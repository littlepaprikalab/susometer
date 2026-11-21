// Reliability pass over decisions 93 and 94 (SPEC.md decision 95): the
// Verdict's pulse chart (the answer shaded or marked, the delta scale) and
// the Replay rows, through the real screens, on the smallest phone at the
// largest text the app allows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/screens/question_screens.dart';
import 'package:susometer/screens/result_screens.dart';
import 'package:susometer/theme/widgets.dart';

import 'rig.dart';

extension on Rig {
  Future<void> startSolo(String name) async {
    presage.storedKey = 'k';
    await tap('Solo · host asks');
    await addPlayer(name);
    await tap('3');
    await tap('Start the show');
    await wait(300);
    if (game.phase == GamePhase.howToPlay) await tap("Got it, let's play");
    autoTaps = true;
    if (game.phase == GamePhase.consent) await tap('I agree, measure me');
  }

  /// A solo answer: [say] heard with the camera missing it, [talk] seen by
  /// the camera, or neither. The pulse runs [rise] BPM above the normal.
  Future<void> answer({String? say, bool talk = false, double rise = 0}) async {
    await until(() => game.phase == GamePhase.answer, what: 'the question');
    await until(() => !game.waitingForPulse, what: 'the pulse');
    final base = game.currentTurn.baseline!.pulse;
    await wait(500);
    await tap(readyCardLabel);
    presage.pulse = base + rise;
    await wait(2000);
    if (say != null) this.say(say);
    if (talk) presage.talk(true);
    await wait(1500);
    if (talk) presage.talk(false);
    await wait(1500);
    await tap('Final answer');
    presage.pulse = base;
    await until(() => game.phase == GamePhase.verdict, what: 'the verdict');
    await wait(300);
  }
}

/// The Verdict's pulse card, scrolled into view.
Future<Rect> pulseCard(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(PulseTrace));
  await tester.pump(const Duration(milliseconds: 300));
  return tester.getRect(
    find
        .ancestor(of: find.byType(PulseTrace), matching: find.byType(SusCard))
        .first,
  );
}

void expectInside(WidgetTester tester, Finder f, Rect card, String what) {
  final r = tester.getRect(f);
  expect(
    r.left >= card.left - 0.5 &&
        r.right <= card.right + 0.5 &&
        r.top >= card.top - 0.5 &&
        r.bottom <= card.bottom + 0.5,
    isTrue,
    reason: '$what $r runs outside the card $card',
  );
}

void main() {
  for (final (screen, scale) in const [
    (Size(320, 568), 1.3),
    (Size(375, 667), 1.3),
    (Size(390, 844), 1.0),
  ]) {
    testWidgets('solo: the Verdict chart shades, marks and labels the answer, '
        'and the Replay rows draw, without overflow '
        '(${screen.width.round()}×${screen.height.round()}, text ×$scale)', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = Rig(tester);
      await rig.pumpApp(size: screen);
      await rig.startSolo('Christopher-Alexandr');

      // Heard, missed by the camera, and a big rise: shaded, ±20.
      await rig.answer(say: 'Chair omelette', rise: 22);
      var card = await pulseCard(tester);
      final verdictTrace = tester.widget<PulseTrace>(find.byType(PulseTrace));
      expect(verdictTrace.deltaScale, isTrue);
      expect(answerMarkFor(verdictTrace.result), AnswerMark.shaded);
      expectInside(tester, find.text('Answering'), card, 'legend');
      expectInside(tester, find.byType(PulseTrace), card, 'chart');
      expect(tester.takeException(), isNull);
      await rig.tap('Next question');
      await rig.wait(300);

      // Nothing heard: a rule at Final answer, and the legend says so.
      await rig.answer();
      card = await pulseCard(tester);
      expect(
        answerMarkFor(
          tester.widget<PulseTrace>(find.byType(PulseTrace)).result,
        ),
        AnswerMark.finalAnswer,
      );
      expect(find.text('Answering'), findsNothing);
      expectInside(tester, find.text('Final answer'), card, 'legend');
      expect(tester.takeException(), isNull);
      await rig.tap('Next question');
      await rig.wait(300);

      // Seen by the camera, as before.
      await rig.answer(talk: true, rise: 4);
      card = await pulseCard(tester);
      expectInside(tester, find.text('Answering'), card, 'legend');
      expect(tester.takeException(), isNull);

      // The Replay: one short row chart per question, no scale, each with
      // its own mark. The list builds rows as they scroll in.
      await rig.tap('See the winners');
      await rig.wait(600);
      await rig.tap('Watch the replay');
      await rig.wait(600);
      expect(tester.takeException(), isNull, reason: 'the Replay header');
      final seen = <int, PulseTrace>{};
      for (var i = 0; i < 6; i++) {
        for (final r in tester.widgetList<PulseTrace>(
          find.byType(PulseTrace),
        )) {
          seen[r.result.index] = r;
        }
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await rig.wait(300);
      }
      expect(seen.keys.toList()..sort(), [0, 1, 2]);
      expect(seen.values.map((r) => r.deltaScale), everyElement(isFalse));
      expect(
        [
          for (final i in [0, 1, 2]) answerMarkFor(seen[i]!.result),
        ],
        [AnswerMark.shaded, AnswerMark.finalAnswer, AnswerMark.shaded],
      );
      expect(tester.takeException(), isNull);
      await rig.finish();
    });
  }
}
