import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../audio/host_audio.dart';
import '../device/device_api.dart';
import '../presage/presage_channel.dart';
import '../presage/presage_models.dart';
import '../settings/app_settings.dart';
import '../voice/speech_service.dart';
import '../voice/turn_detector.dart';
import 'awards.dart';
import 'decks.dart';
import 'models.dart';
import 'scoring.dart';
import 'scoring_config.dart';
import 'signal_log.dart';

/// Screens of the game state machine (SPEC.md §4). Pause and End the show
/// are overlays, not phases.
enum GamePhase {
  lobby,
  howToPlay,
  permissions,
  consent,
  calibrate,
  ask,
  answer,
  settle,
  redo,
  callIt,
  countdown,
  verdict,
  sdkOffline,
  leaderboard,
  replay,
}

enum StartBlock { needPlayers, needKey }

enum CalibStage { starting, quiet, chat, done }

/// One warm-up during calibration.
class Warmup {
  Warmup(this.question, this.askedAtMs);

  final String question;

  /// When the host finished reading it (latency counts from here).
  int askedAtMs;
  double? latencyS;
  bool done = false;
  bool skipped = false;
}

/// Live values the measuring screens redraw at ~10 Hz, kept apart from
/// [GameController] so phase changes and signal updates don't rebuild
/// each other.
class LiveState extends ChangeNotifier {
  PresageSample? sample;
  double micLevel = 0;
  String askerText = '';
  String answerText = '';
  final List<double> trace = [];
  SignalIssue? issue;
  int? issueSinceMs;

  /// Hesitation once the player has started answering (s).
  double? hesitationS;

  /// Live blink rate over the current question so far (per min).
  double? questionBlinkRate;
  double? questionMeanPulse;

  void notify() => notifyListeners();

  void resetQuestion() {
    askerText = '';
    answerText = '';
    hesitationS = null;
    questionBlinkRate = null;
    questionMeanPulse = null;
  }
}

/// Status of each permission, for E2.
class PermissionReport {
  const PermissionReport({
    required this.camera,
    required this.mic,
    required this.speech,
    required this.onDevice,
  });

  final String camera;
  final String mic;
  final String speech;
  final bool onDevice;

  bool get cameraOk => camera == 'granted';
  bool get voiceOk => mic == 'granted' && speech == 'authorized' && onDevice;
}

/// Owns the game state machine (SPEC.md §4) and everything measured.
class GameController extends ChangeNotifier {
  GameController({
    required this.presage,
    required this.speech,
    required this.device,
    required this.settings,
    required this.apiKey,
    this.host = const SilentHostAudio(),
    this.haptics = const SystemHaptics(),
    DeckLibrary decks = DeckLibrary.fallback,
    this.config = const ScoringConfig(),
    TurnConfig turnConfig = const TurnConfig(),
    int Function()? now,
    Random? random,
  }) : _decks = decks,
       _turnConfig = turnConfig,
       _now = now ?? (() => clock.now().millisecondsSinceEpoch),
       _random = random ?? Random(),
       scoring = Scoring(config),
       log = SignalLog(config: config) {
    _presageSub = presage.samples.listen(_onSample, onError: (Object _) {});
    _speechSub = speech.events.listen(_onSpeech, onError: (Object _) {});
  }

  final PresageApi presage;
  final SpeechApi speech;
  final DeviceApi device;
  final AppSettings settings;
  final ApiKeyController apiKey;
  final HostAudio host;
  final HapticsApi haptics;
  final ScoringConfig config;
  final Scoring scoring;
  final SignalLog log;
  final LiveState live = LiveState();

  DeckLibrary _decks;
  final TurnConfig _turnConfig;
  final int Function() _now;
  final Random _random;
  late final StreamSubscription<PresageSample> _presageSub;
  late final StreamSubscription<SpeechEvent> _speechSub;
  Timer? _ticker;

  int get nowMs => _now();
  TurnConfig get turnConfig => _turnConfig;

  void setDecks(DeckLibrary decks) => _decks = decks;

  // ---------------------------------------------------------------------------
  // Double-tap guard: the same action twice within 600 ms counts once, so a
  // fast double tap can't skip two players or two questions.

  final Map<String, int> _lastAction = {};

  /// Bumped whenever a game starts or is reset; async flows compare it
  /// after each await so they can't act on a game that no longer exists.
  int _epoch = 0;

  bool _once(String action) {
    final now = nowMs;
    final last = _lastAction[action];
    if (last != null && now - last < 600) return false;
    _lastAction[action] = now;
    return true;
  }

  // ---------------------------------------------------------------------------
  // Lobby state

  final List<Player> players = [];
  GameMode mode = GameMode.party;
  int questionsPerTurn = 5;
  DeckKind deck = DeckKind.mild;
  int _playerSeq = 0;

  static const maxPlayers = 8;
  int get minPlayers => mode == GameMode.party ? 2 : 1;
  bool get canStart => players.length >= minPlayers;

