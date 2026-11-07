// End-to-end checks of the scoring fixes (SPEC.md decisions 65–67 and 70) through
// the real controller: bridge snapshot maps → PresageSample → SignalLog →
// calibration baseline → question score, and the same stream → #tag.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';

import 'world.dart';

void main() {
  test('an honest, smiling answer from a frequent blinker is Legit, '
      'and the camera stamps #happy', () {
    fakeAsync((async) {
      final w = World(async);
      // 10 blinks a minute sitting still, 24 while chatting and answering.
      w.blinkEveryMs = () =>
          w.game.phase == GamePhase.calibrate &&
              w.game.calibStage != CalibStage.chat
          ? 6000
          : 2500;
      w.startGame(['Sam', 'Alex']);
      w.calibrate();
      final base = w.game.currentTurn.baseline!;
      expect(
        base.blinkRatePerMin,
        greaterThan(18),
        reason: 'the chat rate, not the still-and-chat mix',
      );

      // A real question: Sam smiles while answering.
      expect(w.game.phase, GamePhase.ask);
      w.elapse(300);
      w.say('Have you ever re-gifted a present?');
      w.elapse(1500);
      w.game.doneAsking();
      w.elapse(1300);
      w.talk(true);
      w.expr = const {'happy': 0.6, 'neutral': 0.3};
      w.say('Ha, no. Never. I keep everything.');
      w.elapse(2500);
      expect(w.game.live.expression.tag, 'happy');
      w.talk(false);
      w.expr = const {'neutral': 0.8, 'surprise': 0.05};
      w.elapse(800);
      w.game.finalAnswer();
      w.until(() => w.game.phase != GamePhase.settle, what: 'settle');
      if (w.game.phase == GamePhase.callIt) w.game.reveal();
      w.until(() => w.game.phase == GamePhase.verdict, what: 'verdict');

      final b = w.game.currentResult!.breakdown!;
      expect(b.zExpr, lessThan(0.1), reason: 'a smile is not scored');
      expect(b.zBlink, 0, reason: 'blinking like in the warm-ups');
      expect(b.verdict, Verdict.legit, reason: 'score ${b.score}');
      w.dispose();
    });
  });

  test('happy beside a stress expression neither cancels it in the score '
      'nor wins the #tag', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      w.calibrate();
      expect(w.game.phase, GamePhase.ask);
      w.elapse(300);
      w.say('Have you ever read someone else\'s messages?');
      w.elapse(1500);
      w.game.doneAsking();
      w.elapse(1300);
      w.talk(true);
      // Contempt and happy nearly tied (inside the tag's 0.05 margin).
      w.expr = const {'contempt': 0.45, 'happy': 0.42, 'neutral': 0.1};
      w.say('No, never.');
      w.elapse(2500);
      expect(w.game.live.expression.tag, isNull, reason: 'a close call');
      w.talk(false);
      w.expr = const {'neutral': 0.8, 'surprise': 0.05};
      w.elapse(800);
      w.game.finalAnswer();
      w.until(() => w.game.phase != GamePhase.settle, what: 'settle');
      if (w.game.phase == GamePhase.callIt) w.game.reveal();
      w.until(() => w.game.phase == GamePhase.verdict, what: 'verdict');

      final r = w.game.currentResult!;
      expect(r.features!.exprPeakCategory, 'contempt');
      // The warm-ups had no contempt, so all 0.45 counts (÷ 0.3, capped).
      expect(r.features!.exprPeakDelta, closeTo(0.45, 1e-9));
      expect(r.breakdown!.zExpr, 1.0);
      w.dispose();
    });
  });

  test('a warm-up waits for Next: a long answer is never cut off, a stuck '
      'talking flag never moves it on', () {
    fakeAsync((async) {
      final w = World(async)
        ..autoAnswerWarmups = false
        ..autoTaps = false;
      w.startGame(['Sam', 'Alex']);
      w.game.agreeToMeasure();
      w.until(
        () => w.game.calibStage == CalibStage.chat,
        what: 'the chat phase',
      );

      // Warm-up 1: talks for 16 s, then a long silence.
      final first = w.game.currentWarmup!;
      w.elapse(800);
      w.talk(true);
      w.elapse(16000);
      w.talk(false);
      final quiet = w.now;
      w.elapse(30000);
      expect(first.done, isFalse, reason: 'nothing moves on by itself');
      w.game.nextWarmup();
      expect(first.done, isTrue);
      expect(first.latencyS, closeTo(0.8, 0.3));
      expect(first.doneAtMs, quiet, reason: 'it ended when the talk did');
      expect(
        first.timingUntil(w.now)!.tA1 - first.askedAtMs,
        greaterThan(16000),
        reason: 'its window covers the whole answer',
      );

      // Warm-up 2: the talking flag sticks on; still there a minute later.
      final second = w.game.currentWarmup!;
      expect(identical(second, first), isFalse);
      w.elapse(800);
      w.talk(true);
      w.elapse(60000);
      expect(second.done, isFalse);
      w.game.nextWarmup();
      expect(
        second.doneAtMs,
        second.askedAtMs + 60000,
        reason: 'still talking at the tap: a minute after it was asked',
      );
      w.talk(false);

      // And calibration still finishes (a third warm-up, answered).
      w
        ..autoAnswerWarmups = true
        ..autoTaps = true;
      w.until(
        () => w.game.phase == GamePhase.ask,
        what: 'calibration to finish',
      );
      expect(w.game.currentTurn.baseline, isNotNull);
      w.dispose();
    });
  });

  group('seams of decision 76', () {
    /// Calibrates with the taps by hand, up to "Start the questions".
    void toReady(World w) {
      w.autoTaps = false;
      w.game.agreeToMeasure();
      w.until(() => w.game.calibStage == CalibStage.chat, what: 'chat');
      while (w.game.calibStage == CalibStage.chat) {
        final warmup = w.game.currentWarmup!;
        w.until(() => warmup.latencyS != null && !w.talking, what: 'answer');
        w.elapse(1000);
        w.game.nextWarmup();
        w.elapse(100);
      }
      expect(w.game.calibStage, CalibStage.ready);
    }

    test('a trip away while waiting on Start keeps the locked-in normal', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        toReady(w);
        final base = w.game.calibBaseline;
        final warmups = w.game.warmups.length;
        void stillReady(String why) {
          expect(w.game.phase, GamePhase.calibrate, reason: why);
          expect(w.game.calibStage, CalibStage.ready, reason: why);
          expect(w.game.calibBaseline, same(base), reason: why);
          expect(
            w.game.warmups.length,
            warmups,
            reason: '$why: no new warm-up',
          );
          expect(w.game.paused, isFalse, reason: why);
          expect(w.running, isTrue, reason: why);
          expect(w.game.tickerRunning, isTrue, reason: why);
        }

        var starts = w.sdkCalls('start');
        w.leaveApp(3000);
        stillReady('a screenshot');
        expect(w.sdkCalls('start'), starts + 1);

        starts = w.sdkCalls('start');
        w.leaveApp(GameController.autoResumeWithinMs + 5000);
        expect(w.game.showPauseSheet, isTrue);
        w.game.resume();
        w.elapse(300);
        stillReady('a long trip, then Resume');
        expect(w.sdkCalls('start'), starts + 1);

        // Start tapped while a slow camera is still coming back: it plays.
        w.startTakesMs = 1000;
        w.leaveApp(3000);
        w.game.startQuestions();
        expect(w.game.phase, GamePhase.ask);
        w.elapse(1500);
        expect(w.game.tickerRunning, isTrue);
        expect(w.game.currentTurn.baseline, same(base));
        expect(w.askAndAnswer().verdict, isNotNull);
        w.dispose();
      });
    });

    test('E5 while waiting on Start: Try again goes back to the wait', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        toReady(w);
        final base = w.game.calibBaseline;
        final warmups = w.game.warmups.length;
        w.emitting = false;
        w.until(() => w.game.phase == GamePhase.sdkOffline, maxMs: 40000);
        expect(w.running, isFalse);
        w.emitting = true;
        w.game.retrySdk();
        w.elapse(300);
        expect(w.game.phase, GamePhase.calibrate);
        expect(w.game.calibStage, CalibStage.ready);
        expect(w.game.calibBaseline, same(base));
        expect(w.game.warmups.length, warmups);
        expect(w.running, isTrue);
        expect(w.game.tickerRunning, isTrue);
        w.game.startQuestions();
        expect(w.game.phase, GamePhase.ask);
        expect(w.askAndAnswer().verdict, isNotNull);
        w.dispose();
      });
    });

    test('Pause and Skip again while the camera restarts: one result per '
        'question, and Resume brings the ticker back', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex'], questions: 3);
        w.calibrate();
        w.leaveApp(GameController.autoResumeWithinMs + 5000);
        w.startTakesMs = 1500;
        w.game.skipQuestion();
        w.elapse(100);
        // The sheet closed while the camera restarts: the old question's
        // Final answer is on screen but does nothing.
        expect(w.game.phase, GamePhase.ask);
        w.game.finalAnswer();
        w.game.pause();
        w.elapse(700);
        w.game.skipQuestion();
        w.elapse(3000);
        expect(
          [for (final r in w.game.currentTurn.results) r.index],
          [0],
          reason: 'skipped once, scored never',
        );
        expect(w.game.questionIndex, 1);
        w.game.resume();
        w.elapse(300);
        expect(w.game.tickerRunning, isTrue);
        final r = w.askAndAnswer();
        expect(r.index, 1);
        w.dispose();
      });
    });

    test('solo: a minute and a half on the card, then an answer: scored as '
        'the minute after the question, quickly', () {
      fakeAsync((async) {
        final w = World(async);
        w.heart = (_) => 72;
        w.game.setMode(GameMode.solo);
        w.startGame(['Sam'], questions: 1);
        w.calibrate();
        w.elapse(500);
        w.elapse(90000);
        w.game.readyToAnswer();
        w.elapse(800);
        w.talk(true);
        w.elapse(3000);
        w.talk(false);
        w.elapse(500);
        w.game.finalAnswer();
        w.until(
          () =>
              w.game.phase == GamePhase.verdict ||
              w.game.phase == GamePhase.redo,
        );
        final t = w.game.currentResult!.timing!;
        expect(t.tA0, isNull);
        expect(t.tA1 - t.tQ1, 60000);
        expect(t.windowEnd(12000) - t.tQ0, lessThanOrEqualTo(65000));
        w.dispose();
      });
    });

    test('a warm-up whose talking flag sticks until a late Next ends a minute '
        'after it was asked', () {
      fakeAsync((async) {
        final w = World(async)
          ..autoAnswerWarmups = false
          ..autoTaps = false;
        w.startGame(['Sam', 'Alex']);
        w.game.agreeToMeasure();
        w.until(() => w.game.calibStage == CalibStage.chat, what: 'chat');
        final first = w.game.currentWarmup!;
        w.elapse(800);
        w.talk(true);
        w.elapse(10 * 60000);
        w.game.nextWarmup();
        w.talk(false);
        expect(first.doneAtMs! - first.askedAtMs, 60000);
        w.dispose();
      });
    });

    test('a double tap on a pick keeps the vote; switching always works', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex', 'Priya'], questions: 1);
        w.calibrate();
        w.elapse(300);
        w.say('Have you ever lied?');
        w.elapse(500);
        w.game.doneAsking();
        w.elapse(800);
        w.talk(true);
        w.elapse(1500);
        w.talk(false);
        w.game.finalAnswer();
        w.until(() => w.game.phase == GamePhase.callIt);
        final [alex, priya] = [for (final v in w.game.voters) v.id];
        w.game.castVote(alex, Vote.legit);
        w.elapse(80);
        w.game.castVote(alex, Vote.legit);
        expect(w.game.pendingVotes[alex], Vote.legit, reason: 'double tap');
        w.game.castVote(alex, Vote.sus);
        expect(w.game.pendingVotes[alex], Vote.sus, reason: 'switched at once');
        w.game.castVote(priya, Vote.sus);
        expect(w.game.pendingVotes[priya], Vote.sus, reason: 'another voter');
        w.elapse(700);
        w.game.castVote(alex, Vote.sus);
        expect(w.game.pendingVotes.containsKey(alex), isFalse, reason: 'undo');
        // The votes survive a screenshot and a long trip away.
        w.game.castVote(alex, Vote.legit);
        w.leaveApp(3000);
        expect(w.game.phase, GamePhase.callIt);
        w.leaveApp(GameController.autoResumeWithinMs + 5000);
        w.game.resume();
        w.elapse(300);
        expect(w.game.pendingVotes, {alex: Vote.legit, priya: Vote.sus});
        w.game.reveal();
        expect(w.game.currentResult!.votes, {
          alex: Vote.legit,
          priya: Vote.sus,
        });
        w.dispose();
      });
    });

    test('nothing behind the Pause sheet moves the game on', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex'], questions: 2);
        toReady(w);
        // Waiting on Start.
        w.game.pause();
        w.elapse(700);
        w.game.startQuestions();
        expect(w.game.phase, GamePhase.calibrate);
        w.game.resume();
        w.elapse(300);
        w.game.startQuestions();
        expect(w.game.phase, GamePhase.ask);
        // Asking: Done asking and Final answer.
        w.elapse(300);
        w.say('Have you ever lied?');
        w.elapse(500);
        w.game.pause();
        w.game.doneAsking();
        w.game.finalAnswer();
        expect(w.game.phase, GamePhase.ask);
        w.game.resume();
        w.elapse(300);
        w.say('Have you ever lied?');
        w.elapse(500);
        w.game.doneAsking();
        w.elapse(800);
        w.talk(true);
        w.elapse(1500);
        w.talk(false);
        // Answering: a Final answer while paused would score the pause.
        w.game.pause();
        w.elapse(15000);
        w.game.finalAnswer();
        w.elapse(200);
        expect(w.game.phase, GamePhase.answer);
        expect(w.game.currentTurn.results, isEmpty);
        w.game.resume();
        w.elapse(300);
        expect(w.game.phase, GamePhase.ask, reason: 'the question starts over');
        // Call it! after a long trip: the sheet is up; votes and Reveal wait.
        final r = w.askAndAnswer(votesSus: const []);
        expect(r.index, 0);
        w.until(() => w.game.phase == GamePhase.verdict);
        w.leaveApp(GameController.autoResumeWithinMs + 5000);
        expect(w.game.showPauseSheet, isTrue);
        w.game.nextQuestion();
        w.game.endTurn();
        w.elapse(700);
        expect(w.game.phase, GamePhase.verdict, reason: 'verdict, paused');
        w.game.resume();
        w.elapse(300);
        w.game.nextQuestion();
        w.elapse(100);
        expect(w.game.phase, GamePhase.ask);
        w.elapse(300);
        w.say('Do you floss?');
        w.elapse(500);
        w.game.doneAsking();
        w.elapse(800);
        w.talk(true);
        w.elapse(1500);
        w.talk(false);
        w.game.finalAnswer();
        w.until(() => w.game.phase == GamePhase.callIt);
        w.leaveApp(GameController.autoResumeWithinMs + 5000);
        final alex = w.game.voters.single.id;
        w.game.castVote(alex, Vote.sus);
        w.game.reveal();
        expect(w.game.phase, GamePhase.callIt);
        expect(w.game.pendingVotes, isEmpty);
        w.game.resume();
        w.elapse(300);
        w.game.castVote(alex, Vote.sus);
        w.game.reveal();
        expect(w.game.phase, GamePhase.countdown);
        expect(w.game.currentResult!.votes, {alex: Vote.sus});
        w.dispose();
      });
    });

    test('a double tap on Doesn\'t apply skips one warm-up, not two', () {
      fakeAsync((async) {
        final w = World(async)..autoTaps = false;
        w.startGame(['Sam', 'Alex']);
        w.game.agreeToMeasure();
        w.until(() => w.game.calibStage == CalibStage.chat, what: 'chat');
        w.game.skipWarmup();
        w.elapse(80);
        w.game.skipWarmup();
        expect(w.game.warmups.where((x) => x.skipped).length, 1);
        expect(w.game.warmupSlotsDone, 0, reason: 'still on the first slot');
        w.dispose();
      });
    });

    test('an answer before Done asking is the answer, not part of the '
        'question (PR #18 review)', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex'], questions: 1);
        w.calibrate();
        w.elapse(300);
        w.say('Have you ever lied?');
        final asked = w.speech.segment;
        w.elapse(1200);
        w.talk(true);
        w.elapse(400);
        // Like the recognizer: a segment's partials replace each other, so
        // with no new segment the answer would arrive inside the question's.
        w.say(
          w.speech.segment == asked
              ? 'Have you ever lied? No, never.'
              : 'No, never.',
        );
        w.elapse(1500);
        w.talk(false);
        w.elapse(1000);
        expect(w.game.live.askerText, 'Have you ever lied?');
        w.game.doneAsking();
        expect(w.game.live.answerText, 'No, never.');
        w.elapse(500);
        w.game.finalAnswer();
        w.until(() => w.game.phase == GamePhase.callIt);
        expect(w.game.currentResult!.question, 'Have you ever lied?');
        expect(w.game.currentResult!.answer, 'No, never.');
        w.dispose();
      });
    });

    test('a reaction the asker talks over stays in the question', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex'], questions: 1);
        w.calibrate();
        w.elapse(300);
        w.say('Have you ever');
        w.elapse(300);
        w.talk(true);
        w.elapse(500);
        w.talk(false);
        w.elapse(1500);
        // The asker carries on; whichever segment it lands in, it's theirs.
        w.say('Have you ever lied to me?');
        w.elapse(1000);
        w.game.doneAsking();
        w.elapse(800);
        w.talk(true);
        w.elapse(300);
        w.say('Nope.');
        w.elapse(1500);
        w.talk(false);
        w.game.finalAnswer();
        w.until(() => w.game.phase == GamePhase.callIt);
        expect(
          w.game.currentResult!.question,
          endsWith('Have you ever lied to me?'),
        );
        expect(w.game.currentResult!.answer, 'Nope.');
        w.dispose();
      });
    });

    test('a warm-up answered only after a minute counts as unanswered '
        '(PR #18 review)', () {
      fakeAsync((async) {
        final w = World(async)
          ..autoAnswerWarmups = false
          ..autoTaps = false;
        w.startGame(['Sam', 'Alex']);
        w.game.agreeToMeasure();
        w.until(() => w.game.calibStage == CalibStage.chat, what: 'chat');
        final first = w.game.currentWarmup!;
        w.elapse(3 * 60000);
        w.talk(true);
        w.elapse(2000);
        w.talk(false);
        w.elapse(1000);
        w.game.nextWarmup();
        expect(first.latencyS, isNull, reason: 'too late to be its answer');
        expect(first.timingUntil(w.now), isNull, reason: 'no window at all');
        w.dispose();
      });
    });

    test('Pause just after a short trip, while the camera restarts: Resume '
        'still starts the ticker', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        w.startTakesMs = 1000;
        w.leaveApp(3000);
        w.game.pause();
        w.elapse(2000);
        expect(w.game.tickerRunning, isFalse, reason: 'the restart gave up');
        w.game.resume();
        w.elapse(100);
        expect(w.game.tickerRunning, isTrue);
        // Without the ticker, Locking in would never end.
        expect(w.askAndAnswer().verdict, isNotNull);
        w.dispose();
      });
    });
  });
}
