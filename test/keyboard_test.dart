import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/app_scope.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/main.dart';
import 'package:susometer/screens/settings_screen.dart';
import 'package:susometer/theme/widgets.dart';

import 'fakes.dart';
import 'rig.dart';

/// iPhone keyboards have no key to put them away, so the app has to
/// (SPEC.md decision 87). These run as iOS: on a phone, Flutter keeps the
/// keyboard up through a touch elsewhere unless the field says otherwise.
final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);

/// The keyboard is on screen.
bool keyboardUp(WidgetTester tester) => tester.testTextInput.isVisible;

/// The space an iPhone 14's keyboard takes, so the screen above it scrolls.
void showKeyboardInsets(WidgetTester tester) {
  tester.view.viewInsets = const FakeViewPadding(bottom: 336 * 3);
}

void main() {
  group('Lobby name box', () {
    final nameBox = find.byKey(const ValueKey('addContestant'));
    final plus = find.byWidgetPredicate(
      (w) => w is ChunkyButton && w.label == 'Add contestant',
    );
    const tagline = 'The party game that reads your pulse. Not your mind.';

    Future<Rig> openLobby(WidgetTester tester) async {
      final rig = Rig(tester);
      await rig.pumpApp();
      await tester.tap(nameBox);
      await tester.pump();
      expect(keyboardUp(tester), isTrue, reason: 'a tap on the box types');
      return rig;
    }

    List<String> names(Rig rig) => [for (final p in rig.game.players) p.name];

    testWidgets(
      'Return adds the name and keeps the keyboard up for the next one',
      (tester) async {
        final rig = await openLobby(tester);
        await tester.enterText(nameBox, 'Sam');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(names(rig), ['Sam']);
        expect(keyboardUp(tester), isTrue);
        await tester.enterText(nameBox, 'Alex');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(names(rig), ['Sam', 'Alex']);
        expect(keyboardUp(tester), isTrue);
        await rig.finish();
      },
      variant: iOS,
    );

    testWidgets('Return on an empty box puts the keyboard away', (
      tester,
    ) async {
      final rig = await openLobby(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(keyboardUp(tester), isFalse);
      expect(rig.game.players, isEmpty);
      await rig.finish();
    }, variant: iOS);

    testWidgets('+ adds the name and puts the keyboard away', (tester) async {
      final rig = await openLobby(tester);
      await tester.enterText(nameBox, 'Sam');
      await tester.tap(plus);
      await tester.pump();
      expect(names(rig), ['Sam']);
      expect(keyboardUp(tester), isFalse);
      await rig.finish();
    }, variant: iOS);

    testWidgets("+ from VoiceOver (not a touch) puts the keyboard away too", (
      tester,
    ) async {
      final rig = await openLobby(tester);
      await tester.enterText(nameBox, 'Sam');
      // A double-tap in VoiceOver calls the button with no touch on the
      // screen, so no "tap outside" closes the keyboard first.
      tester.widget<ChunkyButton>(plus).onPressed!();
      await tester.pump();
      expect(names(rig), ['Sam']);
      expect(keyboardUp(tester), isFalse);
      await rig.finish();
    }, variant: iOS);

    testWidgets('a touch anywhere else puts the keyboard away', (tester) async {
      final rig = await openLobby(tester);
      await tester.enterText(nameBox, 'Sa');
      await tester.tap(find.text(tagline));
      await tester.pump();
      expect(keyboardUp(tester), isFalse);
      // Only the keyboard goes: the half-typed name stays, nothing is added.
      expect(find.text('Sa'), findsOneWidget);
      expect(rig.game.players, isEmpty);
      await rig.finish();
    }, variant: iOS);

    testWidgets("a touch on another control closes it and still works", (
      tester,
    ) async {
      final rig = await openLobby(tester);
      await tester.tap(find.text('Solo · host asks'));
      await tester.pump();
      expect(keyboardUp(tester), isFalse);
      expect(rig.game.mode, GameMode.solo);
      await rig.finish();
    }, variant: iOS);

    testWidgets('scrolling the lobby puts the keyboard away', (tester) async {
      final rig = await openLobby(tester);
      showKeyboardInsets(tester);
      await tester.pumpAndSettle();
      // The drag starts on the box itself, so it isn't a touch elsewhere:
      // only the scroll can close the keyboard.
      await tester.drag(nameBox, const Offset(0, -120));
      await tester.pump();
      expect(keyboardUp(tester), isFalse);
      await rig.finish();
    }, variant: iOS);

    testWidgets('a tap in the box keeps the keyboard up', (tester) async {
      final rig = await openLobby(tester);
      await tester.enterText(nameBox, 'Sam');
      await tester.tap(nameBox);
      await tester.pump();
      expect(keyboardUp(tester), isTrue);
      await rig.finish();
    }, variant: iOS);

    testWidgets("after ? and Back the keyboard doesn't come back", (
      tester,
    ) async {
      final rig = await openLobby(tester);
      await tester.tap(find.byTooltip("How it's scored"));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back to lobby'));
      await tester.pumpAndSettle();
      expect(keyboardUp(tester), isFalse);
      await rig.finish();
    }, variant: iOS);
  });

  group('Settings key box', () {
    final keyBox = find.byKey(const ValueKey('apiKeyField'));

    /// First run: Settings opens with the key box focused.
    Future<void> openSettings(WidgetTester tester) async {
      useRealPhone(tester, const Size(390, 844));
      final services = AppServices(
        presage: FakePresage(),
        speech: FakeSpeech(),
        device: FakeDevice(),
      );
      await services.apiKey.refresh();
      await tester.pumpWidget(
        SusApp(
          services: services,
          home: const SettingsScreen(focusKeyField: true),
        ),
      );
      await tester.pump();
      expect(keyboardUp(tester), isTrue, reason: 'opens ready to paste');
    }

    testWidgets('a touch anywhere else puts the keyboard away', (tester) async {
      await openSettings(tester);
      await tester.tap(find.text('Presage API key'));
      await tester.pump();
      expect(keyboardUp(tester), isFalse);
    }, variant: iOS);

    testWidgets('Show and Hide leave the keyboard up', (tester) async {
      await openSettings(tester);
      await tester.enterText(keyBox, 'secret-key-9f3e');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.visibility_rounded));
      await tester.pump();
      expect(tester.widget<TextField>(keyBox).obscureText, isFalse);
      expect(keyboardUp(tester), isTrue);
      await tester.tap(find.byIcon(Icons.visibility_off_rounded));
      await tester.pump();
      expect(tester.widget<TextField>(keyBox).obscureText, isTrue);
      expect(keyboardUp(tester), isTrue);
    }, variant: iOS);

    testWidgets('scrolling Settings puts the keyboard away', (tester) async {
      await openSettings(tester);
      showKeyboardInsets(tester);
      await tester.pumpAndSettle();
      await tester.drag(keyBox, const Offset(0, -120));
      await tester.pump();
      expect(keyboardUp(tester), isFalse);
    }, variant: iOS);
  });
}
