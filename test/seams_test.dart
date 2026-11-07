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
      expect(second.doneAtMs, w.now, reason: 'still talking: at the tap');
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
}
