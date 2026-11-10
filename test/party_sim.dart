// A party of made-up people playing whole games through the real
// GameController on fake time, to measure what a room goes through: how long
// each step takes, how often a screen has nothing to tap, how often a question
// has to be asked again, which taps do nothing, and how the awards fall.
//
// The people are assumptions, not measurements: how fast they tap, how long
// they talk, how often they look away from the camera. They're set on the
// messy side so the numbers are a fair bar. `test/party_sim_test.dart` holds
// the bars; run it with PARTY_SIM_REPORT=1 to print the tables.
import 'dart:async';
import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:susometer/game/awards.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';

import 'world.dart';

/// How one person plays. Times are (shortest, longest) in ms.
class Persona {
  const Persona(
    this.kind, {
    this.tap = (700, 1800),
    this.readConsent = (3000, 9000),
    this.warmupAnswer = (2000, 5000),
    this.warmupSkip = 0.05,
    this.askThink = (800, 4000),
    this.askSpeak = (1800, 4000),
    this.answerPause = (500, 1800),
    this.answerSpeak = (1500, 6000),
    this.finalTap = (600, 2000),
    this.forgetsDoneAsking = 0.1,
    this.forgetsFinalAnswer = 0.05,
    this.glance = 0.25,
    this.wiggle = 0.1,
    this.voteDelay = (1200, 6000),
    this.abstain = 0.08,
    this.changesMind = 0.08,
    this.verdictRead = (3000, 8000),
    this.screenshot = 0.03,
    this.stressed = 0.2,
    this.skipsTurn = 0.0,
    this.eagerReveal = false,
  });

  final String kind;
  final (int, int) tap;
  final (int, int) readConsent;
  final (int, int) warmupAnswer;

  /// Chance a warm-up gets "Doesn't apply".
  final double warmupSkip;

  /// As the asker: thinking of a question, then saying it.
  final (int, int) askThink;
  final (int, int) askSpeak;

  /// In the hot seat: the pause before answering, then the answer.
  final (int, int) answerPause;
  final (int, int) answerSpeak;
  final (int, int) finalTap;

  /// Chance of answering straight away, with Done asking tapped afterwards.
  final double forgetsDoneAsking;

  /// Chance Final answer comes 8–20 s late.
  final double forgetsFinalAnswer;

  /// Chance of looking at the asker during the question (no face, 1–2.5 s).
  final double glance;

  /// Chance of a laugh or a shaky hand during the answer (moving, 1–3 s).
  final double wiggle;

  /// As a voter.
  final (int, int) voteDelay;
  final double abstain;
  final double changesMind;
  final (int, int) verdictRead;

  /// Chance of a screenshot (3 s out of the app) on a verdict.
  final double screenshot;

  /// Chance an answer comes with a clear stress reaction.
  final double stressed;
  final double skipsTurn;

  /// Taps Reveal as soon as their own vote is in.
  final bool eagerReveal;

  static const steady = Persona('steady');
  static const eager = Persona(
    'eager',
    tap: (350, 800),
    readConsent: (1200, 3000),
    askThink: (300, 1200),
    answerPause: (300, 900),
    finalTap: (300, 800),
    voteDelay: (600, 2000),
    verdictRead: (1500, 3500),
    eagerReveal: true,
  );
  static const slow = Persona(
    'slow',
    tap: (1800, 4500),
    readConsent: (9000, 20000),
    askThink: (4000, 12000),
    answerPause: (1500, 4000),
    answerSpeak: (4000, 12000),
    finalTap: (2000, 6000),
    voteDelay: (4000, 12000),
    verdictRead: (6000, 14000),
  );
  static const forgetful = Persona(
    'forgetful',
    forgetsDoneAsking: 0.5,
    forgetsFinalAnswer: 0.35,
    abstain: 0.25,
  );
  static const fidgety = Persona(
    'fidgety',
    glance: 0.7,
    wiggle: 0.5,
    screenshot: 0.1,
    changesMind: 0.25,
  );
  static const nervous = Persona('nervous', stressed: 0.55, warmupSkip: 0.2);

  static const all = [steady, eager, slow, forgetful, fidgety, nervous];
}

/// What happened in one question.
class QuestionLog {
  QuestionLog(this.hotSeat, this.asker);