  bool addPlayer(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || players.length >= maxPlayers) return false;
    final clipped = trimmed.length > 20 ? trimmed.substring(0, 20) : trimmed;
    players.add(Player(id: 'p${_playerSeq++}', name: clipped));
    notifyListeners();
    return true;
  }

  void removePlayer(String id) {
    players.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  void setMode(GameMode m) {
    mode = m;
    notifyListeners();
  }

  void setQuestionsPerTurn(int n) {
    questionsPerTurn = n;
    notifyListeners();
  }

  void setDeck(DeckKind d) {
    deck = d;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Game state

  GamePhase phase = GamePhase.lobby;
  bool paused = false;
  bool micEnabled = true;
  bool hasSeenHowToPlay = false;
  bool thermalWarning = false;
  PermissionReport? permissions;
  PresageErrorInfo? sdkError;
  String? notice;

  final List<PlayerTurn> turns = [];
  int playerIndex = 0;
  int questionIndex = 0;
  Awards? awards;

  late DeckDealer _warmups;
  late DeckDealer _questions;

  PlayerTurn get currentTurn => turns[playerIndex];
  Player get currentPlayer => currentTurn.player;
  bool get inGame => phase != GamePhase.lobby && turns.isNotEmpty;

  /// From Calibrate start until the window closes: no haptics (SPEC.md §12).
  bool get isMeasuring =>
      phase == GamePhase.calibrate ||
      phase == GamePhase.ask ||
      phase == GamePhase.answer ||
      phase == GamePhase.settle;

  bool get _sdkShouldRun =>
      phase == GamePhase.calibrate ||
      phase == GamePhase.ask ||
      phase == GamePhase.answer ||
      phase == GamePhase.settle ||
      phase == GamePhase.redo ||
      phase == GamePhase.callIt ||
      phase == GamePhase.countdown ||
      phase == GamePhase.verdict;

  void _setPhase(GamePhase p) {
    phase = p;
    notifyListeners();
  }

  /// Lobby "Start the show". Returns a reason if the game can't start yet;
  /// the Lobby opens Settings for [StartBlock.needKey] (SPEC.md §2).
  Future<StartBlock?> startShow() async {
    if (phase != GamePhase.lobby || !_once('start')) return null;
    if (!canStart) return StartBlock.needPlayers;
    final e = _epoch;
    await apiKey.refresh();
    if (e != _epoch || phase != GamePhase.lobby) return null;
    if (!apiKey.hasKey) return StartBlock.needKey;

    final report = await _checkPermissions(request: true);
    if (e != _epoch || phase != GamePhase.lobby) return null;
    permissions = report;
    if (!report.cameraOk || !report.voiceOk) {
      _setPhase(GamePhase.permissions);
      return null;
    }
    micEnabled = true;
    _beginGame();
    return null;
  }

  Future<PermissionReport> _checkPermissions({required bool request}) async {
    var camera = await device.cameraPermission();
    if (request && camera == 'undetermined') {
      camera = await device.requestCameraPermission() ? 'granted' : 'denied';
    }
    SpeechPermissions voice;
    try {
      voice = await speech.permissionStatus();
      if (request && voice.undetermined) {
        voice = await speech.requestPermissions();
      }
    } on SpeechException {
      voice = SpeechPermissions.unknown;
    }
    return PermissionReport(
      camera: camera,
      mic: voice.mic,
      speech: voice.speech,
      onDevice: voice.onDevice,
    );
  }

  /// E2: re-check after the user comes back from iOS Settings.
  Future<void> recheckPermissions() async {
    if (phase != GamePhase.permissions) return;
    final report = await _checkPermissions(request: false);
    if (phase != GamePhase.permissions) return;
    permissions = report;
    if (report.cameraOk && report.voiceOk) {
      micEnabled = true;
      _beginGame();
    } else {
      notifyListeners();
    }
  }

  /// E2 "Play without voice": no transcripts, tap-to-advance (SPEC.md §7).
  void playWithoutVoice() {
    if (phase != GamePhase.permissions) return;
    if (!(permissions?.cameraOk ?? false)) return;
    micEnabled = false;
    _beginGame();
  }

  Future<void> openAppSettings() => device.openAppSettings();

  void _beginGame() {
    _epoch++;
    turns
      ..clear()
      ..addAll(players.map(PlayerTurn.new));
    _warmups = DeckDealer(_decks.warmup, random: _random);
    _questions = DeckDealer(_decks.main(deck), random: _random);
    playerIndex = 0;
    questionIndex = 0;
    awards = null;
    paused = false;
    notice = micEnabled ? null : 'Playing without voice: tap to move on.';
    unawaited(device.setKeepAwake(true));
    _setPhase(hasSeenHowToPlay ? GamePhase.consent : GamePhase.howToPlay);
  }

  /// E1 "Got it, let's play".
  void dismissHowToPlay() {
    if (phase != GamePhase.howToPlay) return;
    hasSeenHowToPlay = true;
    _setPhase(GamePhase.consent);
  }

  // ---------------------------------------------------------------------------
  // Consent and calibration

  /// "I agree, measure me".
  Future<void> agreeToMeasure() async {
    if (phase != GamePhase.consent || !_once('agree')) return;
    await _beginCalibration();
  }

  /// "Skip my turn" (consent), or Pause "Skip my turn" while calibrating.
  Future<void> skipTurn() async {
    if (phase != GamePhase.consent && phase != GamePhase.calibrate) return;
    if (!_once('skipTurn')) return;
    final e = _epoch;
    if (phase == GamePhase.calibrate) await _stopMeasuring();
    if (e != _epoch) return;
    paused = false;
    currentTurn.skipped = currentTurn.results.isEmpty;
    await _nextPlayer();
  }

  CalibStage calibStage = CalibStage.starting;
  int calibStartMs = 0;
  int? quietStartMs;
  int? chatStartMs;
  final List<Warmup> warmups = [];
  String? calibHint;
  Baseline? _calibBaseline;
  int _lastBaselineCheck = 0;
  bool _calibrationStarting = false;

  Warmup? get currentWarmup =>
      warmups.isEmpty || warmups.last.done ? null : warmups.last;
  int get warmupsDone => warmups.where((w) => w.done).length;
  Baseline? get calibBaseline => _calibBaseline;

  /// Calibrate progress: 0–4 "sit still" blocks.
  int get stillBlocks {
    final start = quietStartMs;
    if (start == null) return 0;
    if (calibStage == CalibStage.chat || calibStage == CalibStage.done) {
      return 4;
    }
    final step = config.calibQuietMs / 4;
    return ((nowMs - start) / step).floor().clamp(0, 4);
  }

  /// Calibrate progress: 0–6 "chat a bit" blocks (2 per warm-up).
  int get chatBlocks {
    var n = 0;
    for (final w in warmups.take(config.calibMaxWarmups)) {
      n += w.done ? 2 : 1;
    }
    return n.clamp(0, config.calibMaxWarmups * 2);
  }

  Future<void> _beginCalibration() async {
    if (_calibrationStarting) return;
    _calibrationStarting = true;
    log.clear();
    live.trace.clear();
    _calibTalk.reset();
    warmups.clear();
    calibHint = null;
    _calibBaseline = null;
    calibStage = CalibStage.starting;
    calibStartMs = nowMs;
    quietStartMs = null;
    chatStartMs = null;
    sdkError = null;
    _recoveries = 0;
    _setPhase(GamePhase.calibrate);
    final e = _epoch;
    try {
      final ok = await _startSdk();
      if (!ok || e != _epoch) return;
      calibStartMs = nowMs;
      _lastSampleMs = nowMs;
      _startTicker();
      await _startListening();
      if (e != _epoch) {
        await _stopMeasuring();
        return;
      }
      // The turn-start jingle ends before the host speaks (SPEC.md §12).
      if (settings.soundEffects) await host.play(Sfx.jingle);
      if (e != _epoch) return;
      await _say('${currentPlayer.name}, sit still and look at the camera.');
    } finally {
      _calibrationStarting = false;
    }
  }

  /// Starts the SmartSpectra session. `reset()` before each player's
  /// calibration (SPEC.md §4). On failure shows E5 and returns false.
  ///
  /// If the game was reset while this was starting, the session is stopped
  /// again so the camera never runs outside a turn.
  Future<bool> _startSdk({bool fromOffline = false}) async {
    final epoch = _epoch;
    try {
      try {
        await presage.reset();
      } on PresageException {
        // Nothing to reset yet.
      }
      await presage.configure(telemetry: settings.telemetry);
      await presage.start();
      if (epoch != _epoch || !(_sdkShouldRun || fromOffline)) {
        await _safeStopSdk();
        return false;
      }
      return true;
    } on PresageException catch (e) {
      if (epoch != _epoch) return false;
      sdkError = PresageErrorInfo(code: e.code, message: e.message);
      _stopTicker();
      _setPhase(GamePhase.sdkOffline);
      return false;
    }
  }

  Future<void> _safeStopSdk() async {
    try {
      await presage.stop();
    } on PresageException {
      // Already stopped.
    }
  }

  Future<void> _startListening() async {
    if (!micEnabled) return;
    try {
      await speech.start();
    } on SpeechException catch (e) {
      _fallBackToNoVoice(e.code);
    }
  }

  void _fallBackToNoVoice(String code) {
    if (!micEnabled) return;
    micEnabled = false;
    notice = code == 'ON_DEVICE_UNAVAILABLE'
        ? "On-device speech isn't available, so it's tap-to-advance now."
        : 'Voice recognition stopped, so it\'s tap-to-advance now.';
    unawaited(speech.stop().catchError((Object _) {}));
    notifyListeners();
  }

  /// "Doesn't apply? Next one".
  void skipWarmup() {
    if (phase != GamePhase.calibrate) return;
    final w = currentWarmup;
    if (w == null) return;
    w
      ..done = true
      ..skipped = true;
    _afterWarmup();
  }

  final TalkTracker _calibTalk = TalkTracker(const TurnConfig());

  void _tickCalibration(int now) {
    if (calibStage == CalibStage.starting) {
      if (live.sample?.status == PresageStatus.running) {
        calibStage = CalibStage.quiet;
        quietStartMs = now;
        notifyListeners();
      } else if (now - calibStartMs > 20000) {
        _recoverSdk('the vitals engine never started');
      }
      return;
    }
    if (calibStage == CalibStage.quiet) {
      if (now - quietStartMs! >= config.calibQuietMs) {
        calibStage = CalibStage.chat;
        chatStartMs = now;
        _askWarmup();
      }
      notifyListeners();
      return;
    }
    if (calibStage != CalibStage.chat) return;

    for (final (talking, t) in _calibTalk.settle(now)) {
      _onCalibTalk(talking, t);
    }
    final w = currentWarmup;
    if (w != null) {
      final lastEnd = _calibTalk.lastEndMs;
      final answered =
          w.latencyS != null &&
          !_calibTalk.talking &&
          lastEnd != null &&
          now - lastEnd >= 1500;
      if (answered || now - w.askedAtMs >= 12000) {
        w.done = true;
        _afterWarmup();
        // Finishing the last warm-up may have ended calibration already.
        if (phase != GamePhase.calibrate) return;
      }
    }

    if (now - _lastBaselineCheck >= 500) {
      _lastBaselineCheck = now;
      _calibBaseline = scoring.baseline(
        log,
        start: quietStartMs!,
        quietEnd: chatStartMs ?? now,
        end: now,
        warmupLatenciesS: [
          for (final w in warmups)
            if (w.latencyS != null) w.latencyS!,
        ],
      );
      final valid = scoring.baselineValid(_calibBaseline);
      if (valid && warmupsDone >= config.calibMinWarmups) {
        _finishCalibration();
        return;
      }
      if (!valid && now - calibStartMs >= config.calibHintAfterMs) {
        calibHint = _calibrationHintText(now);
      }
    }
    notifyListeners();
  }

  String _calibrationHintText(int now) {
    final issues = log.validationIssues(now - 5000, now);
    for (final (code, _, _) in issues) {
      final issue = SignalIssue.fromCode(code);
      if (issue != null) return '${issue.title}. ${issue.fix}';
    }
    return 'Still warming up. Keep your face in the oval and hold the phone steady.';
  }

  void _onCalibTalk(bool talking, int t) {
    final w = currentWarmup;
    if (talking && w != null && w.latencyS == null && t >= w.askedAtMs) {
      w.latencyS = (t - w.askedAtMs) / 1000;
    }
  }

  Future<void> _askWarmup() async {
    final question = _warmups.next();
    final w = Warmup(question, nowMs);
    warmups.add(w);
    notifyListeners();
    await _say(question);
    // Latency counts from the end of the host's reading.
    if (!w.done && w.latencyS == null) w.askedAtMs = nowMs;
  }

  void _afterWarmup() {
    if (phase != GamePhase.calibrate) return;
    final valid = scoring.baselineValid(_calibBaseline);
    if (valid && warmupsDone >= config.calibMinWarmups) {
      _finishCalibration();
      return;
    }
    // Keep chatting until the baseline is valid (SPEC.md §4: stay / hints).
    unawaited(_askWarmup());
  }

  void _finishCalibration() {
    if (phase != GamePhase.calibrate || calibStage == CalibStage.done) return;
    calibStage = CalibStage.done;
    currentTurn.baseline = _calibBaseline;
    calibHint = null;
    // Normally 0; after a mid-turn recalibration, carry on where we were.
    questionIndex = currentTurn.results.length;
    if (questionIndex >= questionsPerTurn) {
      unawaited(_endTurn());
      return;
    }
    _beginQuestion();
  }

  // ---------------------------------------------------------------------------
  // Questions

  TurnDetector? detector;
  String questionText = '';
  int questionStartMs = 0;
  int? _askerFromSeg;
  int? _answerFromSeg;
  final TranscriptBuffer _askerTranscript = TranscriptBuffer();
  final TranscriptBuffer _answerTranscript = TranscriptBuffer();
  int? settleUntilMs;
  QuestionResult? currentResult;
  int _soloReadEndsAt = 0;

  /// The player in the hot seat starts answering; question text for display.
  String get displayQuestion => mode == GameMode.solo
      ? questionText
      : (live.askerText.isEmpty ? '' : live.askerText);

  void _beginQuestion({String? repeat}) {
    detector = TurnDetector(
      party: mode == GameMode.party,
      micEnabled: micEnabled,
      startMs: nowMs,
      config: _turnConfig,
    );
    questionStartMs = nowMs;
    settleUntilMs = null;
    currentResult = null;
    _askerTranscript.clear();
    _answerTranscript.clear();
    _askerFromSeg = null;
    _answerFromSeg = null;
    live.resetQuestion();
    questionText = mode == GameMode.solo ? (repeat ?? _questions.next()) : '';
    _setPhase(GamePhase.ask);
    if (mode == GameMode.party) unawaited(_say('Ask your question!'));
    if (micEnabled) {
      unawaited(
        speech
            .newSegment()
            .then((seg) => _askerFromSeg = seg)
            .catchError((Object _) => null),
      );
    }
    if (mode == GameMode.solo) unawaited(_soloReadQuestion());
  }

  Future<void> _soloReadQuestion() async {
    final text = questionText;
    // Fallback timing when the host voice is off: rough reading time.
    _soloReadEndsAt = nowMs + 1500 + 55 * text.length;
    await _say('Here\'s one for you, ${currentPlayer.name}. $text');
    if (phase == GamePhase.ask && questionText == text && settings.hostVoice) {
      _apply(detector?.onHostFinishedQuestion(nowMs) ?? const []);
    }
  }

  /// Solo "Different question".
  void differentQuestion() {
    if (mode != GameMode.solo || phase != GamePhase.ask) return;
    unawaited(host.stopSpeaking());
    _beginQuestion();
  }

  /// "Too loud? Tap when done asking" / "Done asking".
  void doneAsking() {
    if (phase != GamePhase.ask) return;
    _apply(detector?.onDoneAskingTap(nowMs) ?? const []);
  }

  /// "Final answer".
  void finalAnswer() {
    if (phase != GamePhase.answer && phase != GamePhase.ask) return;
    _apply(detector?.onFinalAnswerTap(nowMs) ?? const []);
  }

  void _apply(List<TurnEvent> events) {
    for (final e in events) {
      switch (e) {
        case QuestionEnded():
          _onQuestionEnded(e);
        case AnswerStarted():
          final d = detector!;
          live.hesitationS =
              max(0, e.tMs - (d.hesitationFromMs ?? e.tMs)) / 1000;
          live.notify();
        case AnswerEnded():
          _onAnswerEnded();
      }
    }
  }

  void _onQuestionEnded(QuestionEnded e) {
    _setPhase(GamePhase.answer);
    if (micEnabled) {
      unawaited(
        speech
            .newSegment()
            .then((seg) => _answerFromSeg = seg)
            .catchError((Object _) => null),
      );
    }
    if (e.hostShouldPrompt) {
      unawaited(
        _say('${currentPlayer.name}, your answer?').then((_) {
          detector?.onHostPromptFinished(nowMs);
        }),
      );
    }
  }

  void _onAnswerEnded() {
    final timing = detector!.timing();
    settleUntilMs = timing.windowEnd(config.minWindowAfterQuestionMs);
    _setPhase(GamePhase.settle);
    _tickSettle(nowMs);
  }

  void _tickSettle(int now) {
    final until = settleUntilMs;
    if (until != null && now >= until) _evaluate();
  }

  void _evaluate() {
    final d = detector;
    final base = currentTurn.baseline;
    if (d == null || base == null) return;
    final timing = d.timing();
    final features = scoring.features(log, timing, base);
    final t1 = timing.windowEnd(config.minWindowAfterQuestionMs);
    final spark = [for (final p in log.confidentPulse(timing.tQ0, t1)) p.bpm];
    final question = mode == GameMode.solo
        ? questionText
        : (_askerTranscript.text.isNotEmpty
              ? _askerTranscript.text
              : 'Question ${questionIndex + 1}');
    if (!scoring.isClean(features)) {
      currentResult = QuestionResult(
        index: questionIndex,
        question: question,
        answer: _answerTranscript.text,
        timing: timing,
        features: features,
        noCleanReadReasons: scoring.noCleanReadReasons(
          log,
          timing,
          currentPlayer.name,
        ),
        noCleanReadTitle: scoring.noCleanReadTitle(log, timing),
        pulseSpark: spark,
        basePulse: base.pulse,
        baseBlinkRate: base.blinkRatePerMin,
      );
      _setPhase(GamePhase.redo);
      return;
    }
    final result = QuestionResult(
      index: questionIndex,
      question: question,
      answer: _answerTranscript.text,
      timing: timing,
      features: features,
      breakdown: scoring.score(features, base),
      pulseSpark: spark,
      basePulse: base.pulse,
      baseBlinkRate: base.blinkRatePerMin,
    );
    currentResult = result;
    currentTurn.results.add(result);
    if (mode == GameMode.party && voters.isNotEmpty) {
      _beginCallIt();
    } else {
      _beginCountdown();
    }
  }

  /// E4 "Ask it again".
  void askAgain() {
    if (phase != GamePhase.redo || !_once('askAgain')) return;
    _beginQuestion(repeat: mode == GameMode.solo ? questionText : null);
  }

  /// E4 "Skip it", Pause "Skip question", E3 "Skip question".
  Future<void> skipQuestion() async {
    const allowed = {
      GamePhase.ask,
      GamePhase.answer,
      GamePhase.settle,
      GamePhase.redo,
    };
    if (!inGame || !allowed.contains(phase) || !_once('skipQuestion')) return;
    final q = mode == GameMode.solo
        ? questionText
        : (_askerTranscript.text.isEmpty
              ? 'Question ${questionIndex + 1}'
              : _askerTranscript.text);
    currentTurn.results.add(
      QuestionResult(
        index: questionIndex,
        question: q,
        answer: _answerTranscript.text,
        timing: null,
        skipped: true,
      ),
    );
    paused = false;
    await _afterQuestion();
  }

  // ---------------------------------------------------------------------------
  // Call it! (room vote, SPEC.md §5.6)

  final Map<String, Vote> pendingVotes = {};
  int callItDeadlineMs = 0;
  static const callItTimeoutMs = 10000;

  /// Everyone except the hot seat.
  List<Player> get voters => [
    for (final t in turns)
      if (t.player.id != currentPlayer.id) t.player,
  ];

  void _beginCallIt() {
    pendingVotes.clear();
    callItDeadlineMs = nowMs + callItTimeoutMs;
    _setPhase(GamePhase.callIt);
    unawaited(_say('Call it! Legit or sus?'));
  }

  /// Tapping a voter's chip cycles unset → Legit → Sus → unset.
  void cycleVote(String voterId) {
    if (phase != GamePhase.callIt) return;
    final current = pendingVotes[voterId];
    if (current == null) {
      pendingVotes[voterId] = Vote.legit;
    } else if (current == Vote.legit) {
      pendingVotes[voterId] = Vote.sus;
    } else {
      pendingVotes.remove(voterId);
    }
    notifyListeners();
  }

  void reveal() {
    if (phase != GamePhase.callIt) return;
    currentResult?.votes.addAll(pendingVotes);
    _beginCountdown();
  }

  // ---------------------------------------------------------------------------
  // Countdown and verdict

  int countdownValue = 3;
  int _countdownNextAt = 0;

  void _beginCountdown() {
    countdownValue = 3;
    _countdownNextAt = nowMs + 1000;
    _setPhase(GamePhase.countdown);
    if (settings.soundEffects) unawaited(host.play(Sfx.drumroll));
    _haptic(HapticCue.countdownTick);
  }

  void _tickCountdown(int now) {
    if (now < _countdownNextAt) return;
    _countdownNextAt = now + 1000;
    countdownValue--;
    if (countdownValue <= 0) {
      _showVerdict();
    } else {
      _haptic(HapticCue.countdownTick);
      notifyListeners();
    }
  }

  void _showVerdict() {
    _setPhase(GamePhase.verdict);
    final verdict = currentResult?.verdict;
    if (verdict == null) return;
    final (sfx, cue) = switch (verdict) {
      Verdict.legit => (Sfx.dingDing, HapticCue.legit),
      Verdict.hmm => (Sfx.wahWah, HapticCue.hmm),
      Verdict.sus => (Sfx.buzzer, HapticCue.sus),
    };
    _haptic(cue);
    unawaited(() async {
      if (settings.soundEffects) await host.play(sfx);
      await _say(switch (verdict) {
        Verdict.legit => 'Legit!',
        Verdict.hmm => 'Hmm…',
        Verdict.sus => 'Sus!',
      });
    }());
  }

  bool get isLastQuestion => questionIndex >= questionsPerTurn - 1;
  bool get isLastPlayer => playerIndex >= turns.length - 1;

  /// Verdict "Next question".
  Future<void> nextQuestion() async {
    if (phase != GamePhase.verdict || !_once('next')) return;
    await _afterQuestion();
  }

  /// Verdict "End turn".
  Future<void> endTurn() async {
    if (phase != GamePhase.verdict || !_once('next')) return;
    await _endTurn();
  }

  Future<void> _afterQuestion() async {
    if (isLastQuestion) {
      await _endTurn();
    } else {
      questionIndex++;
      _beginQuestion();
    }
  }

  Future<void> _endTurn() async {
    final e = _epoch;
    await _stopMeasuring();
    final thermal = await device.thermalState();
    if (e != _epoch) return;
    thermalWarning = thermal == 'serious' || thermal == 'critical';
    await _nextPlayer();
  }

  Future<void> _nextPlayer() async {
    if (turns.isEmpty) {
      _setPhase(GamePhase.lobby);
      return;
    }
    if (playerIndex < turns.length - 1) {
      playerIndex++;
      questionIndex = 0;
      _setPhase(GamePhase.consent);
    } else {
      _showLeaderboard();
    }
  }

  Future<void> _stopMeasuring() async {
    _stopTicker();
    detector = null;
    if (micEnabled) {
      await speech.stop().catchError((Object _) {});
    }
    await host.stopSpeaking().catchError((Object _) {});
    try {
      await presage.stop();
    } on PresageException {
      // Already stopped.
    }
  }

  void _showLeaderboard() {
    if (turns.isEmpty) {
      _setPhase(GamePhase.lobby);
      return;
    }
    awards = Awards.compute(turns, mode: mode);
    unawaited(device.setKeepAwake(false));
    _setPhase(GamePhase.leaderboard);
    if (awards!.ranked.isNotEmpty) {
      _haptic(HapticCue.award);
      unawaited(() async {
        await _say('And the winners are…');
        if (settings.soundEffects) await host.play(Sfx.applause);
      }());
    }
  }

  void openReplay() {
    if (phase == GamePhase.leaderboard) _setPhase(GamePhase.replay);
  }

  void backToLeaderboard() {
    if (phase == GamePhase.replay) _setPhase(GamePhase.leaderboard);
  }

  /// Leaderboard / Replay "Play again": same contestants, scores wiped.
  Future<void> playAgain() async {
    await _resetGame(keepPlayers: true);
  }

  /// "Wipe everything" (Replay) and "Wipe all game data now" (Settings).
  Future<void> wipeAll() async {
    await _resetGame(keepPlayers: false);
  }

  Future<void> _resetGame({required bool keepPlayers}) async {
    // Any async flow still in flight for the old game sees the new epoch
    // and bails out.
    _epoch++;
    await _stopMeasuring();
    turns.clear();
    awards = null;
    currentResult = null;
    detector = null;
    log.clear();
    live
      ..resetQuestion()
      ..trace.clear()
      ..sample = null;
    paused = false;
    sdkError = null;
    if (!keepPlayers) players.clear();
    unawaited(device.setKeepAwake(false));
    _setPhase(GamePhase.lobby);
  }

  /// E6 "End and see scores". Crowns winners from what's been played.
  Future<void> endShowEarly() async {
    if (!inGame) return;
    final e = _epoch;
    if (_sdkShouldRun) await _stopMeasuring();
    if (e != _epoch) return;
    paused = false;
    final anyPlayed = turns.any((t) => t.results.isNotEmpty);
    if (anyPlayed) {
      _showLeaderboard();
    } else {
      await _resetGame(keepPlayers: true);
    }
  }

  /// E5 "Try again".
  /// E5 "Try again". If the player was already calibrated, the SDK restarts
  /// and the interrupted question is asked again; otherwise calibration
  /// starts over.
  Future<void> retrySdk() async {
    if (phase != GamePhase.sdkOffline || !_once('retry')) return;
    if (currentTurn.baseline == null) {
      await _beginCalibration();
      return;
    }
    sdkError = null;
    _recoveries = 0;
    final e = _epoch;
    if (!await _startSdk(fromOffline: true) || e != _epoch) return;
    _lastSampleMs = nowMs;
    live.sample = null;
    _startTicker();
    await _startListening();
    if (e != _epoch) return;
    if (currentTurn.results.length >= questionsPerTurn) {
      await _endTurn();
    } else {
      questionIndex = currentTurn.results.length;
      _beginQuestion(repeat: mode == GameMode.solo ? questionText : null);
    }
  }

  /// E5 "Back to lobby" and the consent back button.
  Future<void> backToLobby() => _resetGame(keepPlayers: true);

  /// Summary for E6: who played how many questions, who hasn't played.
  (List<(Player, int)>, List<Player>) playedSummary() {
    final played = <(Player, int)>[];
    final notYet = <Player>[];
    for (var i = 0; i < turns.length; i++) {
      final t = turns[i];
      final n = t.questionsPlayed;
      if (n > 0) {
        played.add((t.player, n));
      } else if (!t.skipped &&
          (i > playerIndex ||
              (i == playerIndex && phase == GamePhase.consent))) {
        notYet.add(t.player);
      }
    }
    return (played, notYet);
  }

  // ---------------------------------------------------------------------------
  // Pause and app lifecycle

  bool _needsRestart = false;

  void pause() {
    if (!inGame || !isMeasuring) return;
    paused = true;
    unawaited(host.stopSpeaking().catchError((Object _) {}));
    notifyListeners();
  }

  /// Pause "Resume". A question that was interrupted starts over, since its
  /// measurement window was broken.
  Future<void> resume() async {
    if (!paused) return;
    paused = false;
    notifyListeners();
    if (_needsRestart) {
      _needsRestart = false;
      if (phase == GamePhase.calibrate) {
        await _beginCalibration();
        return;
      }
      final e = _epoch;
      if (!await _startSdk() || e != _epoch) return;
      _lastSampleMs = nowMs;
      _startTicker();
      await _startListening();
      if (e != _epoch) return;
    }
    if (phase == GamePhase.ask ||
        phase == GamePhase.answer ||
        phase == GamePhase.settle) {
      _beginQuestion(repeat: mode == GameMode.solo ? questionText : null);
    }
  }

  /// The app went to the background: iOS stops the camera, so stop cleanly
  /// and restart on resume.
  Future<void> onAppBackgrounded() async {
    if (!_sdkShouldRun) return;
    paused = true;
    _needsRestart = true;
    _stopTicker();
    if (micEnabled) await speech.stop().catchError((Object _) {});
    await host.stopSpeaking().catchError((Object _) {});
    try {
      await presage.stop();
    } on PresageException {
      // Already stopped.
    }
    notifyListeners();
  }

  Future<void> onAppResumed() async {
    if (phase == GamePhase.permissions) await recheckPermissions();
  }

  // ---------------------------------------------------------------------------
  // Signals

  int _lastSampleMs = 0;
  int _recoveries = 0;

  void _onSample(PresageSample s) {
    _lastSampleMs = nowMs;
    live.sample = s;
    if (s.trace.isNotEmpty) {
      live.trace.addAll(s.trace);
      if (live.trace.length > 240) {
        live.trace.removeRange(0, live.trace.length - 240);
      }
    }
    if (!_sdkShouldRun) {
      live.notify();
      return;
    }
    log.add(s);

    // E3: a validation problem that lasts more than 1.5 s.
    final issue = SignalIssue.fromCode(s.validation?.code);
    if (issue == null) {
      live.issue = null;
      live.issueSinceMs = null;
    } else if (live.issueSinceMs == null || live.issue?.code != issue.code) {
      live.issueSinceMs = s.tMs;
      live.issue = issue;
    }

    for (final e in s.events) {
      if (e.type == PresageEdgeType.blink) continue;
      final talking = e.type == PresageEdgeType.talkStart;
      if (phase == GamePhase.calibrate) {
        for (final (t, at) in _calibTalk.edge(talking, e.tMs)) {
          _onCalibTalk(t, at);
        }
      } else if (!paused) {
        _apply(detector?.onPlayerTalkEdge(talking, e.tMs) ?? const []);
      }
    }

    if (phase == GamePhase.answer || phase == GamePhase.settle) {
      final d = detector;
      final from = d?.tQ0 ?? questionStartMs;
      live.questionBlinkRate = nowMs - from > 3000
          ? log.blinkRatePerMin(from, nowMs)
          : null;
      final pulses = log.confidentPulse(from, nowMs);
      live.questionMeanPulse = pulses.isEmpty
          ? null
          : pulses.map((p) => p.bpm).reduce((a, b) => a + b) / pulses.length;
    }
    live.notify();
  }

  /// Shows E3 only once an issue has lasted 1.5 s.
  SignalIssue? get visibleIssue {
    final since = live.issueSinceMs;
    if (live.issue == null || since == null) return null;
    return nowMs - since >= 1500 ? live.issue : null;
  }

  void _onSpeech(SpeechEvent e) {
    switch (e) {
      case SpeechText():
        _onSpeechText(e);
      case SpeechLevel():
        live.micLevel = e.level;
        if (!paused && (phase == GamePhase.ask || phase == GamePhase.answer)) {
          _apply(detector?.onLevel(e.level, e.tMs) ?? const []);
        }
        live.notify();
      case SpeechStateChange():
        break;
      case SpeechError():
        if (e.code == 'RECOGNIZER_FAILING' ||
            e.code == 'ON_DEVICE_UNAVAILABLE') {
          _fallBackToNoVoice(e.code);
        }
    }
  }

  /// Files recognized text under the question or the answer by segment
  /// (SPEC.md §7). Transcripts stay in memory only.
  void _onSpeechText(SpeechText e) {
    if (!micEnabled) return;
    if (phase != GamePhase.ask &&
        phase != GamePhase.answer &&
        phase != GamePhase.settle) {
      return;
    }
    final askerFrom = _askerFromSeg;
    if (askerFrom != null && e.segment < askerFrom) return;
    final answerFrom = _answerFromSeg;
    // Text from before the answer's segment is the tail of the question.
    // In solo mode there's no human asker: early speech is the answer.
    final isQuestion =
        mode == GameMode.party &&
        (phase == GamePhase.ask ||
            answerFrom == null ||
            e.segment < answerFrom);
    if (isQuestion) {
      _askerTranscript.add(e);
      live.askerText = _askerTranscript.text;
    } else {
      _answerTranscript.add(e);
      live.answerText = _answerTranscript.text;
    }
    if (!paused) _apply(detector?.onSpeech(e.tMs) ?? const []);
    live.notify();
  }

  // ---------------------------------------------------------------------------
  // Ticker (~10 Hz while a turn runs) and self-healing

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _tick() {
    final now = nowMs;
    if (paused) return;
    switch (phase) {
      case GamePhase.calibrate:
        _tickCalibration(now);
      case GamePhase.ask:
        // Host voice off: the question "ends" after a rough reading time.
        if (mode == GameMode.solo &&
            !settings.hostVoice &&
            now >= _soloReadEndsAt) {
          _apply(detector?.onHostFinishedQuestion(now) ?? const []);
        }
        _apply(detector?.tick(now) ?? const []);
        notifyListeners();
      case GamePhase.answer:
        _apply(detector?.tick(now) ?? const []);
        notifyListeners();
      case GamePhase.settle:
        _tickSettle(now);
        notifyListeners();
      case GamePhase.callIt:
        if (now >= callItDeadlineMs) reveal();
      case GamePhase.countdown:
        _tickCountdown(now);
      default:
        break;
    }
    _watchdog(now);
  }

  /// Self-healing: if the SDK stops sending while it should be measuring,
  /// or reports an error, restart it; after repeated failures show E5.
  void _watchdog(int now) {
    if (!isMeasuring || paused || _recovering) return;
    final status = live.sample?.status;
    final silent = now - _lastSampleMs > 6000;
    if (status != _watchStatus) {
      _watchStatus = status;
      _watchStatusSince = now;
    }
    final stuck =
        (status == PresageStatus.starting ||
            status == PresageStatus.stopping) &&
        now - _watchStatusSince > 15000 &&
        !(phase == GamePhase.calibrate && calibStage == CalibStage.starting);
    if (silent || status == PresageStatus.error || stuck) {
      _recoverSdk(
        silent
            ? 'no signal for 6 seconds'
            : (stuck ? 'stuck while ${status!.name}' : 'SDK error'),
      );
    }
  }

  bool _recovering = false;
  PresageStatus? _watchStatus;
  int _watchStatusSince = 0;

  Future<void> _recoverSdk(String why) async {
    if (_recovering) return;
    _recovering = true;
    try {
      _recoveries++;
      final error = live.sample?.error;
      final fatal =
          error != null && ApiKeyController.keyErrorCodes.contains(error.code);
      if (_recoveries > 2 || fatal) {
        _stopTicker();
        sdkError =
            error ??
            PresageErrorInfo(
              code: 'NO_SIGNAL',
              message: 'Lost the signal: $why.',
            );
        try {
          await presage.stop();
        } on PresageException {
          // Already stopped.
        }
        _setPhase(GamePhase.sdkOffline);
        return;
      }
      final e = _epoch;
      await _safeStopSdk();
      if (e != _epoch || !_sdkShouldRun) return;
      if (!await _startSdk() || e != _epoch) return;
      _lastSampleMs = nowMs;
      live.sample = null;
      if (phase == GamePhase.calibrate && calibStage == CalibStage.starting) {
        calibStartMs = nowMs;
      }
      if (phase == GamePhase.ask ||
          phase == GamePhase.answer ||
          phase == GamePhase.settle) {
        _beginQuestion(repeat: mode == GameMode.solo ? questionText : null);
      }
    } finally {
      _recovering = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Host voice and haptics

  /// Speaks a host line if the voice is on. Completes when done.
  Future<void> _say(String text) async {
    hostLine = text;
    notifyListeners();
    if (!settings.hostVoice) return;
    try {
      await host.say(text);
    } catch (_) {
      // Voice is a nice-to-have; never block the game on it.
    }
  }

  /// The last thing the host said (captions, SPEC.md §3).
  String hostLine = '';

  void _haptic(HapticCue cue) {
    if (!settings.haptics || isMeasuring) return;
    unawaited(haptics.cue(cue).catchError((Object _) {}));
  }

  @override
  void dispose() {
    _stopTicker();
    _presageSub.cancel();
    _speechSub.cancel();
    live.dispose();
    super.dispose();
  }
}
