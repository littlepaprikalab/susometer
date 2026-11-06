import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/theme/fit_text.dart';
import 'package:susometer/theme/tokens.dart';

Future<String> fit(
  WidgetTester tester,
  String text, {
  FitOverflow overflow = FitOverflow.keepEnd,
  Size box = const Size(300, 60),
  TextStyle Function(double)? style,
  List<double> sizes = const [28, 22, 18],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      // A Scaffold, like the app: its default text style has a taller line
      // height than plain Text, which FitText must measure with.
      home: Scaffold(
        body: Center(
          child: SizedBox.fromSize(
            size: box,
            child: FitText(
              text,
              overflow: overflow,
              sizes: sizes,
              style: style ?? (s) => SusText.display(s),
            ),
          ),
        ),
      ),
    ),
  );
  final shown = tester.widget<Text>(find.byType(Text));
  // The laid-out text itself, not the widget (which its box clamps).
  final paragraph = tester.renderObject<RenderParagraph>(find.byType(RichText));
  if (box.height > 0) {
    expect(
      paragraph.textSize.height,
      lessThanOrEqualTo(box.height + 0.5),
      reason: 'never taller than its box',
    );
  }
  return shown.data!;
}

const long =
    'No way absolutely not I would never okay maybe once but it was a really '
    'ugly sweater and honestly anyone would have done it';

void main() {
  testWidgets('short text keeps the biggest size', (tester) async {
    expect(await fit(tester, 'Maybe once.'), 'Maybe once.');
    final t = tester.widget<Text>(find.byType(Text));
    expect(t.style!.fontSize, 28);
  });

  testWidgets('a long transcript keeps whole newest words, after "…"', (
    tester,
  ) async {
    final shown = await fit(tester, long);
    expect(shown, startsWith('…'));
    expect(shown, endsWith('anyone would have done it'));
    expect(long.endsWith(shown.substring(1)), isTrue, reason: 'whole words');
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel(long), findsOneWidget, reason: 'VoiceOver');
    handle.dispose();
  });

  testWidgets('a long question keeps its start and ends in an ellipsis', (
    tester,
  ) async {
    final shown = await fit(tester, long, overflow: FitOverflow.keepStart);
    expect(shown, long);
    final t = tester.widget<Text>(find.byType(Text));
    expect(t.overflow, TextOverflow.ellipsis);
    expect(t.maxLines, greaterThanOrEqualTo(1));
  });

  testWidgets('one giant word still fits without throwing', (tester) async {
    await fit(tester, 'Supercalifragilisticexpialidocious' * 3);
  });

  testWidgets('empty text and a zero-height box are fine', (tester) async {
    await fit(tester, '');
    await fit(tester, long, box: const Size(300, 0));
  });

  testWidgets('cost: 300 live transcript updates rebuild quickly', (
    tester,
  ) async {
    final text = ValueNotifier('');
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 322,
            height: 90,
            child: ValueListenableBuilder(
              valueListenable: text,
              builder: (_, t, _) =>
                  FitText(t, style: (s) => SusText.display(s)),
            ),
          ),
        ),
      ),
    );
    final words = long.split(' ');
    final sw = Stopwatch()..start();
    for (var i = 0; i < 300; i++) {
      text.value = words.take(1 + i % words.length).join(' ');
      await tester.pump();
    }
    final perFrameMs = sw.elapsedMicroseconds / 300 / 1000;
    // ignore: avoid_print
    print('FitText: ${perFrameMs.toStringAsFixed(2)} ms per update (debug)');
    expect(perFrameMs, lessThan(8), reason: 'half a 60 Hz frame, in debug');
  });

  testWidgets('measures with the ambient line height (the hint case)', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await fit(
      tester,
      "Christopher: just start answering when you're ready.",
      box: const Size(343, 36),
      overflow: FitOverflow.keepStart,
      sizes: const [15, 13, 12, 11],
      style: (s) => SusText.body(s, weight: FontWeight.w700),
    );
  });
}
