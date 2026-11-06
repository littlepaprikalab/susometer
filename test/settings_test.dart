import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/app_scope.dart';
import 'package:susometer/main.dart';
import 'package:susometer/presage/presage_models.dart';
import 'package:susometer/screens/settings_screen.dart';
import 'package:susometer/settings/app_settings.dart';

import 'fakes.dart';

void main() {
  group('ApiKeyController', () {
    test('no key, then save, then connected', () async {
      final api = FakePresage();
      final keys = ApiKeyController(api);
      await keys.refresh();
      expect(keys.state, ApiKeyState.none);
      expect(keys.hasKey, isFalse);

      expect(await keys.save('  abcd-1234-wxyz  '), isTrue);
      expect(api.storedKey, 'abcd-1234-wxyz', reason: 'trimmed before save');
      expect(keys.state, ApiKeyState.saved);
      expect(keys.hint, '••••wxyz');

      final result = await keys.test(telemetry: false);
      expect(result.ok, isTrue);
      expect(keys.state, ApiKeyState.connected);
      expect(api.calls, contains('testConnection(telemetry: false)'));
    });

    test(
      'auth errors mean rejected; network errors keep the key saved',
      () async {
        final api = FakePresage()..storedKey = 'k-1234';
        final keys = ApiKeyController(api);
        await keys.refresh();
        expect(keys.state, ApiKeyState.saved);

        api.nextTest = const ConnectionTestResult(
          ok: false,
          code: 'authenticationFailed',
          message: 'Invalid key',
        );
        await keys.test(telemetry: false);
        expect(keys.state, ApiKeyState.rejected);

        api.nextTest = const ConnectionTestResult(
          ok: false,
          code: 'networkError',
          message: 'Offline',
        );
        await keys.test(telemetry: false);
        expect(keys.state, ApiKeyState.saved);
        expect(keys.lastTest!.code, 'networkError');
      },
    );

    test('remove clears the key', () async {
      final api = FakePresage()..storedKey = 'k-1234';
      final keys = ApiKeyController(api);
      await keys.refresh();
      await keys.remove();
      expect(api.storedKey, isNull);
      expect(keys.state, ApiKeyState.none);
      expect(keys.hint, isNull);
    });

    test('empty key is not saved', () async {
      final api = FakePresage();
      final keys = ApiKeyController(api);
      expect(await keys.save('   '), isFalse);
      expect(api.calls, isNot(contains('setApiKey')));
    });
  });

  test('settings default to telemetry off and are in-memory only', () {
    final s = AppSettings();
    expect(s.telemetry, isFalse);
    expect(s.proofPanel, isFalse);
    expect(s.hostVoice, isTrue);
    expect(s.soundEffects, isTrue);
    expect(s.haptics, isTrue);
  });

  group('SettingsScreen', () {
    Future<(FakePresage, AppServices)> pumpSettings(
      WidgetTester tester, {
      String? key,
    }) async {
      final api = FakePresage()..storedKey = key;
      final services = AppServices(
        presage: api,
        speech: FakeSpeech(),
        device: FakeDevice(),
      );
      await services.apiKey.refresh();
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        SusApp(services: services, home: const SettingsScreen()),
      );
      await tester.pump();
      return (api, services);
    }

    testWidgets('shows No key yet, then Save & test saves and connects', (
      tester,
    ) async {
      final (api, _) = await pumpSettings(tester);
      expect(find.text('No key yet'), findsOneWidget);
      expect(find.text('Test connection'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('apiKeyField')),
        'secret-key-9f3e',
      );
      await tester.pump();
      expect(find.text('Save & test'), findsOneWidget);
      await tester.tap(find.text('Save & test'));
      await tester.pumpAndSettle();

      expect(api.storedKey, 'secret-key-9f3e');
      expect(
        api.calls,
        containsAllInOrder(['setApiKey', 'testConnection(telemetry: false)']),
      );
      // The field is cleared after saving; only the hint remains.
      expect(find.text('secret-key-9f3e'), findsNothing);
      expect(
        find.text('Saved ••••9f3e. Paste a new key to replace it.'),
        findsOneWidget,
      );
      expect(find.text('Connected'), findsOneWidget);
      expect(
        find.textContaining('Signed in to Presage in 2.3 s.'),
        findsOneWidget,
      );
    });

    testWidgets('shows the SDK error code when the key is rejected', (
      tester,
    ) async {
      final (api, _) = await pumpSettings(tester, key: 'bad-key-0000');
      api.nextTest = const ConnectionTestResult(
        ok: false,
        code: 'authenticationFailed',
        message: 'Invalid API key',
      );
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();
      expect(find.text('Key rejected'), findsOneWidget);
      expect(find.textContaining('authenticationFailed'), findsOneWidget);
    });

    testWidgets('remove asks first, then clears the key', (tester) async {
      final (api, _) = await pumpSettings(tester, key: 'k-0000');
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove the key?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(api.storedKey, isNull);
      expect(find.text('No key yet'), findsOneWidget);
    });

    testWidgets('telemetry toggle starts off and passes through to the test', (
      tester,
    ) async {
      final (api, services) = await pumpSettings(tester, key: 'k-0000');
      expect(services.settings.telemetry, isFalse);
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('testConnection(telemetry: false)'));
    });
  });
}
