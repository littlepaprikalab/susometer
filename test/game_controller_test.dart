import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/audio/host_audio.dart';
import 'package:susometer/game/decks.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/presage/presage_models.dart';
import 'package:susometer/settings/app_settings.dart';
import 'package:susometer/voice/speech_service.dart';
import 'package:susometer/voice/turn_detector.dart';

import 'fakes.dart';

/// Records which phase each haptic fired in.
class PhaseHaptics implements HapticsApi {
  PhaseHaptics(this.phase);

  final GamePhase Function() phase;
  final List<(HapticCue, GamePhase)> cues = [];

  @override
  Future<void> cue(HapticCue cue) async => cues.add((cue, phase()));
}

/// A scripted SmartSpectra + speech world running on fake time.
class World {
  World(
    this.async, {
    TurnConfig turnConfig = const TurnConfig(
      autoQuestionEnd: false,
      autoAnswerEnd: false,
    ),
  }) {
    presage = RunningPresage(this);
    game = GameController(
      presage: presage,
      speech: speech,
      device: device,
      settings: settings,
      apiKey: ApiKeyController(presage),
      host: host,
      haptics: haptics = PhaseHaptics(() => game.phase),
      decks: DeckLibrary.fallback,
      turnConfig: turnConfig,
      now: () => now,
    );
    _emitter = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _emit(),
    );
  }

  final FakeAsync async;
  late final RunningPresage presage;
  final speech = FakeSpeech();
  final device = FakeDevice();
  final host = FakeHostAudio();
  final settings = AppSettings();
  late final PhaseHaptics haptics;
  late final GameController game;
  late final Timer _emitter;

  static const base = 1700000000000;
  int get now => base + async.elapsed.inMilliseconds;

  // Script knobs.
  bool running = false;
  bool emitting = true;
  double pulse = 70;
  String code = 'OK';
  bool autoAnswerWarmups = true;
  final List<Map<String, Object?>> _pendingEvents = [];
  int? _pulseAt;
  int _nextBlink = 0;
  Warmup? _answered;

  void talk(bool on) =>
      _pendingEvents.add({'e': on ? 'talkStart' : 'talkEnd', 't': now});

  void say(String text, {bool isFinal = false}) => speech.controller.add(
    SpeechText(text: text, segment: speech.segment, isFinal: isFinal, tMs: now),
  );

  void _emit() {
    if (!running || !emitting) return;
    final t = now;
    if (_pulseAt == null || t - _pulseAt! >= 1000) _pulseAt = t;
    if (t >= _nextBlink) {
      _pendingEvents.add({'e': 'blinkEvent', 't': t});
      _nextBlink = t + 4000;
    }
    // Answer each warm-up: start talking 0.8 s after it's asked, stop 2 s later.
    final w = game.currentWarmup;
    if (autoAnswerWarmups &&
        w != null &&
        !identical(w, _answered) &&
        t - w.askedAtMs >= 800) {
      _answered = w;
      talk(true);
      Timer(const Duration(seconds: 2), () => talk(false));
    }
    presage.controller.add(
      PresageSample.fromMap({
        't': t,
        'status': 'running',
        'pulse': pulse,
        'pulseConf': 0.9,
        'pulseAt': _pulseAt,
        'expr': const {'neutral': 0.8, 'surprise': 0.05},
        'validation': {'code': code, 'hint': code == 'OK' ? '' : 'hint'},
        'events': List.of(_pendingEvents),
      }),
    );
    _pendingEvents.clear();
  }

  /// Advances fake time in 100 ms steps until [cond] holds.
  void until(bool Function() cond, {int maxMs = 120000, String? what}) {
    var waited = 0;
    while (!cond()) {
      async.elapse(const Duration(milliseconds: 100));
      waited += 100;
      if (waited > maxMs) {
        fail(
          'Timed out waiting for ${what ?? 'condition'} (phase ${game.phase})',
        );
      }
    }
  }

  void elapse(int ms) => async.elapse(Duration(milliseconds: ms));

  void dispose() {
    _emitter.cancel();
    game.dispose();
  }

  /// Lobby → consent of the first player.
  void startGame(List<String> names, {int questions = 3}) {
    for (final n in names) {
      game.addPlayer(n);
    }
    game.setQuestionsPerTurn(questions);
    presage.storedKey = 'pk_test_1234';
    game.startShow();
    elapse(100);
    if (game.phase == GamePhase.howToPlay) game.dismissHowToPlay();
    expect(game.phase, GamePhase.consent);
  }

  /// Consent → calibrated and asking question 1.
  void calibrate() {
    game.agreeToMeasure();
    elapse(100);
    expect(game.phase, GamePhase.calibrate);
    until(
      () => game.phase == GamePhase.ask || game.phase == GamePhase.answer,
      what: 'calibration to finish',
    );
  }

  /// Party question with tap-to-advance; returns the result.
  QuestionResult askAndAnswer({
    String question = 'Have you ever re-gifted a present?',
    String answer = 'No way. Okay, maybe once.',
    double answerPulse = 70,
    List<String> votesSus = const [],
  }) {
    expect(game.phase, GamePhase.ask);
    elapse(300);
    say(question);
    elapse(1500);
    game.doneAsking();
    expect(game.phase, GamePhase.answer);
    elapse(200);
    pulse = answerPulse;
    elapse(1100);
    talk(true);
    elapse(300);
    say(answer);
    elapse(2500);
    talk(false);
    elapse(800);
    game.finalAnswer();
    expect(game.phase, GamePhase.settle);
    until(() => game.phase != GamePhase.settle, what: 'settle');
    pulse = 70;
    if (game.phase == GamePhase.callIt) {
      for (final id in votesSus) {
        game.cycleVote(id);
        game.cycleVote(id);
      }
      game.reveal();
    }
    expect(game.phase, GamePhase.countdown);
    until(() => game.phase == GamePhase.verdict, what: 'countdown');
    return game.currentResult!;
  }
}