  final String hotSeat;
  final String? asker;
  bool stressed = false;
  int asksNeeded = 1;
  bool skipped = false;
  int pulseWaitMs = 0;
  int settleMs = 0;
  int callItMs = 0;
  int totalMs = 0;
  int votesCast = 0;
  int votesLost = 0;
  Verdict? verdict;
  int? score;
}

/// A tap that changed nothing, and where.
class DeadTap {
  DeadTap(this.what, this.phase);

  final String what;
  final GamePhase phase;

  @override
  String toString() => '$what on ${phase.name}';
}

class PartyReport {
  PartyReport(this.players, this.questionsPerTurn);

  final int players;
  final int questionsPerTurn;
  int totalMs = 0;

  /// Time on each kind of screen (ms). Keys are phase names, with calibrate
  /// split into its steps and "pulseWait" taken out of ask.
  final Map<String, int> time = {};
  final List<QuestionLog> questions = [];
  final List<DeadTap> deadTaps = [];
  final Map<String, int> asked = {};
  int taps = 0;
  int turnsSkipped = 0;
  int calibrations = 0;
  int calibrationMs = 0;
  Awards? awards;
  List<PlayerTurn> turns = const [];
  bool finished = false;

  /// Time with nothing to do but wait: the sit-still, the lock-in, a wait
  /// for the pulse and the countdown.
  int get waitMs =>
      (time['calibrate.starting'] ?? 0) +
      (time['calibrate.quiet'] ?? 0) +
      (time['settle'] ?? 0) +
      (time['pulseWait'] ?? 0) +
      (time['countdown'] ?? 0);

  Iterable<QuestionLog> get played => questions.where((q) => !q.skipped);
}

/// Thrown when the game stops moving: the report's most important finding.
class Stuck implements Exception {
  Stuck(this.what, this.phase);

  final String what;
  final GamePhase phase;

  @override
  String toString() => 'Stuck waiting for $what (phase ${phase.name})';
}

class PartySim {
  PartySim(
    this.async, {
    required this.people,
    this.questions = 5,
    int seed = 1,
    this.pulseRecoveryMs = 3000,
    this.hostVoice = true,
  }) : rng = math.Random(seed),
       w = World(async),
       report = PartyReport(people.length, questions) {
    w
      ..autoTaps = false
      ..autoAnswerWarmups = false
      ..host.hold = hostVoice
      ..settings.hostVoice = hostVoice
      ..codeAt = _codeAt;
    _clock = Timer.periodic(const Duration(milliseconds: 100), (_) => _beat());
  }

  final FakeAsync async;
  final List<(String, Persona)> people;
  final int questions;
  final math.Random rng;
  final World w;
  final PartyReport report;

  /// How long the camera needs a face back in view before its pulse is
  /// confident again (the SDK's pulse is a 12 s average). Unknown on a
  /// device; 3 s by default, and the test also runs it at 10 s.
  final int pulseRecoveryMs;
  final bool hostVoice;
  late final Timer _clock;

  GameController get game => w.game;

  // --- The camera's view of the hot seat ------------------------------------

  /// When the face is out of view or moving: (from, to, code).
  final List<(int, int, String)> _away = [];
  int _faceOkSince = 0;

  void _lookAway(int ms, String code, {int inMs = 0}) =>
      _away.add((w.now + inMs, w.now + inMs + ms, code));

  String? _codeAt(int t) {
    for (final (from, to, code) in _away) {
      if (t >= from && t < to) return code;
    }
    return null;
  }

  // --- Clockwork: the host's voice, the pulse, the time sheet ---------------

  int _linesSeen = 0;
  int _soundsSeen = 0;
  GamePhase? _lastPhase;
  int _phaseSince = 0;

  void _beat() {
    final now = w.now;
    // Each host line takes about as long as it takes to say.
    while (_linesSeen < w.host.said.length) {
      final i = _linesSeen++;
      final ms = 500 + 55 * w.host.said[i].length;
      Timer(Duration(milliseconds: ms), () => w.host.finishLine(i));
    }
    if (_soundsSeen < w.host.played.length) {
      _soundsSeen = w.host.played.length;
      Timer(const Duration(milliseconds: 900), w.host.finishSounds);
    }
    // The pulse is confident only once the face has been back a while.
    final code = _codeAt(now);
    if (code == 'NO_FACE_FOUND') _faceOkSince = now + 100;
    w.pulseConf = now - _faceOkSince >= pulseRecoveryMs ? 0.9 : 0.2;
    _away.removeWhere((a) => a.$2 < now - 1000);

    if (game.phase != _lastPhase) {
      _lastPhase = game.phase;
      _phaseSince = now;
    }
    final key = switch (game.phase) {
      GamePhase.calibrate => 'calibrate.${game.calibStage.name}',
      GamePhase.ask when game.waitingForPulse => 'pulseWait',
      final p => p.name,
    };
    report.time[key] = (report.time[key] ?? 0) + 100;
  }

