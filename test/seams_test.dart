// End-to-end checks of the scoring fixes (SPEC.md decisions 65–67) through
// the real controller: bridge snapshot maps → PresageSample → SignalLog →
// calibration baseline → question score, and the same stream → #tag.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';

import 'world.dart';

void main() {
  test('an honest, smiling answer from a frequent blinker is Legit, '
      'and the camera stamps #happy, not #contempt', () {
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

      // A real question: Sam smiles while answering, and the SDK scores the
      // smile as contempt just as much as happy.
      expect(w.game.phase, GamePhase.ask);
      w.elapse(300);
      w.say('Have you ever re-gifted a present?');
      w.elapse(1500);
      w.game.doneAsking();
      w.elapse(1300);
      w.talk(true);
      w.expr = const {'happy': 0.4, 'contempt': 0.4, 'neutral': 0.2};
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
      expect(b.zExpr, lessThan(0.1), reason: 'the smile cancels');
      expect(b.zBlink, 0, reason: 'blinking like in the warm-ups');
      expect(b.verdict, Verdict.legit, reason: 'score ${b.score}');
      w.dispose();
    });
  });

  test('a long warm-up answer is not cut off; a stuck talking flag still '
      'moves on', () {
    fakeAsync((async) {
      final w = World(async)..autoAnswerWarmups = false;
      w.startGame(['Sam', 'Alex']);
      w.game.agreeToMeasure();
      w.until(
        () => w.game.calibStage == CalibStage.chat,
        what: 'the chat phase',
      );

      // Warm-up 1: talks for 16 s, well past the 12 s limit.
      final first = w.game.currentWarmup!;
      w.elapse(800);
      w.talk(true);
      w.elapse(16000);
      expect(first.done, isFalse, reason: 'still talking at 16.8 s');
      w.talk(false);
      w.until(() => first.done, maxMs: 3000, what: 'warm-up 1 to end');
      expect(first.latencyS, closeTo(0.8, 0.3));
      expect(
        first.timingUntil(w.now)!.tA1 - first.askedAtMs,
        greaterThan(16000),
        reason: 'its window covers the whole answer',
      );

      // Warm-up 2: the talking flag sticks on; it moves on at 25 s anyway.
      final second = w.game.currentWarmup!;
      expect(identical(second, first), isFalse);
      w.elapse(800);
      w.talk(true);
      w.until(() => second.done, maxMs: 26000, what: 'warm-up 2 to end');
      expect(w.now - second.askedAtMs, inInclusiveRange(25000, 25500));
      w.talk(false);

      // And calibration still finishes (a third warm-up, answered).
      w.autoAnswerWarmups = true;
      w.until(
        () => w.game.phase == GamePhase.ask,
        what: 'calibration to finish',
      );
      expect(w.game.currentTurn.baseline, isNotNull);
      w.dispose();
    });
  });
}