class RunningPresage extends FakePresage {
  RunningPresage(this.world);

  final World world;

  @override
  Future<void> start() async {
    await super.start();
    world.running = true;
  }

  @override
  Future<void> stop() async {
    await super.stop();
    world.running = false;
  }

  @override
  Future<void> reset() async {
    await super.reset();
    world.running = false;
  }
}

void main() {
  test('a full party game: 2 players, 3 questions, votes, awards', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      expect(w.device.calls, contains('keepAwake(true)'));
      expect(w.game.hasSeenHowToPlay, isTrue);

      w.calibrate();
      expect(
        w.presage.calls,
        containsAllInOrder(['reset', 'configure(telemetry: false)', 'start']),
      );
      expect(w.speech.calls, contains('start'));
      final base = w.game.currentTurn.baseline!;
      expect(base.pulse, closeTo(70, 0.01));
      expect(base.latencyS, closeTo(0.8, 0.25));
      expect(w.game.warmupsDone, greaterThanOrEqualTo(2));

      final alexId = w.game.players[1].id;
      final r1 = w.askAndAnswer(votesSus: [alexId]);
      expect(r1.question, 'Have you ever re-gifted a present?');
      expect(r1.answer, 'No way. Okay, maybe once.');
      expect(r1.verdict, isNotNull);
      expect(r1.votes[alexId], Vote.sus);
      expect(r1.timing!.tA0, isNotNull);
      expect(r1.features!.hesitationS, closeTo(1.3, 0.25));

      w.game.nextQuestion();
      final r2 = w.askAndAnswer(
        question: 'Do you floss every day?',
        answerPulse: 95,
        votesSus: [alexId],
      );
      expect(
        r2.verdict,
        isNot(Verdict.legit),
        reason: 'pulse +25 for most of the window',
      );
      expect(r2.score!, greaterThan(r1.score!));

      w.game.nextQuestion();
      w.askAndAnswer(question: 'Have you ever sung in the shower?');
      expect(w.game.isLastQuestion, isTrue);
      w.game.nextQuestion();
      w.elapse(100);
      expect(w.game.phase, GamePhase.consent);
      expect(w.game.currentPlayer.name, 'Alex');
      expect(w.presage.calls.last, 'stop');
      expect(w.speech.calls, contains('stop'));

      // Alex skips; the game ends.
      w.game.skipTurn();
      w.elapse(100);
      expect(w.game.phase, GamePhase.leaderboard);
      final awards = w.game.awards!;
      expect(awards.ranked.single.player.name, 'Sam');
      expect(awards.unscored.single.name, 'Alex');
      expect(awards.biggestSpike!.result.question, 'Do you floss every day?');
      w.elapse(100);
      expect(w.host.said.last, 'And the winners are…');
      expect(w.host.played.last, Sfx.applause);
      expect(w.device.calls.last, 'keepAwake(false)');

      // No haptics ever fired while measuring.
      const measuring = {
        GamePhase.calibrate,
        GamePhase.ask,
        GamePhase.answer,
        GamePhase.settle,
      };
      expect(w.haptics.cues.where((c) => measuring.contains(c.$2)), isEmpty);
      expect(
        w.haptics.cues.map((c) => c.$1),
        contains(HapticCue.countdownTick),
      );

      w.game.openReplay();
      expect(w.game.phase, GamePhase.replay);
      w.game.playAgain();
      w.elapse(100);
      expect(w.game.phase, GamePhase.lobby);
      expect(
        w.game.players.length,
        2,
        reason: 'Play again keeps the contestants',
      );
      expect(w.game.turns, isEmpty);
      w.dispose();
    });
  });

  test('host lines and the half-duplex speech segments', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex'], questions: 1);
      w.calibrate();
      expect(w.host.said.first, 'Sam, sit still and look at the camera.');
      expect(w.host.said, contains(w.game.warmups.first.question));
      w.askAndAnswer();
      expect(
        w.speech.calls.where((c) => c == 'newSegment').length,
        2,
        reason: 'one when the question starts, one when the answer starts',
      );
      expect(w.host.said, contains('Ask your question!'));
      expect(w.host.said, contains('Call it! Legit or sus?'));
      expect(w.host.said.last, isIn(['Legit!', 'Hmm…', 'Sus!']));
      expect(w.host.played, contains(Sfx.drumroll));
      w.dispose();
    });
  });

  test('host voice off: lines still show as captions but are not spoken', () {
    fakeAsync((async) {
      final w = World(async);
      w.settings.hostVoice = false;
      w.startGame(['Sam', 'Alex'], questions: 1);
      w.calibrate();
      expect(w.host.said, isEmpty);
      expect(w.game.hostLine, isNotEmpty);
      w.dispose();
    });
  });

  test('no key: Start the show asks for Settings instead of starting', () {
    fakeAsync((async) {
      final w = World(async);
      w.game.addPlayer('Sam');
      w.game.addPlayer('Alex');
      StartBlock? block;
      w.game.startShow().then((b) => block = b);
      w.elapse(100);
      expect(block, StartBlock.needKey);
      expect(w.game.phase, GamePhase.lobby);
      w.dispose();
    });
  });

  test('party needs 2 players, solo needs 1, max 8', () {
    fakeAsync((async) {
      final w = World(async);
      w.game.addPlayer('Sam');
      StartBlock? block;
      w.game.startShow().then((b) => block = b);
      w.elapse(100);
      expect(block, StartBlock.needPlayers);
      w.game.setMode(GameMode.solo);
      expect(w.game.canStart, isTrue);
      for (var i = 0; i < 10; i++) {
        w.game.addPlayer('P$i');
      }
      expect(w.game.players.length, 8);
      expect(w.game.addPlayer('   '), isFalse);
      w.dispose();
    });
  });

  test(
    'camera denied: E2 with no way to play; mic denied: Play without voice',
    () {
      fakeAsync((async) {
        final w = World(async);
        w.device.camera = 'denied';
        w.game.addPlayer('Sam');
        w.game.addPlayer('Alex');
        w.presage.storedKey = 'k';
        w.game.startShow();
        w.elapse(100);
        expect(w.game.phase, GamePhase.permissions);
        expect(w.game.permissions!.cameraOk, isFalse);
        w.game.playWithoutVoice();
        expect(
          w.game.phase,
          GamePhase.permissions,
          reason: 'camera is required',
        );
        w.game.openAppSettings();
        expect(w.device.calls, contains('openAppSettings'));

        // The user turns the camera on in iOS Settings and comes back.
        w.device.camera = 'granted';
        w.game.onAppResumed();
        w.elapse(100);
        expect(w.game.phase, GamePhase.howToPlay);
        w.dispose();
      });
    },
  );

  test('play without voice: no recognition, tap-to-advance still works', () {
    fakeAsync((async) {
      final w = World(async);
      w.speech.permissions = const SpeechPermissions(
        mic: 'denied',
        speech: 'denied',
        onDevice: true,
      );
      w.game.addPlayer('Sam');
      w.game.addPlayer('Alex');
      w.presage.storedKey = 'k';
      w.game.startShow();
      w.elapse(100);
      expect(w.game.phase, GamePhase.permissions);
      w.game.playWithoutVoice();
      expect(w.game.micEnabled, isFalse);
      w.game.dismissHowToPlay();
      w.calibrate();
      expect(w.speech.calls, isNot(contains('start')));
      final r = w.askAndAnswer();
      expect(r.question, 'Question 1', reason: 'no transcript without a mic');
      expect(r.answer, isEmpty);
      expect(w.speech.calls, isNot(contains('newSegment')));
      w.dispose();
    });
  });

  test('SDK sign-in fails: E5, then Try again recovers', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      w.presage.startError = const PresageException(
        'authenticationFailed',
        'Invalid API key',
      );
      w.game.agreeToMeasure();
      w.elapse(200);
      expect(w.game.phase, GamePhase.sdkOffline);
      expect(w.game.sdkError!.code, 'authenticationFailed');
      w.presage.startError = null;
      w.game.retrySdk();
      w.elapse(200);
      expect(w.game.phase, GamePhase.calibrate);
      w.until(() => w.game.phase == GamePhase.ask);
      w.dispose();
    });
  });

  test('watchdog restarts a silent SDK, then gives up with E5', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      w.calibrate();
      final startsBefore = w.presage.calls.where((c) => c == 'start').length;
      w.emitting = false;
      w.elapse(6500);
      expect(
        w.presage.calls.where((c) => c == 'start').length,
        startsBefore + 1,
      );
      expect(
        w.game.phase,
        GamePhase.ask,
        reason: 'question restarts after recovery',
      );
      w.until(() => w.game.phase == GamePhase.sdkOffline, maxMs: 30000);
      expect(w.game.sdkError!.code, 'NO_SIGNAL');
      w.emitting = true;
      w.game.retrySdk();
      w.elapse(200);
      expect(w.game.phase, GamePhase.calibrate);
      w.dispose();
    });
  });

  test('pause freezes the question; resume starts it over', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      w.calibrate();
      w.say('Have you ever lied?');
      w.elapse(500);
      w.game.doneAsking();
      expect(w.game.phase, GamePhase.answer);
      w.game.pause();
      w.elapse(20000);
      expect(
        w.game.phase,
        GamePhase.answer,
        reason: 'nothing advances while paused',
      );
      w.game.resume();
      w.elapse(100);
      expect(w.game.phase, GamePhase.ask);
      expect(w.game.paused, isFalse);
      w.dispose();
    });
  });

  test('app backgrounded mid-question: stops cleanly, restarts on resume', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      w.calibrate();
      final starts = w.presage.calls.where((c) => c == 'start').length;
      w.game.onAppBackgrounded();
      w.elapse(100);
      expect(w.game.paused, isTrue);
      expect(w.presage.calls.last, 'stop');
      expect(w.running, isFalse);
      w.elapse(30000);
      expect(w.game.phase, GamePhase.ask, reason: 'no E5 while backgrounded');
      w.game.resume();
      w.elapse(300);
      expect(w.presage.calls.where((c) => c == 'start').length, starts + 1);
      expect(w.game.phase, GamePhase.ask);
      w.dispose();
    });
  });

  test('no clean read: E4, Ask it again, then Skip it', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex'], questions: 2);
      w.calibrate();
      w.say('Have you ever read a diary?');
      w.elapse(500);
      w.game.doneAsking();
      w.code = 'NO_FACE_FOUND';
      w.elapse(3000);
      w.game.finalAnswer();
      w.until(() => w.game.phase != GamePhase.settle);
      expect(w.game.phase, GamePhase.redo);
      expect(
        w.game.currentResult!.noCleanReadReasons.first,
        contains("lost Sam's face"),
      );
      expect(
        w.game.currentTurn.results,
        isEmpty,
        reason: 'shaky reads are never scored',
      );
      w.game.askAgain();
      expect(w.game.phase, GamePhase.ask);
      expect(w.game.questionIndex, 0);
      w.game.doneAsking();
      w.elapse(500);
      w.game.finalAnswer();
      w.until(() => w.game.phase != GamePhase.settle);
      expect(w.game.phase, GamePhase.redo);
      w.code = 'OK';
      w.game.skipQuestion();
      w.elapse(100);
      expect(w.game.phase, GamePhase.ask);
      expect(w.game.questionIndex, 1);
      expect(w.game.currentTurn.results.single.skipped, isTrue);
      w.dispose();
    });
  });

  test('End the show early crowns winners from what was played', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex', 'Priya']);
      w.calibrate();
      w.askAndAnswer();
      w.game.nextQuestion();
      final (played, notYet) = w.game.playedSummary();
      expect(played.single.$1.name, 'Sam');
      expect(notYet.map((p) => p.name), ['Alex', 'Priya']);
      w.game.endShowEarly();
      w.elapse(100);
      expect(w.game.phase, GamePhase.leaderboard);
      expect(w.running, isFalse);
      w.game.wipeAll();
      w.elapse(100);
      expect(w.game.phase, GamePhase.lobby);
      expect(w.game.players, isEmpty);
      w.dispose();
    });
  });

  test('solo mode: the host reads deck questions; Different question', () {
    fakeAsync((async) {
      final w = World(async);
      w.game.setMode(GameMode.solo);
      w.startGame(['Sam']);
      w.calibrate();
      // Host voice is on and the fake host finishes instantly.
      w.elapse(100);
      expect(w.game.phase, GamePhase.answer);
      final q = w.game.questionText;
      expect(DeckLibrary.fallback.mild, contains(q));
      expect(w.host.said.any((l) => l.contains(q)), isTrue);
      w.talk(true);
      w.elapse(2000);
      w.talk(false);
      w.elapse(600);
      w.game.finalAnswer();
      w.until(
        () => w.game.phase == GamePhase.countdown,
        what: 'no Call it! in solo',
      );
      w.until(() => w.game.phase == GamePhase.verdict);
      expect(w.game.currentResult!.question, q);
      expect(w.game.currentResult!.votes, isEmpty);
      w.dispose();
    });
  });

  test('a hot phone shows the breather note before the next turn', () {
    fakeAsync((async) {
      final w = World(async);
      w.device.thermal = 'serious';
      w.startGame(['Sam', 'Alex'], questions: 1);
      w.calibrate();
      w.askAndAnswer();
      w.game.nextQuestion();
      w.elapse(100);
      expect(w.game.phase, GamePhase.consent);
      expect(w.game.thermalWarning, isTrue);
      w.dispose();
    });
  });

  test('voice recognition failing falls back to tap-to-advance', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      w.calibrate();
      w.speech.controller.add(
        const SpeechError('RECOGNIZER_FAILING', 'nope', 0),
      );
      w.elapse(100);
      expect(w.game.micEnabled, isFalse);
      expect(w.game.notice, contains('tap-to-advance'));
      w.dispose();
    });
  });

  test(
    'automatic turns: silence ends the question, host prompts, 4 s silence ends the answer',
    () {
      fakeAsync((async) {
        final w = World(async, turnConfig: const TurnConfig());
        w.startGame(['Sam', 'Alex'], questions: 1);
        w.calibrate();
        expect(w.game.phase, GamePhase.ask);
        w.elapse(500);
        for (final part in [
          'Have you',
          'Have you ever',
          'Have you ever lied?',
        ]) {
          w.say(part);
          w.elapse(400);
        }
        expect(w.game.phase, GamePhase.ask);
        w.until(
          () => w.game.phase == GamePhase.answer,
          maxMs: 3000,
          what: 'silence to end the question',
        );
        expect(
          w.game.detector!.questionEndReason,
          QuestionEndReason.askerSilence,
        );
        w.elapse(100);
        expect(w.host.said, contains('Sam, your answer?'));
        w.elapse(900);
        w.talk(true);
        w.elapse(300);
        w.say('Nope.');
        w.elapse(1700);
        w.talk(false);
        w.until(
          () => w.game.phase == GamePhase.settle,
          maxMs: 6000,
          what: '4 s of silence',
        );
        expect(w.game.detector!.answerEndReason, AnswerEndReason.silence);
        w.until(() => w.game.phase == GamePhase.callIt);
        w.game.reveal();
        w.until(() => w.game.phase == GamePhase.verdict);
        final r = w.game.currentResult!;
        expect(r.question, 'Have you ever lied?');
        expect(r.answer, 'Nope.');
        expect(
          r.features!.hesitationS,
          closeTo(0.9, 0.3),
          reason: 'measured from the prompt end',
        );
        w.dispose();
      });
    },
  );

  test(
    'automatic turns: answering straight away ends the question with no prompt',
    () {
      fakeAsync((async) {
        final w = World(async, turnConfig: const TurnConfig());
        w.startGame(['Sam', 'Alex'], questions: 1);
        w.calibrate();
        w.elapse(500);
        w.say('Do you floss?');
        w.elapse(300);
        w.talk(true);
        w.elapse(400);
        expect(w.game.phase, GamePhase.answer);
        expect(
          w.game.detector!.questionEndReason,
          QuestionEndReason.playerTalk,
        );
        expect(w.host.said, isNot(contains('Sam, your answer?')));
        expect(w.game.live.hesitationS, 0);
        w.dispose();
      });
    },
  );
}