  // --- People ---------------------------------------------------------------

  int _between((int, int) range) =>
      range.$1 + rng.nextInt(math.max(1, range.$2 - range.$1));
  bool _chance(double p) => rng.nextDouble() < p;

  void _wait(int ms) => w.elapse(ms);

  void _until(bool Function() cond, String what, {int maxMs = 180000}) {
    var waited = 0;
    while (!cond()) {
      w.elapse(100);
      waited += 100;
      if (waited > maxMs) throw Stuck(what, game.phase);
    }
  }

  /// A deliberate tap on [what]. The screen ignores touches for 450 ms after
  /// it changes (game_root.dart's phase tap guard), so a tap that soon is
  /// held back the way a person's would be. Counted dead if nothing changed.
  bool _tap(String what, void Function() action) {
    final guard = 450 - (w.now - _phaseSince);
    if (guard > 0) _wait(guard);
    report.taps++;
    final before = _fingerprint();
    action();
    w.elapse(100);
    if (_fingerprint() == before) {
      report.deadTaps.add(DeadTap(what, game.phase));
      return false;
    }
    return true;
  }

  String _fingerprint() => [
    game.phase,
    game.playerIndex,
    game.questionIndex,
    game.calibStage,
    game.warmups.length,
    game.warmupsDone,
    game.paused,
    game.pendingVotes.entries.map((e) => '${e.key}${e.value}').join(),
    game.detector?.tQ1,
    game.detector?.tA1,
    game.soloHoldsQuestion,
    identical(game.currentResult, _lastResult),
  ].join('|');

  QuestionResult? _lastResult;

  // --- The body: one player's pulse, blinks and face -------------------------

  double _basePulse = 70;
  double _blinksPerMin = 17;
  int _stressFrom = 0;
  int _stressTo = 0;
  double _stressBpm = 0;

  void _newBody() {
    _basePulse = 60 + rng.nextDouble() * 25;
    _blinksPerMin = 12 + rng.nextDouble() * 12;
    _stressFrom = _stressTo = 0;
    w
      ..heart = _heart
      ..blinkEveryMs = _nextBlink
      ..expr = const {'neutral': 0.7, 'happy': 0.15, 'surprise': 0.05};
  }

  double _heart(int t) {
    final wobble =
        1.5 * math.sin(t / 7000) + 0.8 * math.sin(t / 2300 + _basePulse);
    var bump = 0.0;
    if (t >= _stressFrom && t < _stressTo) {
      final into = (t - _stressFrom) / 2500;
      final left = (_stressTo - t) / 4000;
      bump = _stressBpm * math.min(1, math.min(into, left));
    }
    return _basePulse + wobble + bump;
  }

  int _nextBlink() {
    final stressed = w.now >= _stressFrom && w.now < _stressTo;
    final rate = _blinksPerMin * (stressed ? 2.4 : 1);
    return (-math.log(1 - rng.nextDouble()) * 60000 / rate).round().clamp(
      150,
      30000,
    );
  }

  // --- The game -------------------------------------------------------------

  Persona _persona(Player p) => people.firstWhere((e) => e.$1 == p.name).$2;

  PartyReport play() {
    try {
      _play();
      report.finished = game.phase == GamePhase.leaderboard;
    } finally {
      report
        ..totalMs = w.now - World.base
        ..awards = game.awards
        ..turns = List.of(game.turns);
      _clock.cancel();
      w.dispose();
    }
    return report;
  }

  void _play() {
    for (final (name, _) in people) {
      game.addPlayer(name);
    }
    game.setQuestionsPerTurn(questions);
    w.presage.storedKey = 'pk_test_1234';
    _tap('Start the show', game.startShow);
    if (game.phase == GamePhase.howToPlay) {
      _wait(6000);
      _tap("Got it, let's play", game.dismissHowToPlay);
    }
    while (game.phase == GamePhase.consent) {
      _turn();
    }
  }

