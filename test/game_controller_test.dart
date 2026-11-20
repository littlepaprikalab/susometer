import 'dart:async';

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
      expect(w.host.said, contains('Alex, ask your question!'));
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

  test('play without voice: no recognition, the taps still work', () {
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

    test(
      'leaving while the camera starts: nothing starts in the background',
      () {
        fakeAsync((async) {
          final w = World(async);
          w.startGame(['Sam', 'Alex']);
          w.startTakesMs = 800;
          w.game.agreeToMeasure();
          w.elapse(300);
          // A screenshot right after "I agree": the start finishes while away.
          w.goAway();
          final said = w.host.said.length;
          w.elapse(2000);
          expect(
            w.running,
            isFalse,
            reason: 'camera started in the background',
          );
          expect(
            w.game.micEnabled,
            isTrue,
            reason: 'voice was dropped: the mic was started in the background',
          );
          expect(w.host.said.length, said, reason: 'the host spoke while away');
          w.startTakesMs = 0;
          w.comeBack();
          w.elapse(300);
          expect(w.game.paused, isFalse);
          expect(w.running, isTrue);
          w.until(() => w.game.phase == GamePhase.ask, what: 'calibration');
          expect(w.game.micEnabled, isTrue);
          expect(w.askAndAnswer().verdict, isNotNull);
          w.dispose();
        });
      },
    );

    test('a camera start that fails because the app left is not E5', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.startTakesMs = 800;
        w.startFailsWhileAway = true;
        w.game.agreeToMeasure();
        w.elapse(300);
        w.goAway();
        w.elapse(2000);
        expect(w.game.phase, GamePhase.calibrate, reason: 'E5 for a trip');
        expect(w.game.paused, isTrue);
        w.startTakesMs = 0;
        w.comeBack();
        w.until(() => w.game.phase == GamePhase.ask, what: 'calibration');
        expect(w.running, isTrue);
        w.dispose();
      });
    });

    test('leaving while the mic starts keeps voice on', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        w.leaveApp(GameController.autoResumeWithinMs + 5000);
        w.speech.startTakesMs = 500;
        w.game.resume();
        w.elapse(200);
        // iOS runs the mic start after the app is already in the background.
        w.goAway();
        final said = w.host.said.length;
        final asked = w.game.questionStartMs;
        w.elapse(2000);
        expect(w.game.micEnabled, isTrue, reason: 'voice dropped for a trip');
        expect(
          w.game.questionStartMs,
          asked,
          reason: 'a question began while away',
        );
        expect(w.game.paused, isTrue);
        expect(w.host.said.length, said, reason: 'the host spoke while away');
        w.speech.startTakesMs = 0;
        w.comeBack();
        w.elapse(300);
        expect(w.running, isTrue);
        expect(w.game.phase, GamePhase.ask);
        expect(w.askAndAnswer().verdict, isNotNull);
        w.dispose();
      });
    });

    test('back before the camera finished starting: calibration runs', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.startTakesMs = 800;
        w.game.agreeToMeasure();
        w.elapse(100);
        w.goAway();
        w.elapse(200);
        w.comeBack();
        w.startTakesMs = 0;
        w.until(() => w.game.phase == GamePhase.ask, what: 'calibration');
        expect(w.running, isTrue);
        expect(w.game.micEnabled, isTrue);
        expect(w.askAndAnswer().verdict, isNotNull);
        w.dispose();
      });
    });

    test('a native stop that never returns does not hold up the return', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        final starts = w.sdkCalls('start');
        w.stopHangs = Completer<void>();
        w.leaveApp(3000);
        w.stopHangs = null;
        w.elapse(3000);
        expect(w.game.paused, isFalse);
        expect(
          w.sdkCalls('start'),
          starts + 1,
          reason: 'the restart waited on the stop',
        );
        expect(w.askAndAnswer().verdict, isNotNull);
        w.dispose();
      });
    });

    test('a mic error while away does not turn voice off', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        w.leaveApp(
          3000,
          whileAway: () {
            // The recognizer fails as iOS takes the audio session away.
            w.speech.controller.add(
              const SpeechError('RECOGNIZER_FAILING', 'cancelled', 0),
            );
            w.elapse(100);
          },
        );
        expect(w.game.micEnabled, isTrue);
        expect(w.game.notice, isNull);
        w.dispose();
      });
    });

    test('leaving again while Resume restarts the camera', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        w.leaveApp(GameController.autoResumeWithinMs + 5000);
        w.startTakesMs = 800;
        w.game.resume();
        w.elapse(300);
        w.goAway();
        final said = w.host.said.length;
        w.elapse(2000);
        expect(w.game.paused, isTrue);
        expect(w.running, isFalse, reason: 'camera started in the background');
        expect(w.game.micEnabled, isTrue);
        expect(w.host.said.length, said, reason: 'the host spoke while away');
        w.startTakesMs = 0;
        w.comeBack();
        w.elapse(300);
        expect(w.running, isTrue);
        expect(w.game.phase, GamePhase.ask);
        expect(w.askAndAnswer().verdict, isNotNull);
        w.dispose();
      });
    });

    test('leaving again while Skip question restarts the camera', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex'], questions: 3);
        w.calibrate();
        w.leaveApp(GameController.autoResumeWithinMs + 5000);
        w.startTakesMs = 800;
        w.game.skipQuestion();
        w.elapse(300);
        w.goAway();
        final said = w.host.said.length;
        w.elapse(2000);
        expect(w.running, isFalse, reason: 'camera started in the background');
        expect(w.host.said.length, said, reason: 'the host spoke while away');
        w.startTakesMs = 0;
        w.comeBack();
        w.elapse(300);
        expect(w.game.questionIndex, 1, reason: 'the skip moved on once');
        expect(w.game.paused, isFalse);
        expect(w.running, isTrue);
        w.askAndAnswer();
        expect(w.game.currentTurn.results.map((r) => r.index), [
          0,
          1,
        ], reason: 'each question recorded once');
        w.dispose();
      });
    });

    /// Party question 1, answered and settling.
    void answerToSettle(World w) {
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
      expect(w.game.phase, GamePhase.settle);
    }

    test('Skip question from settle: the skipped one never scores', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex'], questions: 3);
        w.calibrate();
        answerToSettle(w);
        // Away past the settle window, then Skip while the mic is slow.
        w.leaveApp(GameController.autoResumeWithinMs + 5000);
        w.speech.startTakesMs = 1000;
        w.game.skipQuestion();
        w.elapse(1500);
        expect(w.game.currentTurn.results.map((r) => (r.index, r.skipped)), [
          (0, true),
        ], reason: 'the skipped question was scored as well');
        expect(w.game.phase, GamePhase.ask);
        expect(w.game.questionIndex, 1);
        w.dispose();
      });
    });

    test('Resume from settle restarts the question, never scores it', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex'], questions: 3);
        w.calibrate();
        answerToSettle(w);
        w.leaveApp(GameController.autoResumeWithinMs + 5000);
        w.speech.startTakesMs = 1000;
        w.game.resume();
        w.elapse(1500);
        expect(
          w.game.currentTurn.results,
          isEmpty,
          reason: 'a question with a broken window was scored',
        );
        expect(w.game.phase, GamePhase.ask, reason: 'the question starts over');
        expect(w.game.questionIndex, 0);
        w.dispose();
      });
    });

    test('Call it! waits for Reveal, through a trip away and after', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        answerToCallIt(w);
        w.elapse(4000);
        w.leaveApp(8000);
        expect(w.game.paused, isFalse);
        expect(w.running, isTrue);
        w.elapse(60000);
        expect(
          w.game.phase,
          GamePhase.callIt,
          reason: 'the vote has no timer (decision 76)',
        );
        w.game.reveal();
        expect(w.game.phase, GamePhase.countdown);
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
      // Still no face, so no pulse: the question waits instead of running
      // into another No clean read (decision 79), and its taps do nothing.
      expect(w.game.waitingForPulse, isTrue);
      w.game.doneAsking();
      w.game.finalAnswer();
      w.elapse(5000);
      expect(w.game.phase, GamePhase.ask);
      expect(w.game.detector, isNull);
      // The face is back: the question starts within a pulse sample or two.
      w.code = 'OK';
      w.until(() => !w.game.waitingForPulse, maxMs: 2500);
      expect(w.host.said.last, 'Alex, ask your question!');
      w.game.doneAsking();
      w.code = 'NO_FACE_FOUND';
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
      expect([for (final d in DeckLibrary.fallback.mild) d.text], contains(q));
      expect(w.host.said.any((l) => l.contains(q)), isTrue);
      expect(
        w.game.soloHoldsQuestion,
        isTrue,
        reason: 'the question stays up until Ready to answer',
      );
      w.elapse(5000);
      expect(w.game.soloHoldsQuestion, isTrue);
      w.game.readyToAnswer();
      expect(w.game.soloHoldsQuestion, isFalse);
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

  test(
    'solo: Ready to answer redraws at once, and only it releases the card',
    () {
      fakeAsync((async) {
        final w = World(async);
        w.game.setMode(GameMode.solo);
        w.startGame(['Sam']);
        w.calibrate();
        w.elapse(100);
        expect(w.game.shownPhase, GamePhase.ask);
        // Recognized words and talking don't release it (decision 76).
        w.say('Maybe');
        w.talk(true);
        w.elapse(600);
        expect(w.game.soloHoldsQuestion, isTrue);
        var redraws = 0;
        w.game.addListener(() => redraws++);
        w.game.readyToAnswer();
        expect(w.game.shownPhase, GamePhase.answer);
        expect(redraws, greaterThan(0), reason: 'redraws without waiting');
        w.dispose();
      });
    },
  );

  test('solo: a turn climbs the heat curve and ends on the hottest', () {
    fakeAsync((async) {
      final w = World(async);
      w.game.setMode(GameMode.solo);
      w.startGame(['Sam'], questions: 5);
      w.calibrate();
      Set<String> heat(int h) => {
        for (final d in DeckLibrary.fallback.mild)
          if (d.heat == h) d.text,
      };
      final asked = <String>[];
      for (var q = 0; q < 5; q++) {
        w.until(() => w.game.phase == GamePhase.answer);
        asked.add(w.game.questionText);
        w.game.finalAnswer();
        w.until(
          () =>
              w.game.phase == GamePhase.verdict ||
              w.game.phase == GamePhase.redo,
        );
        if (w.game.phase == GamePhase.redo) {
          w.game.skipQuestion();
        } else {
          w.game.nextQuestion();
        }
        w.elapse(100);
      }
      expect(heat(1), containsAll(asked.sublist(0, 2)));
      expect(heat(2), containsAll(asked.sublist(2, 4)));
      expect(heat(3), contains(asked[4]));
      w.dispose();
    });
  });

  test('warm-ups come in slot order, and a skip is replaced from its slot', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      w.game.agreeToMeasure();
      w.until(() => w.game.currentWarmup != null, what: 'the first warm-up');
      Set<String> slot(WarmupSlot s) => {
        for (final d in DeckLibrary.fallback.warmup)
          if (d.slot == s) d.text,
      };
      final first = w.game.currentWarmup!.question;
      expect(slot(WarmupSlot.recall), contains(first));
      w.game.skipWarmup();
      w.until(() => w.game.currentWarmup != null, what: 'the next warm-up');
      final second = w.game.currentWarmup!.question;
      expect(slot(WarmupSlot.recall), contains(second));
      expect(second, isNot(first));
      w.until(
        () => w.game.phase == GamePhase.ask,
        what: 'calibration to finish',
      );
      final asked = [
        for (final x in w.game.warmups)
          if (!x.skipped) x.question,
      ];
      expect(
        asked.length,
        greaterThanOrEqualTo(3),
        reason: 'the skip is not one of the three',
      );
      expect(slot(WarmupSlot.recall), contains(asked[0]));
      expect(slot(WarmupSlot.compare), contains(asked[1]));
      expect(slot(WarmupSlot.light), contains(asked[2]));
      w.dispose();
    });
  });

  test('two skips in a row move on to the next slot', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      w.game.agreeToMeasure();
      Set<String> slot(WarmupSlot s) => {
        for (final d in DeckLibrary.fallback.warmup)
          if (d.slot == s) d.text,
      };
      for (final expected in [WarmupSlot.recall, WarmupSlot.recall]) {
        w.until(() => w.game.currentWarmup != null, what: 'a warm-up');
        expect(slot(expected), contains(w.game.currentWarmup!.question));
        expect(w.game.chatBlocks, 1, reason: 'a skip fills nothing');
        expect(w.game.warmupNumber, 1);
        w.game.skipWarmup();
        w.elapse(700); // two taps, not a double tap
      }
      w.until(() => w.game.currentWarmup != null, what: 'a warm-up');
      expect(
        slot(WarmupSlot.compare),
        contains(w.game.currentWarmup!.question),
      );
      expect(w.game.chatBlocks, 3);
      expect(w.game.warmupNumber, 2);
      w.dispose();
    });
  });

  test('calibration asks all three warm-up slots, even after 15 s of chat', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      w.calibrate();
      final asked = [
        for (final x in w.game.warmups)
          if (!x.skipped) x.question,
      ];
      expect(
        asked.length,
        greaterThanOrEqualTo(3),
        reason: 'more only while the baseline is not clean yet',
      );
      for (final (i, s) in WarmupSlot.values.indexed) {
        expect({
          for (final d in DeckLibrary.fallback.warmup)
            if (d.slot == s) d.text,
        }, contains(asked[i]));
      }
      expect(w.game.chatBlocks, 6);
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

  test('voice recognition failing: no transcripts, taps as ever', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      w.calibrate();
      w.speech.controller.add(
        const SpeechError('RECOGNIZER_FAILING', 'nope', 0),
      );
      w.elapse(100);
      expect(w.game.micEnabled, isFalse);
      expect(w.game.notice, contains('no transcripts'));
      w.dispose();
    });
  });

  test('a mic that fails to restart: no transcripts, voice back next turn', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex'], questions: 1);
      w.calibrate();
      w.speech.controller.add(
        const SpeechError('AUDIO_RESTART_FAILED', 'no input', 0),
      );
      w.elapse(100);
      expect(w.game.micEnabled, isFalse);
      expect(w.game.notice, contains('no transcripts for this turn'));
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

  test('no on-device speech stays off for the whole game', () {
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
      final ask = w.host.calls.lastIndexOf('say:Alex, ask your question!');
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
      // The restarted SDK has no pulse yet: the question waits, unread, and
      // its buttons do nothing (decision 79).
      w.elapse(1000);
      expect(w.game.waitingForPulse, isTrue);
      expect(w.host.said.length - 1, first, reason: 'not read while waiting');
      w.game.readyToAnswer();
      w.game.differentQuestion();
      w.elapse(700);
      expect(w.game.phase, GamePhase.ask);
      expect(w.game.detector, isNull);
      w.waitForPulse();
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

  test('voting: pick, switch, take back; only voters, only on Call it! '
      '(decision 77)', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex', 'Priya'], questions: 1);
      w.calibrate();
      final sam = w.game.players[0].id;
      final alex = w.game.players[1].id;
      final priya = w.game.players[2].id;
      w.game.castVote(alex, Vote.sus);
      expect(w.game.pendingVotes, isEmpty, reason: 'not on Call it! yet');
      w.elapse(300);
      w.say('Have you ever lied?');
      w.elapse(500);
      w.game.doneAsking();
      w.elapse(1000);
      w.talk(true);
      w.elapse(1500);
      w.talk(false);
      w.game.finalAnswer();
      w.until(() => w.game.phase == GamePhase.callIt);
      w.game.castVote(sam, Vote.sus);
      expect(w.game.pendingVotes, isEmpty, reason: 'the hot seat never votes');
      w.game.castVote(alex, Vote.legit);
      w.game.castVote(priya, Vote.sus);
      expect(w.game.pendingVotes, {alex: Vote.legit, priya: Vote.sus});
      w.game.castVote(alex, Vote.sus);
      expect(w.game.pendingVotes[alex], Vote.sus, reason: 'switched');
      w.elapse(700); // not a double tap
      w.game.castVote(priya, Vote.sus);
      expect(w.game.pendingVotes.containsKey(priya), isFalse, reason: 'undone');
      w.game.reveal();
      expect(w.game.currentResult!.votes, {alex: Vote.sus});
      w.game.castVote(priya, Vote.legit);
      expect(w.game.currentResult!.votes, {alex: Vote.sus}, reason: 'closed');
      w.dispose();
    });
  });

  group('only taps move the game on (SPEC.md decision 76)', () {
    test('silence, talking and the vote all wait for a tap', () {
      fakeAsync((async) {
        final w = World(async);
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
        // The asker pauses, the player laughs: nothing moves.
        w.elapse(5000);
        w.talk(true);
        w.elapse(800);
        w.talk(false);
        w.elapse(30000);
        expect(w.game.phase, GamePhase.ask);
        expect(w.host.said, isNot(contains('Sam, your answer?')));
        w.game.doneAsking();
        expect(w.game.phase, GamePhase.answer);
        w.elapse(1000);
        w.talk(true);
        w.elapse(300);
        w.say('Nope.');
        w.elapse(1700);
        w.talk(false);
        // The player thinks, the room chats: the answer stays open.
        w.elapse(40000);
        expect(w.game.phase, GamePhase.answer);
        w.game.finalAnswer();
        w.until(() => w.game.phase != GamePhase.settle, what: 'settle');
        expect(w.game.phase, GamePhase.callIt);
        w.elapse(60000);
        expect(w.game.phase, GamePhase.callIt);
        w.game.reveal();
        w.until(() => w.game.phase == GamePhase.verdict);
        final r = w.game.currentResult!;
        expect(r.question, 'Have you ever lied?');
        expect(r.answer, 'Nope.');
        w.elapse(60000);
        expect(w.game.phase, GamePhase.verdict);
        w.dispose();
      });
    });

    test("a slow Done asking still counts toward the pause", () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex'], questions: 1);
        w.calibrate();
        w.elapse(500);
        w.say('Do you floss?');
        final asked = w.now;
        // Slow to tap, slower to answer.
        w.elapse(3000);
        w.game.doneAsking();
        w.elapse(1000);
        w.talk(true);
        w.elapse(300);
        expect(w.game.detector!.tQ1, asked);
        // 4 s from the asker's last words, less 1.5 s for the tap.
        expect(w.game.live.hesitationS, closeTo(2.5, 0.15));
        w.say('Every day.');
        w.elapse(1500);
        w.talk(false);
        w.elapse(500);
        w.game.finalAnswer();
        w.until(() => w.game.phase == GamePhase.callIt);
        expect(w.game.currentResult!.features!.hesitationS, closeTo(2.5, 0.15));
        w.dispose();
      });
    });

    test(
      'answering before Done asking: the answer is timed from its start',
      () {
        fakeAsync((async) {
          final w = World(async);
          w.startGame(['Sam', 'Alex'], questions: 1);
          w.calibrate();
          w.elapse(500);
          w.say('Do you floss?');
          w.elapse(1200);
          w.talk(true);
          final started = w.now;
          w.elapse(2000);
          w.talk(false);
          w.elapse(2000);
          expect(w.game.phase, GamePhase.ask, reason: 'no tap yet');
          w.game.doneAsking();
          expect(w.game.detector!.tA0, started);
          expect(w.game.live.hesitationS, closeTo(1.2, 0.15));
          w.dispose();
        });
      },
    );

    test('a late Final answer: the reading ends 4 s after the last words', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex'], questions: 1);
        w.calibrate();
        w.elapse(500);
        w.say('Have you ever lied?');
        w.elapse(500);
        w.game.doneAsking();
        w.elapse(800);
        w.talk(true);
        w.elapse(2000);
        w.talk(false);
        final quiet = w.now;
        w.elapse(30000);
        w.game.finalAnswer();
        final d = w.game.detector!;
        expect(d.tA1, closeTo(quiet + 4000, 100));
        // The window closed long ago: no Locking in.
        w.elapse(200);
        expect(w.game.phase, GamePhase.callIt);
        w.dispose();
      });
    });

    test('calibration waits for Next on each warm-up and for Start', () {
      fakeAsync((async) {
        final w = World(async)..autoTaps = false;
        w.startGame(['Sam', 'Alex']);
        w.game.agreeToMeasure();
        w.until(() => w.game.calibStage == CalibStage.chat, what: 'chat');
        final first = w.game.currentWarmup!;
        // Answered (World talks 0.8–2.8 s after it's asked), then silence.
        w.elapse(60000);
        expect(identical(w.game.currentWarmup, first), isTrue);
        expect(first.done, isFalse);
        while (w.game.calibStage == CalibStage.chat) {
          final warmup = w.game.currentWarmup!;
          w.until(() => warmup.latencyS != null && !w.talking, what: 'answer');
          w.elapse(1000);
          w.game.nextWarmup();
          expect(warmup.done, isTrue);
          expect(warmup.doneAtMs, lessThan(w.now), reason: 'at the talk end');
          w.elapse(100);
        }
        expect(w.game.calibStage, CalibStage.ready);
        expect(w.game.warmupSlotsDone, 3);
        expect(w.host.said.last, "That's your normal locked in.");
        final baseline = w.game.calibBaseline;
        expect(baseline, isNotNull);
        // A double tap on the last Next doesn't start the questions.
        w.game.startQuestions();
        expect(w.game.phase, GamePhase.calibrate);
        w.elapse(60000);
        expect(w.game.phase, GamePhase.calibrate);
        expect(
          identical(w.game.calibBaseline, baseline),
          isTrue,
          reason: 'nothing after the lock goes into the normal',
        );
        w.game.startQuestions();
        expect(w.game.phase, GamePhase.ask);
        expect(w.game.currentTurn.baseline, same(baseline));
        expect(w.host.said.last, 'Alex, ask your question!');
        w.dispose();
      });
    });

    test('solo: the question card stays up until Ready to answer', () {
      fakeAsync((async) {
        final w = World(async);
        w.game.setMode(GameMode.solo);
        w.startGame(['Sam'], questions: 1);
        w.calibrate();
        w.elapse(500);
        expect(w.game.phase, GamePhase.answer, reason: 'host finished');
        w.talk(true);
        w.elapse(300);
        w.say('Never.');
        w.elapse(1500);
        w.talk(false);
        w.elapse(30000);
        expect(w.game.soloHoldsQuestion, isTrue);
        expect(w.game.shownPhase, GamePhase.ask);
        expect(w.game.live.answerText, 'Never.');
        w.game.readyToAnswer();
        expect(w.game.shownPhase, GamePhase.answer);
        expect(w.game.phase, GamePhase.answer, reason: 'still answering');
        w.dispose();
      });
    });
  });

  group('the host says who asks (SPEC.md decision 76)', () {
    test('the other players take turns, starting after the hot seat', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex', 'Priya'], questions: 3);
        w.calibrate();
        final asked = <String>[];
        for (var q = 0; q < 3; q++) {
          asked.add(w.game.askLine);
          expect(w.host.said.last, w.game.askLine);
          w.askAndAnswer(question: 'Q$q?');
          if (q < 2) w.game.nextQuestion();
        }
        expect(asked, [
          'Alex, ask your question!',
          'Priya, ask your question!',
          'Alex, ask your question!',
        ]);
        w.game.nextQuestion();
        w.elapse(100);
        expect(w.game.phase, GamePhase.consent);
        expect(w.game.currentPlayer.name, 'Alex');
        w.calibrate();
        expect(w.game.askLine, 'Priya, ask your question!');
        w.askAndAnswer();
        w.game.nextQuestion();
        expect(w.game.askLine, 'Sam, ask your question!');
        expect(w.host.said.last, 'Sam, ask your question!');
        w.dispose();
      });
    });

    test('the next asker is known a question ahead, and none after the '
        "turn's last", () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex', 'Priya'], questions: 3);
        // Before the first question: Calibrate can already say who's first.
        expect(w.game.currentAsker!.name, 'Alex');
        w.calibrate();
        for (final (asker, next) in [
          ('Alex', 'Priya'),
          ('Priya', 'Alex'),
          ('Alex', null),
        ]) {
          expect(w.game.currentAsker!.name, asker);
          w.askAndAnswer();
          expect(w.game.phase, GamePhase.verdict);
          expect(w.game.nextAsker?.name, next);
          w.game.nextQuestion();
          w.elapse(100);
          if (next != null) expect(w.game.currentAsker!.name, next);
        }
        expect(w.game.phase, GamePhase.consent);
        w.dispose();
      });
    });

    test('solo has no next asker either', () {
      fakeAsync((async) {
        final w = World(async);
        w.game.setMode(GameMode.solo);
        w.startGame(['Sam'], questions: 3);
        w.calibrate();
        expect(w.game.nextAsker, isNull);
        w.dispose();
      });
    });

    test("the lobby's estimate: none until the game can start, then it "
        'grows with players and questions', () {
      fakeAsync((async) {
        final w = World(async);
        final game = w.game;
        expect(game.estimatedMinutes, isNull);
        game.addPlayer('Sam');
        expect(game.estimatedMinutes, isNull, reason: 'a party needs two');
        game.addPlayer('Alex');
        // 2 × (75 s + 1 × 40 s) = 230 s, with the default of one question.
        expect(game.estimatedMinutes, 4);
        game.setQuestionsPerTurn(5);
        expect(game.estimatedMinutes, 9);
        for (final n in ['Priya', 'Jordan', 'Kai', 'Mo', 'Lee', 'Ana']) {
          game.addPlayer(n);
        }
        // 8 × (75 s + 5 × 40 s): over half an hour.
        expect(game.estimatedMinutes, 37);
        game.setQuestionsPerTurn(3);
        expect(game.estimatedMinutes, 26);
        w.dispose();
      });
    });

    test('a solo player gets an estimate too', () {
      fakeAsync((async) {
        final w = World(async);
        w.game
          ..setMode(GameMode.solo)
          ..addPlayer('Sam')
          ..setQuestionsPerTurn(3);
        expect(w.game.estimatedMinutes, 3);
        w.dispose();
      });
    });

    test('a question asked again keeps its asker', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex', 'Priya'], questions: 3);
        w.calibrate();
        w.askAndAnswer();
        w.game.nextQuestion();
        expect(w.game.currentAsker!.name, 'Priya');
        // Away long enough that the question starts over.
        w.leaveApp(GameController.autoResumeWithinMs + 5000);
        w.game.resume();
        w.elapse(1500);
        expect(w.game.phase, GamePhase.ask);
        expect(w.host.said.last, 'Priya, ask your question!');
        w.dispose();
      });
    });

    test('solo has no asker', () {
      fakeAsync((async) {
        final w = World(async);
        w.game.setMode(GameMode.solo);
        w.startGame(['Sam'], questions: 1);
        w.calibrate();
        expect(w.game.currentAsker, isNull);
        expect(
          w.host.said.where((l) => l.contains('ask your question')),
          isEmpty,
        );
        w.dispose();
      });
    });
  });

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
