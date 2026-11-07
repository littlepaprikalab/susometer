import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/audio/host_audio.dart';
import 'package:susometer/game/decks.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/scoring.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/presage/presage_models.dart';
import 'package:susometer/voice/speech_service.dart';
import 'package:susometer/voice/turn_detector.dart';

import 'world.dart';

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

  test('the expression tag follows the player in the seat, never the last '
      'one', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex'], questions: 3);
      w.expr = const {'surprise': 0.7, 'neutral': 0.2};
      w.calibrate();
      expect(w.game.live.expression.tag, 'surprise');
      for (var q = 0; q < 3; q++) {
        w.askAndAnswer();
        w.game.nextQuestion();
      }
      w.elapse(100);
      expect(w.game.phase, GamePhase.consent);
      expect(w.game.currentPlayer.name, 'Alex');
      expect(w.game.live.expression.tag, isNull, reason: 'camera is off');

      // Alex's face: the first frames must not show Sam's #surprise.
      w.expr = const {'happy': 0.7, 'neutral': 0.2};
      w.game.agreeToMeasure();
      for (var i = 0; i < 6; i++) {
        w.elapse(100);
        expect(
          w.game.live.expression.tag,
          isNot('surprise'),
          reason: '${(i + 1) * 100} ms into Alex calibrating',
        );
      }
      w.elapse(1000);
      expect(w.game.live.expression.tag, 'happy');
      w.dispose();
    });
  });

  group('the camera problem on screen (E3)', () {
    const motion = SignalIssue(
      'EXCESSIVE_MOTION',
      'Hold still',
      'Hold still',
      'Rest your elbows.',
    );
    const far = SignalIssue('FACE_TOO_FAR', 'Move closer', 'Move closer', '');

    /// Feeds [raw] every 100 ms for [ms] from [t]; returns the new time and
    /// every change of what's on screen.
    (int, List<String?>) feed(LiveState live, int t, int ms, SignalIssue? raw) {
      final seen = <String?>[];
      for (var i = 0; i < ms ~/ 100; i++) {
        t += 100;
        final before = live.issue?.stamp;
        live.updateIssue(raw, t);
        if (live.issue?.stamp != before) seen.add(live.issue?.stamp);
      }
      return (t, seen);
    }

    test('shows after 1.5 s; a shorter blip never shows', () {
      final live = LiveState();
      var (t, seen) = feed(live, 0, 1400, motion);
      expect(live.issue, isNull);
      (t, seen) = feed(live, t, 1000, null);
      expect(seen, isEmpty, reason: 'a 1.4 s blip');
      // 16 snapshots 100 ms apart: 1.5 s from the first to the last.
      (t, seen) = feed(live, t, 1600, motion);
      expect(seen, ['Hold still']);
    });

    test('a shaky hand keeps it up instead of blinking it', () {
      final live = LiveState();
      var t = 0;
      final seen = <String?>[];
      for (var cycle = 0; cycle < 8; cycle++) {
        final (t1, a) = feed(live, t, 2000, motion);
        final (t2, b) = feed(live, t1, 300, null);
        t = t2;
        seen
          ..addAll(a)
          ..addAll(b);
      }
      expect(seen, ['Hold still'], reason: 'shown once, kept');
      // Fixed for good: gone after 1 s clean, not before.
      var (t3, gone) = feed(live, t, 700, null);
      expect(gone, isEmpty);
      (t3, gone) = feed(live, t3, 500, null);
      expect(gone, [null]);
    });

    test('another problem takes over with no gap', () {
      final live = LiveState();
      var (t, seen) = feed(live, 0, 1600, motion);
      expect(seen, ['Hold still']);
      (t, seen) = feed(live, t, 1400, far);
      expect(seen, isEmpty, reason: 'the old stamp stays meanwhile');
      (t, seen) = feed(live, t, 200, far);
      expect(seen, ['Move closer'], reason: 'straight from one to the other');
    });

    test('a new session forgets it', () {
      final live = LiveState();
      feed(live, 0, 1600, motion);
      expect(live.issue, isNotNull);
      live.resetCamera();
      expect(live.issue, isNull);
      // And it starts counting afresh.
      final (_, seen) = feed(live, 10000, 1400, motion);
      expect(seen, isEmpty);
    });
  });

  test('a camera problem follows the player in the seat too: Alex never '
      'starts on Sam\'s "Hold still"', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex'], questions: 3);
      w.calibrate();
      for (var q = 0; q < 3; q++) {
        w.askAndAnswer();
        if (q == 2) {
          // Sam fidgets while the last verdict is up.
          w.code = 'EXCESSIVE_MOTION';
          w.elapse(2000);
          expect(w.game.visibleIssue?.stamp, 'Hold still');
        }
        w.game.nextQuestion();
      }
      w.elapse(100);
      expect(w.game.phase, GamePhase.consent);
      expect(w.game.visibleIssue, isNull, reason: 'camera is off');

      // Alex's camera is slow to send its first frame.
      w.code = 'OK';
      w.emitting = false;
      w.game.agreeToMeasure();
      w.elapse(2000);
      expect(w.game.phase, GamePhase.calibrate);
      expect(w.game.visibleIssue, isNull, reason: "Sam's problem, on Alex");
      w.emitting = true;
      w.elapse(1000);
      expect(w.game.visibleIssue, isNull);
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
      expect(
        w.game.phase,
        GamePhase.ask,
        reason: 'baseline kept; the question is asked again',
      );
      expect(w.game.questionIndex, 0);
      expect(w.game.currentTurn.baseline, isNotNull);
      w.dispose();
    });
  });

  test('a frozen camera is restarted, so "Reading paused" clears', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      w.calibrate();
      expect(w.game.phase, GamePhase.ask);
      int starts() => w.presage.calls.where((c) => c == 'start').length;
      final before = starts();
      // The camera stalls on a shaky frame: the SDK still says running and
      // the bridge keeps resending the last validation code.
      w.code = 'EXCESSIVE_MOTION';
      w.cameraFrozen = true;
      w.elapse(4500);
      expect(starts(), before, reason: 'a short gap is not a frozen camera');
      expect(w.game.visibleIssue?.code, 'EXCESSIVE_MOTION');
      w.elapse(1000);
      expect(starts(), before + 1, reason: 'restarted after 5 s');
      expect(w.game.phase, GamePhase.ask, reason: 'the question restarts');
      // The restart brings the camera back.
      w.cameraFrozen = false;
      w.code = 'OK';
      w.elapse(10000);
      expect(starts(), before + 1, reason: 'no more restarts');
      expect(w.game.visibleIssue, isNull);
      w.dispose();
    });
  });

  test('a camera that stays frozen ends in E5, not "Reading paused" '
      'forever', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      w.calibrate();
      w.code = 'EXCESSIVE_MOTION';
      w.cameraFrozen = true;
      w.until(() => w.game.phase == GamePhase.sdkOffline, maxMs: 30000);
      expect(w.game.sdkError!.code, 'NO_SIGNAL');
      expect(w.game.sdkError!.message, contains('camera froze'));
      w.cameraFrozen = false;
      w.code = 'OK';
      w.game.retrySdk();
      w.elapse(200);
      expect(w.game.phase, GamePhase.ask);
      w.dispose();
    });
  });

  test('no restart while something is over the app, or just after', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      w.calibrate();
      int starts() => w.presage.calls.where((c) => c == 'start').length;
      final before = starts();
      // Notification Center is pulled down: iOS may hold the camera.
      w.game.onAppInactive();
      w.cameraFrozen = true;
      w.elapse(20000);
      expect(starts(), before, reason: 'the app is inactive');
      w.game.onAppResumed();
      w.elapse(4500);
      expect(starts(), before, reason: 'the camera gets 5 s to come back');
      w.elapse(1000);
      expect(starts(), before + 1, reason: 'it did not come back');
      w.cameraFrozen = false;
      // Back in time: no restart.
      w.game.onAppInactive();
      w.cameraFrozen = true;
      w.elapse(8000);
      w.cameraFrozen = false;
      w.game.onAppResumed();
      w.elapse(10000);
      expect(starts(), before + 1);
      w.dispose();
    });
  });

  test('a camera that froze while paused is restarted on resume', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      w.calibrate();
      int starts() => w.presage.calls.where((c) => c == 'start').length;
      final before = starts();
      w.game.pause();
      w.cameraFrozen = true;
      w.elapse(10000);
      expect(starts(), before, reason: 'the watchdog rests while paused');
      w.game.resume();
      w.elapse(300);
      expect(starts(), before + 1);
      expect(w.game.paused, isFalse);
      expect(w.game.phase, GamePhase.ask);
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

  group('leaving the app', () {
    /// Party question 1, answered, up to Call it!.
    void answerToCallIt(World w) {
      expect(w.game.phase, GamePhase.ask);
      w.elapse(300);
      w.say('Have you ever re-gifted a present?');
      w.elapse(1500);
      w.game.doneAsking();
      w.elapse(1300);
      w.talk(true);
      w.elapse(300);
      w.say('No way.');
      w.elapse(2500);
      w.talk(false);
      w.elapse(800);
      w.game.finalAnswer();
      w.until(() => w.game.phase != GamePhase.settle, what: 'settle');
      expect(w.game.phase, GamePhase.callIt);
    }

    test('a short trip (a screenshot) carries on by itself', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        w.elapse(2000);
        final asked = w.game.questionStartMs;
        final starts = w.sdkCalls('start');
        final stops = w.sdkCalls('stop');
        w.leaveApp(
          3000,
          whileAway: () {
            expect(w.game.paused, isTrue);
            expect(w.game.pausedAway, isTrue);
            expect(w.running, isFalse, reason: 'camera stops while away');
          },
        );
        expect(w.game.paused, isFalse, reason: 'no Pause sheet to dismiss');
        expect(w.game.pausedAway, isFalse);
        expect(w.running, isTrue);
        expect(w.sdkCalls('start'), starts + 1);
        expect(
          w.sdkCalls('stop'),
          stops + 1,
          reason: 'hidden on the way back in stopped the camera again',
        );
        expect(w.game.phase, GamePhase.ask);
        expect(
          w.game.questionStartMs,
          greaterThan(asked),
          reason: 'the question starts over',
        );
        expect(w.game.paused, isFalse);
        expect(w.askAndAnswer().verdict, isNotNull, reason: 'still plays');
        w.dispose();
      });
    });

    test('a long trip waits on the Pause sheet, marked as away', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        w.leaveApp(GameController.autoResumeWithinMs + 5000);
        expect(w.game.paused, isTrue);
        expect(w.game.pausedAway, isTrue);
        expect(w.game.cameraStopped, isTrue);
        expect(w.running, isFalse);
        w.elapse(30000);
        expect(w.game.phase, GamePhase.ask, reason: 'no E5 while paused');
        w.game.resume();
        w.elapse(300);
        expect(w.game.paused, isFalse);
        expect(w.game.pausedAway, isFalse);
        expect(w.game.cameraStopped, isFalse);
        expect(w.running, isTrue);
        expect(w.askAndAnswer().verdict, isNotNull);
        w.dispose();
      });
    });

    test('a pause someone chose survives a short trip', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        w.game.pause();
        w.elapse(100);
        w.leaveApp(2000);
        expect(w.game.paused, isTrue, reason: 'only Resume ends this pause');
        expect(w.game.pausedAway, isFalse, reason: 'someone tapped Pause');
        expect(w.game.cameraStopped, isTrue);
        expect(w.running, isFalse);
        w.game.resume();
        w.elapse(300);
        expect(w.running, isTrue);
        expect(w.game.phase, GamePhase.ask);
        w.dispose();
      });
    });

    test('Skip question after a long trip brings the camera back', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        w.leaveApp(GameController.autoResumeWithinMs + 5000);
        expect(w.game.paused, isTrue);
        w.game.skipQuestion();
        w.elapse(300);
        expect(w.game.questionIndex, 1);
        expect(w.game.phase, GamePhase.ask);
        expect(w.game.paused, isFalse);
        expect(w.game.cameraStopped, isFalse);
        expect(w.running, isTrue, reason: 'the next question needs the camera');
        // It plays: without the ticker, settle would never end.
        expect(w.askAndAnswer().verdict, isNotNull);
        w.dispose();
      });
    });

    test('Call it! keeps the rest of its vote time', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        answerToCallIt(w);
        w.elapse(4000);
        final left = w.game.callItDeadlineMs - w.now;
        w.leaveApp(8000);
        expect(w.game.paused, isFalse);
        expect(w.running, isTrue);
        expect(
          w.game.phase,
          GamePhase.callIt,
          reason: 'the vote ran out while the app was away',
        );
        expect(w.game.callItDeadlineMs - w.now, closeTo(left - 300, 150));
        w.until(() => w.game.phase == GamePhase.countdown, maxMs: 7000);
        w.until(() => w.game.phase == GamePhase.verdict, maxMs: 5000);
        w.dispose();
      });
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
      expect(
        w.game.soloHoldsQuestion,
        isTrue,
        reason: 'the question stays up until the player starts answering',
      );
      w.elapse(5000);
      expect(w.game.soloHoldsQuestion, isTrue);
      w.talk(true);
      w.elapse(300);
      expect(w.game.soloHoldsQuestion, isFalse);
      w.elapse(1700);
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

  test('solo Ready to answer: shows the answer screen, timing unchanged', () {
    fakeAsync((async) {
      final w = World(async);
      w.game.setMode(GameMode.solo);
      w.startGame(['Sam']);
      w.calibrate();
      w.elapse(100);
      expect(w.game.phase, GamePhase.answer);
      final tQ1 = w.game.detector!.tQ1;
      w.elapse(3000);
      expect(w.game.soloHoldsQuestion, isTrue);
      w.game.readyToAnswer();
      expect(w.game.soloHoldsQuestion, isFalse);
      expect(w.game.phase, GamePhase.answer);
      expect(
        w.game.detector!.tQ1,
        tQ1,
        reason: 'hesitation still counts from when the host finished',
      );
      // Different question only works while the question is on screen.
      final q = w.game.questionText;
      w.game.differentQuestion();
      expect(w.game.questionText, q);
      w.dispose();
    });
  });

  test('solo Ready to answer while the host reads ends the question', () {
    fakeAsync((async) {
      final w = World(async);
      w.game.setMode(GameMode.solo);
      w.settings.hostVoice = false;
      w.startGame(['Sam']);
      w.calibrate();
      w.elapse(100);
      expect(w.game.phase, GamePhase.ask);
      w.game.readyToAnswer();
      expect(w.game.phase, GamePhase.answer);
      expect(w.game.soloHoldsQuestion, isFalse);
      expect(w.game.detector!.questionEndReason, QuestionEndReason.button);
      w.dispose();
    });
  });

  test('solo: the answer card shows the moment the player starts', () {
    fakeAsync((async) {
      final w = World(async);
      w.game.setMode(GameMode.solo);
      w.startGame(['Sam']);
      w.calibrate();
      w.elapse(100);
      expect(w.game.shownPhase, GamePhase.ask);
      var redraws = 0;
      w.game.addListener(() => redraws++);
      // Recognized words, with no tick in between.
      w.say('Maybe');
      async.flushMicrotasks();
      expect(w.game.soloHoldsQuestion, isFalse);
      expect(w.game.shownPhase, GamePhase.answer);
      expect(redraws, greaterThan(0), reason: 'redraws without waiting');
      w.dispose();
    });
  });

  test('solo: a double tap on Different question skips only one', () {
    fakeAsync((async) {
      final w = World(async);
      w.game.setMode(GameMode.solo);
      w.startGame(['Sam']);
      w.calibrate();
      w.elapse(100);
      w.game.differentQuestion();
      final q = w.game.questionText;
      w.elapse(120);
      w.game.differentQuestion();
      expect(w.game.questionText, q, reason: 'second tap ignored');
      w.elapse(700);
      w.game.differentQuestion();
      expect(w.game.questionText, isNot(q));
      w.dispose();
    });
  });

  test('solo Different question still works after the host has read it', () {
    fakeAsync((async) {
      final w = World(async);
      w.game.setMode(GameMode.solo);
      w.startGame(['Sam']);
      w.calibrate();
      w.elapse(100);
      expect(w.game.soloHoldsQuestion, isTrue);
      final q = w.game.questionText;
      w.game.differentQuestion();
      expect(w.game.questionText, isNot(q));
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

  test('a mic that fails to restart: tap-to-advance, voice back next turn', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex'], questions: 1);
      w.calibrate();
      w.speech.controller.add(
        const SpeechError('AUDIO_RESTART_FAILED', 'no input', 0),
      );
      w.elapse(100);
      expect(w.game.micEnabled, isFalse);
      expect(w.game.notice, contains('tap-to-advance for this turn'));
      expect(w.speech.calls.last, 'stop');
      w.askAndAnswer();
      w.game.endTurn();
      w.elapse(100);
      expect(w.game.phase, GamePhase.consent);
      final startsBefore = w.speech.calls.where((c) => c == 'start').length;
      w.calibrate();
      expect(w.game.micEnabled, isTrue, reason: "Alex's turn has voice");
      expect(w.game.notice, isNull);
      expect(
        w.speech.calls.where((c) => c == 'start').length,
        startsBefore + 1,
      );
      w.dispose();
    });
  });

  test('no on-device speech stays tap-to-advance for the whole game', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex'], questions: 1);
      w.calibrate();
      w.speech.controller.add(
        const SpeechError('ON_DEVICE_UNAVAILABLE', 'no', 0),
      );
      w.elapse(100);
      w.askAndAnswer();
      w.game.endTurn();
      w.elapse(100);
      w.calibrate();
      expect(w.game.micEnabled, isFalse);
      w.dispose();
    });
  });

  test('a speech error outside a turn leaves the mic alone', () {
    fakeAsync((async) {
      // Settings' signal check listens from the lobby.
      final w = World(async);
      w.speech.controller.add(
        const SpeechError('AUDIO_RESTART_FAILED', 'no input', 0),
      );
      w.speech.controller.add(
        const SpeechError('RECOGNIZER_FAILING', 'nope', 0),
      );
      w.elapse(100);
      expect(w.game.micEnabled, isTrue);
      expect(w.game.notice, isNull);
      expect(w.speech.calls, isNot(contains('stop')));
      w.dispose();
    });
  });

  test('a new question stops the host before it speaks', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex'], questions: 2);
      w.calibrate();
      w.askAndAnswer();
      w.game.nextQuestion();
      w.elapse(100);
      expect(w.game.phase, GamePhase.ask);
      final ask = w.host.calls.lastIndexOf('say:Ask your question!');
      expect(ask, greaterThan(0));
      expect(
        w.host.calls[ask - 1],
        'stop',
        reason: 'a verdict line still going is cut, not queued ahead',
      );
      w.dispose();
    });
  });

  test('solo: a camera restart re-asks, and the old reading ends nothing', () {
    fakeAsync((async) {
      final w = World(async);
      w.game.setMode(GameMode.solo);
      w.startGame(['Sam']);
      w.calibrate();
      w.elapse(100);
      // The host reads slowly from here on.
      w.host.hold = true;
      w.elapse(700);
      w.game.differentQuestion();
      final first = w.host.said.length - 1;
      expect(w.game.phase, GamePhase.ask);
      // The camera stops sending: the question restarts with the same text.
      w.emitting = false;
      w.elapse(6500);
      w.emitting = true;
      final second = w.host.said.length - 1;
      expect(second, greaterThan(first), reason: 'the question was re-asked');
      expect(w.host.said[second], w.host.said[first]);
      // The first reading ends (stopped, or iOS finally reports it).
      w.host.finishLine(first);
      w.elapse(100);
      expect(
        w.game.phase,
        GamePhase.ask,
        reason: 'the re-asked question is still being read',
      );
      expect(w.game.detector!.questionEnded, isFalse);
      w.host.finishLine(second);
      w.elapse(100);
      expect(w.game.phase, GamePhase.answer);
      expect(w.game.detector!.questionEndReason, QuestionEndReason.hostDone);
      w.dispose();
    });
  });

  test('"Next question" during the verdict sound: no verdict line after', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex'], questions: 2);
      w.calibrate();
      w.host.hold = true;
      w.askAndAnswer();
      expect(w.game.phase, GamePhase.verdict);
      w.game.nextQuestion();
      w.elapse(100);
      expect(w.game.phase, GamePhase.ask);
      w.host.finishSounds();
      w.elapse(100);
      for (final line in ['Legit!', 'Hmm…', 'Sus!']) {
        expect(w.host.said, isNot(contains(line)));
      }
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

  test('double taps never skip two players or two questions', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex', 'Priya'], questions: 3);
      w.game.skipTurn();
      w.game.skipTurn();
      w.elapse(50);
      expect(w.game.currentPlayer.name, 'Alex', reason: 'second tap ignored');
      w.elapse(700);
      w.calibrate();
      w.askAndAnswer();
      w.game.nextQuestion();
      w.game.nextQuestion();
      w.game.endTurn();
      w.elapse(100);
      expect(w.game.phase, GamePhase.ask);
      expect(w.game.questionIndex, 1);
      expect(w.game.currentPlayer.name, 'Alex');
      w.dispose();
    });
  });

  test('an SDK stuck in starting is restarted', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      w.calibrate();
      final starts = w.presage.calls.where((c) => c == 'start').length;
      w.status = 'starting';
      w.elapse(16500);
      expect(
        w.presage.calls.where((c) => c == 'start').length,
        greaterThan(starts),
      );
      w.status = 'running';
      w.dispose();
    });
  });

  test('E5 mid-turn: Try again carries on from the next unplayed question', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex'], questions: 3);
      w.calibrate();
      w.askAndAnswer();
      w.game.nextQuestion();
      w.elapse(100);
      expect(w.game.questionIndex, 1);
      w.emitting = false;
      w.until(() => w.game.phase == GamePhase.sdkOffline, maxMs: 40000);
      w.emitting = true;
      w.elapse(700);
      w.game.retrySdk();
      w.elapse(300);
      expect(w.game.phase, GamePhase.ask);
      expect(w.game.questionIndex, 1, reason: 'question 1 is already played');
      expect(w.game.currentTurn.results.length, 1);
      w.dispose();
    });
  });

  test('lobby settings are locked once a game starts', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex'], questions: 5);
      final g = w.game;
      final before = (g.mode, g.questionsPerTurn, g.deck, g.players.length);
      g.setMode(GameMode.solo);
      g.setQuestionsPerTurn(3);
      g.setDeck(g.deck == DeckKind.mild ? DeckKind.spicy : DeckKind.mild);
      expect(g.addPlayer('Late'), isFalse);
      g.removePlayer(g.players.first.id);
      expect((g.mode, g.questionsPerTurn, g.deck, g.players.length), before);
      w.dispose();
    });
  });
}