  void _turn() {
    final seat = game.currentPlayer;
    final me = _persona(seat);
    // The phone changes hands.
    _wait(_between(me.readConsent));
    if (_chance(me.skipsTurn)) {
      report.turnsSkipped++;
      _tap('Skip my turn', game.skipTurn);
      _wait(300);
      return;
    }
    _newBody();
    _faceOkSince = w.now;
    _tap('I agree, measure me', game.agreeToMeasure);
    final calibFrom = w.now;
    _calibrate(me);
    report.calibrations++;
    report.calibrationMs += w.now - calibFrom;
    final index = game.playerIndex;
    while (game.playerIndex == index &&
        (game.phase == GamePhase.ask || game.phase == GamePhase.answer)) {
      _question(seat, me);
    }
    _wait(300);
  }

  void _calibrate(Persona me) {
    _until(() => game.calibStage == CalibStage.chat, 'the sit-still');
    while (game.calibStage == CalibStage.chat) {
      final warmup = game.currentWarmup;
      if (warmup == null) {
        _wait(100);
        continue;
      }
      // Hear it out, then answer or pass.
      _until(
        () => warmup.askedAtMs > warmup.startedAtMs || !hostVoice,
        'the host to read a warm-up',
      );
      if (_chance(me.warmupSkip)) {
        _wait(_between(me.tap));
        _tap("Doesn't apply", game.skipWarmup);
        continue;
      }
      _wait(_between(me.answerPause));
      w.talk(true);
      _wait(_between(me.warmupAnswer));
      w.talk(false);
      _wait(_between(me.tap));
      _tap('Next', game.nextWarmup);
    }
    _until(() => game.calibStage == CalibStage.ready, 'the normal to lock in');
    _wait(_between(me.tap) + 600);
    _tap('Start the questions', game.startQuestions);
  }

  void _question(Player seat, Persona me) {
    final log = QuestionLog(seat.name, game.currentAsker?.name);
    final from = w.now;
    final index = game.questionIndex;
    report.questions.add(log);
    log.stressed = _chance(me.stressed);

    while (true) {
      _askAndAnswer(seat, me, log);
      if (game.phase != GamePhase.redo) break;
      // No clean read: most rooms ask again, twice at most.
      _wait(_between(me.verdictRead));
      if (log.asksNeeded >= 3 || _chance(0.2)) {
        log.skipped = true;
        _tap('Skip it', game.skipQuestion);
        _wait(200);
        log.totalMs = w.now - from;
        return;
      }
      log.asksNeeded++;
      _tap('Ask it again', game.askAgain);
    }

    if (game.phase == GamePhase.callIt) _callIt(seat, me, log);
    _until(() => game.phase == GamePhase.verdict, 'the countdown');
    final result = game.currentResult!;
    _lastResult = result;
    log
      ..verdict = result.verdict
      ..score = result.score;
    // The phone comes back to the hot seat for the verdict.
    final back = 500 + rng.nextInt(2500);
    _lookAway(back, 'NO_FACE_FOUND');
    _wait(_between(me.verdictRead));
    if (_chance(me.screenshot)) {
      w.leaveApp(3000);
      _wait(500);
    }
    log.totalMs = w.now - from;
    _tap(
      game.isLastQuestion ? 'Next contestant' : 'Next question',
      game.nextQuestion,
    );
    _wait(200);
    assert(game.questionIndex != index || game.phase != GamePhase.ask);
  }

