import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/app_scope.dart';
import 'package:susometer/debug/bridge_spike_screen.dart';
import 'package:susometer/main.dart';
import 'package:susometer/presage/presage_models.dart';
import 'package:susometer/screens/settings_screen.dart';
import 'package:susometer/voice/speech_service.dart';

import 'fakes.dart';

void main() {
  Future<(FakePresage, FakeSpeech)> pumpApp(
    WidgetTester tester, {
    String? key,
  }) async {
    final presage = FakePresage()..storedKey = key;
    final speech = FakeSpeech();
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SusApp(
        services: AppServices(
          presage: presage,
          speech: speech,
          device: FakeDevice(),
        ),
        home: const BridgeSpikeScreen(),
      ),
    );
    await tester.pump();
    return (presage, speech);
  }

  testWidgets('spike screen shows the disclaimer', (tester) async {
    await pumpApp(tester);
    expect(find.text('Bridge spike'), findsOneWidget);
    expect(
      find.text('For fun only. Measures stress reactions, not truth.'),
      findsOneWidget,
    );
  });

  testWidgets('starting without a key opens Settings instead', (tester) async {
    final (presage, _) = await pumpApp(tester);
    await tester.scrollUntilVisible(find.text('Start both'), 300);
    await tester.ensureVisible(find.text('Start both'));
    await tester.pump();
    await tester.tap(find.text('Start both'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(presage.calls, isNot(contains('start')));
  });

  testWidgets('live samples and transcript both show up', (tester) async {
    final (presage, speech) = await pumpApp(tester, key: 'k-1234');
    await tester.scrollUntilVisible(find.text('Start both'), 300);
    await tester.ensureVisible(find.text('Start both'));
    await tester.pump();
    await tester.tap(find.text('Start both'));
    await tester.pumpAndSettle();
    expect(
      presage.calls,
      containsAllInOrder(['configure(telemetry: false)', 'start']),
    );
    expect(speech.calls, contains('start'));

    presage.controller.add(
      PresageSample.fromMap({
        't': DateTime.now().millisecondsSinceEpoch,
        'status': 'running',
        'pulse': 78.4,
        'pulseConf': 0.9,
        'pulseAt': DateTime.now().millisecondsSinceEpoch,
        'validation': {'code': 'OK', 'hint': 'Looking good'},
        'events': [
          {'e': 'blinkEvent', 't': 1},
          {'e': 'blinkEvent', 't': 2},
        ],
      }),
    );
    speech.controller.add(
      const SpeechText(
        text: 'What did you have for breakfast?',
        segment: 1,
        isFinal: false,
        tMs: 1,
      ),
    );
    // One frame delivers the stream events, the next renders them.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('What did you have for breakfast?'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('78 BPM'), -300);
    expect(find.text('78 BPM'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Looking good'), 200);
    expect(find.text('78.4 BPM'), findsOneWidget);
    expect(find.text('Looking good'), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'two blinks counted');

    // Leave the screen cleanly (stops the clock timer).
    await tester.pumpWidget(const SizedBox());
  });
}
