import 'dart:async';

import 'package:susometer/presage/presage_channel.dart';
import 'package:susometer/presage/presage_models.dart';
import 'package:susometer/voice/speech_service.dart';

/// In-memory stand-in for the Swift Presage bridge.
class FakePresage implements PresageApi {
  final StreamController<PresageSample> controller =
      StreamController<PresageSample>.broadcast();
  final List<String> calls = [];

  /// Mirrors the Keychain. Dart code under test never reads it back.
  String? storedKey;
  ConnectionTestResult nextTest = const ConnectionTestResult(
    ok: true,
    code: 'OK',
    message: 'Connected',
    elapsedMs: 2300,
  );
  PresageException? startError;

  @override
  Stream<PresageSample> get samples => controller.stream;

  @override
  Future<void> configure({required bool telemetry}) async {
    calls.add('configure(telemetry: $telemetry)');
    if (storedKey == null) throw const PresageException('NO_KEY', 'No key');
  }

  @override
  Future<void> setApiKey(String key) async {
    calls.add('setApiKey');
    storedKey = key;
  }

  @override
  Future<bool> hasApiKey() async => storedKey != null;

  @override
  Future<String?> apiKeyHint() async {
    final key = storedKey;
    if (key == null) return null;
    return '••••${key.substring(key.length < 4 ? 0 : key.length - 4)}';
  }

  @override
  Future<void> clearApiKey() async {
    calls.add('clearApiKey');
    storedKey = null;
  }

  @override
  Future<ConnectionTestResult> testConnection({required bool telemetry}) async {
    calls.add('testConnection(telemetry: $telemetry)');
    if (storedKey == null) {
      return const ConnectionTestResult(ok: false, code: 'NO_KEY', message: '');
    }
    return nextTest;
  }

  @override
  Future<void> start() async {
    calls.add('start');
    final error = startError;
    if (error != null) throw error;
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> reset() async => calls.add('reset');

  @override
  Future<void> setKeepAwake(bool on) async => calls.add('setKeepAwake($on)');

  @override
  Future<Map<String, Object?>> sdkInfo() async => {'version': 'fake'};
}

class FakeSpeech implements SpeechApi {
  final StreamController<SpeechEvent> controller =
      StreamController<SpeechEvent>.broadcast();
  final List<String> calls = [];
  SpeechPermissions permissions = const SpeechPermissions(
    mic: 'granted',
    speech: 'authorized',
    onDevice: true,
  );

  @override
  Stream<SpeechEvent> get events => controller.stream;

  @override
  Future<SpeechPermissions> permissionStatus() async => permissions;

  @override
  Future<SpeechPermissions> requestPermissions() async => permissions;

  @override
  Future<void> start({String? locale}) async => calls.add('start');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');
}