  void _askAndAnswer(Player seat, Persona me, QuestionLog log) {
    final waitFrom = w.now;
    _until(() => !game.waitingForPulse, 'the pulse', maxMs: 60000);
    log.pulseWaitMs += w.now - waitFrom;
    final asker = game.currentAsker;
    if (asker != null) {
      report.asked[asker.name] = (report.asked[asker.name] ?? 0) + 1;
    }
    final them = asker == null ? me : _persona(asker);
    // The asker hears their name, thinks, and asks.
    _wait(_between(them.askThink));
    if (_chance(me.glance)) {
      _lookAway(1000 + rng.nextInt(1500), 'FACE_NOT_FORWARD', inMs: 300);
    }
    final speak = _between(them.askSpeak);
    for (var said = 0; said < speak; said += 400) {
      w.say('Have you ever ${'la ' * (1 + said ~/ 400)}');
      _wait(400);
    }
    final tQ1 = w.now;
    if (log.stressed) {
      // Until the answer is over; its end is set below.
      _stressFrom = tQ1;
      _stressTo = tQ1 + 600000;
      _stressBpm = 9 + rng.nextDouble() * 8;
    }

    final early = _chance(me.forgetsDoneAsking);
    if (!early) {
      _wait(_between(me.tap));
      _tap('Done asking', game.doneAsking);
    }
    _wait(
      _between(me.answerPause) + (log.stressed ? 1500 + rng.nextInt(2000) : 0),
    );
    if (log.stressed) {
      w.expr = const {'neutral': 0.3, 'surprise': 0.55, 'fear': 0.3};
    }
    w.talk(true);
    final answer = _between(me.answerSpeak);
    if (_chance(me.wiggle)) {
      _lookAway(1000 + rng.nextInt(2000), 'EXCESSIVE_MOTION', inMs: 400);
    }
    for (var said = 0; said < answer; said += 500) {
      w.say('Well ${'um ' * (1 + said ~/ 500)}');
      _wait(500);
    }
    w.talk(false);
    w.expr = const {'neutral': 0.7, 'happy': 0.15, 'surprise': 0.05};
    if (log.stressed) _stressTo = w.now + 6000;
    if (early) {
      // Realises the screen still says Done asking.
      _wait(_between(me.tap) + 800);
      _tap('Done asking', game.doneAsking);
    }
    _wait(
      _chance(me.forgetsFinalAnswer)
          ? 8000 + rng.nextInt(12000)
          : _between(me.finalTap),
    );
    _tap('Final answer', game.finalAnswer);
    final settleFrom = w.now;
    _until(() => game.phase != GamePhase.settle, 'the reading to lock in');
    log.settleMs += w.now - settleFrom;
  }

  void _callIt(Player seat, Persona me, QuestionLog log) {
    final from = w.now;
    // The hot seat holds the phone out to the room: no face until it's back.
    _lookAway(600000, 'NO_FACE_FOUND');
    final voters = game.voters;
    final picks = <(int, Player, Vote)>[];
    int? eagerAt;
    for (final v in voters) {
      final p = _persona(v);
      if (_chance(p.abstain)) continue;
      final at = _between(p.voteDelay);
      // A fair guess at the meter: right 60% of the time, like a friend who
      // half knows the tells.
      final guess = _chance(0.6) == log.stressed ? Vote.sus : Vote.legit;
      picks.add((at, v, guess));
      if (_chance(p.changesMind)) {
        picks.add((
          at + 400 + rng.nextInt(2500),
          v,
          guess == Vote.sus ? Vote.legit : Vote.sus,
        ));
      }
      if (p.eagerReveal) eagerAt = math.min(eagerAt ?? at + 900, at + 900);
    }
    picks.sort((a, b) => a.$1.compareTo(b.$1));
    final lastAt = picks.isEmpty ? 2500 : picks.last.$1;
    final revealAt = eagerAt ?? lastAt + _between(me.tap);
    var t = 0;
    for (final (at, voter, vote) in picks) {
      if (at >= revealAt) {
        log.votesLost++;
        continue;
      }
      _wait(at - t);
      t = at;
      report.taps++;
      game.castVote(voter.id, vote);
    }
    _wait(math.max(0, revealAt - t));
    log.votesCast = game.pendingVotes.length;
    _tap('Reveal', game.reveal);
    log.callItMs = w.now - from;
    _away.clear();
  }
}

/// One game on its own fake clock.
PartyReport playParty({
  required List<(String, Persona)> people,
  int questions = 5,
  int seed = 1,
  int pulseRecoveryMs = 3000,
  bool hostVoice = true,
}) {
  late PartyReport report;
  fakeAsync((async) {
    final sim = PartySim(
      async,
      people: people,
      questions: questions,
      seed: seed,
      pulseRecoveryMs: pulseRecoveryMs,
      hostVoice: hostVoice,
    );
    report = sim.play();
  });
  return report;
}

const partyNames = [
  'Sam',
  'Alex',
  'Priya',
  'Jordan',
  'Kai',
  'Mo',
  'Lee',
  'Ana',
];

/// [n] people with personas dealt from [seed].
List<(String, Persona)> party(int n, int seed) {
  final rng = math.Random(seed * 7919 + n);
  return [
    for (var i = 0; i < n; i++)
      (partyNames[i], Persona.all[rng.nextInt(Persona.all.length)]),
  ];
}
