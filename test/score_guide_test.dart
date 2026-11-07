import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/app_scope.dart';
import 'package:susometer/game/expression_tag.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/game/scoring_config.dart';
import 'package:susometer/main.dart';
import 'package:susometer/screens/score_guide_screen.dart';
import 'package:susometer/screens/settings_screen.dart';
import 'package:susometer/theme/expression_stamp.dart';

import 'fakes.dart';

/// A device whose camera check waits for [gate], so a test can act while
/// *Start the show* is still starting.
class _SlowDevice extends FakeDevice {
  Completer<String>? gate;

  @override
  Future<String> cameraPermission() => gate?.future ?? super.cameraPermission();
}

void main() {
  void phone(WidgetTester tester, {Size size = const Size(390, 844)}) {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  AppServices services() => AppServices(
    presage: FakePresage(),
    speech: FakeSpeech(),
    device: FakeDevice(),
  );

  /// The guide in an app whose game scores with [config].
  Future<GameController> pumpGuide(
    WidgetTester tester,
    ScoringConfig config,
  ) async {
    final s = AppServices(
      presage: FakePresage(),
      speech: FakeSpeech(),
      device: FakeDevice(),
      config: config,
    );
    await tester.pumpWidget(
      SusApp(services: s, home: const ScoreGuideScreen()),
    );
    await tester.pump();
    return s.game;
  }

  /// The labels of the #tag stamps drawn in [stress] (red) or teal ink.
  List<String> stamps(WidgetTester tester, {required bool stress}) => [
    for (final s in tester.widgetList<ExpressionStamp>(
      find.byType(ExpressionStamp),
    ))
      if (s.stress == stress) s.label,
  ];

  testWidgets("the lobby's ? opens the guide, and back returns", (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(SusApp(services: services()));
    await tester.pump();

    await tester.tap(find.byTooltip("How it's scored"));
    await tester.pumpAndSettle();
    expect(find.text("How it's scored"), findsOneWidget);

    await tester.tap(find.byTooltip('Back to lobby'));
    await tester.pumpAndSettle();
    expect(find.text('Start the show'), findsOneWidget);
  });

  /// Tall enough that the list builds every card at once.
  const tall = Size(390, 3200);

  testWidgets('the default guide matches the scoring', (tester) async {
    phone(tester, size: tall);
    const c = ScoringConfig();
    await pumpGuide(tester, c);

    for (final pct in ['45%', '25%', '15%']) {
      expect(find.text(pct), findsWidgets, reason: pct);
    }
    expect(find.text('0–34'), findsOneWidget);
    expect(find.text('35–59'), findsOneWidget);
    expect(find.text('60–100'), findsOneWidget);
    expect(
      find.textContaining(
        'score = 100 × (0.45 pulse + 0.25 blinks + 0.15 expressions + '
        '0.15 pause)^0.8',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('more than 40% of a question'), findsOneWidget);
    expect(
      find.textContaining('chat through ${c.calibMaxWarmups} easy warm-ups'),
      findsOneWidget,
      reason: 'every warm-up slot is asked (decision 74), so no "3–3"',
    );
    expect(find.textContaining('The first extra second is free'), findsOne);
    expect(
      find.textContaining('0 to 100, curved so a small reaction still shows.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('running high or dipping just after the question'),
      findsOneWidget,
      reason: 'the early slowdown counts too (SPEC decision 63)',
    );
    expect(
      find.textContaining(
        "Surprise, fear, contempt or disgust going past your highest in the "
        "warm-ups. Angry, happy, neutral and sad don't count.",
      ),
      findsOneWidget,
    );

    // Red ink for exactly the expressions the score counts, teal for every
    // other tag the camera can show: the same split as the camera's stamp.
    expect(stamps(tester, stress: true), c.exprCategories);
    expect(find.textContaining('counts those four when'), findsOneWidget);
    expect(stamps(tester, stress: false), [
      for (final l in ExpressionTagger.labels)
        if (!c.exprCategories.contains(l)) l,
    ]);
  });

  testWidgets('every number on the guide comes from ScoringConfig', (
    tester,
  ) async {
    phone(tester, size: tall);
    await pumpGuide(
      tester,
      const ScoringConfig(
        wPulse: 0.5,
        wBlink: 0.2,
        wExpr: 0.2,
        wHesitation: 0.1,
        scoreExponent: 0.7,
        legitBelow: 30,
        susFrom: 70,
        minCleanFraction: 0.75,
        hesitationGraceS: 1.5,
        calibQuietMs: 15000,
        calibMinWarmups: 2,
        calibMaxWarmups: 4,
        exprCategories: ['fear', 'surprise'],
      ),
    );

    for (final pct in ['50%', '20%', '10%']) {
      expect(find.text(pct), findsWidgets, reason: pct);
    }
    expect(find.text('45%'), findsNothing);
    expect(find.text('0–29'), findsOneWidget);
    expect(find.text('30–69'), findsOneWidget);
    expect(find.text('70–100'), findsOneWidget);
    expect(
      find.textContaining(
        'score = 100 × (0.5 pulse + 0.2 blinks + 0.2 expressions + '
        '0.1 pause)^0.7',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('more than 25% of a question'), findsOneWidget);
    expect(
      find.textContaining('The first extra 1.5 seconds are free'),
      findsOneWidget,
    );
    expect(find.textContaining('about 15 seconds'), findsOneWidget);
    expect(find.textContaining('chat through 2–4 easy warm-ups'), findsOne);
    expect(find.textContaining('Fear or surprise going past'), findsOneWidget);
    expect(stamps(tester, stress: true), ['fear', 'surprise']);
    expect(stamps(tester, stress: false), hasLength(6));
    expect(find.textContaining('counts those two when'), findsOneWidget);
  });

  testWidgets('tap targets, labels and contrast', (tester) async {
    phone(tester);
    final handle = tester.ensureSemantics();
    await pumpGuide(tester, const ScoringConfig());
    final list = find.byType(Scrollable).first;
    // Check each screenful: the guideline only sees what's on screen.
    for (var i = 0; i < 4; i++) {
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await tester.drag(list, const Offset(0, -700));
      await tester.pumpAndSettle();
    }
    expect(find.text('House rule'), findsOneWidget, reason: 'scrolled to end');
    handle.dispose();
  });

  testWidgets('fits a small phone at the largest text size', (tester) async {
    phone(tester, size: const Size(320, 568));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final s = services();
    await tester.pumpWidget(
      SusApp(services: s, home: const ScoreGuideScreen()),
    );
    await tester.pump();
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 12; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pump();
    }
    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(find.text('House rule'), findsOneWidget);
  });

  testWidgets('a curve, or no free pause, still reads right', (tester) async {
    phone(tester, size: tall);
    await pumpGuide(
      tester,
      const ScoringConfig(scoreExponent: 1, hesitationGraceS: 0),
    );
    expect(find.textContaining('0 to 100.'), findsOneWidget);
    expect(find.textContaining('curved'), findsNothing);
    expect(find.textContaining('0.15 pause)'), findsOneWidget);
    expect(find.textContaining('pause)^'), findsNothing);
    expect(find.textContaining('free'), findsNothing);

    await pumpGuide(tester, const ScoringConfig(scoreExponent: 1.25));
    expect(
      find.textContaining('curved so it takes a big reaction to score high'),
      findsOneWidget,
    );
    expect(find.textContaining('pause)^1.25'), findsOneWidget);
  });

  group('seams', () {
    testWidgets('neither ? nor the gear opens over a show that is starting', (
      tester,
    ) async {
      phone(tester);
      final device = _SlowDevice();
      final s = AppServices(
        presage: FakePresage()..storedKey = 'k-1234',
        speech: FakeSpeech(),
        device: device,
      );
      await tester.pumpWidget(SusApp(services: s));
      await tester.pump();
      s.game.addPlayer('Sam');
      s.game.addPlayer('Alex');
      device.gate = Completer();
      await tester.tap(find.text('Start the show'));
      await tester.pump();
      expect(find.text('Warming up…'), findsOneWidget);

      await tester.tap(find.byTooltip("How it's scored"));
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(ScoreGuideScreen), findsNothing);
      expect(find.byType(SettingsScreen), findsNothing);

      // The show starts in view, with nothing over it.
      device.gate!.complete('granted');
      await tester.pumpAndSettle();
      expect(s.game.phase, GamePhase.howToPlay);
      expect(find.text('How to play'), findsOneWidget);
      expect(find.byType(ScoreGuideScreen), findsNothing);
    });

    testWidgets("the page doesn't rebuild when the game notifies", (
      tester,
    ) async {
      phone(tester);
      final game = await pumpGuide(tester, const ScoringConfig());
      final before = tester.widget(find.byType(ListView));
      game.setMode(GameMode.solo);
      await tester.pump();
      expect(game.mode, GameMode.solo, reason: 'the game did notify');
      expect(identical(before, tester.widget(find.byType(ListView))), isTrue);
    });

    testWidgets('a double tap on ? opens one page', (tester) async {
      phone(tester);
      await tester.pumpWidget(SusApp(services: services()));
      await tester.pump();
      final at = tester.getCenter(find.byTooltip("How it's scored"));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(find.byType(ScoreGuideScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Back to lobby'));
      await tester.pumpAndSettle();
      expect(find.byType(ScoreGuideScreen), findsNothing);
      expect(find.text('Start the show'), findsOneWidget);
    });

    testWidgets('leaving the app with the page open comes back to it', (
      tester,
    ) async {
      phone(tester);
      final presage = FakePresage();
      final s = AppServices(
        presage: presage,
        speech: FakeSpeech(),
        device: FakeDevice(),
      );
      await tester.pumpWidget(SusApp(services: s));
      await tester.pump();
      await tester.tap(find.byTooltip("How it's scored"));
      await tester.pumpAndSettle();
      // Flutter's order for a trip out and back (World.leaveApp).
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.pumpAndSettle();
      expect(s.game.phase, GamePhase.lobby);
      expect(s.game.showPauseSheet, isFalse);
      expect(find.byType(ScoreGuideScreen), findsOneWidget);
      expect(presage.calls, isNot(contains('start')), reason: 'no camera');
    });
  });
}
