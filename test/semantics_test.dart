import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/app_scope.dart';
import 'package:susometer/main.dart';

import 'fakes.dart';

void main() {
  testWidgets('VoiceOver can activate the lobby controls', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final services = AppServices(
      presage: FakePresage(),
      speech: FakeSpeech(),
      device: FakeDevice(),
    );
    await tester.pumpWidget(SusApp(services: services));
    await tester.pump();

    for (final label in [
      'Settings',
      'Party',
      'Solo · host asks',
      '5',
      'Mild',
      'Start the show',
      'Add contestant',
    ]) {
      final node = tester.getSemantics(find.bySemanticsLabel(label).first);
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: '"$label" must be tappable with VoiceOver',
      );
    }

    // Double-tapping Solo in VoiceOver switches the mode.
    tester.semantics.tap(find.semantics.byLabel('Solo · host asks'));
    await tester.pump();
    expect(services.game.mode.name, 'solo');
    handle.dispose();
  });
}
