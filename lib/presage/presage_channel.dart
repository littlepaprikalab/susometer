import 'package:flutter/services.dart';

import 'presage_models.dart';

/// Dart side of the SmartSpectra bridge (SPEC.md §6).
///
/// The API key goes to Swift once, on save, and is stored in the Keychain.
/// It never comes back to Dart; [apiKeyHint] returns only the last 4 characters.
abstract class PresageApi {
  /// Snapshots from `sus/presage/stream` (about 10 Hz while measuring).
  Stream<PresageSample> get samples;

  Future<void> configure({required bool telemetry});
  Future<void> setApiKey(String key);
  Future<bool> hasApiKey();
  Future<String?> apiKeyHint();
  Future<void> clearApiKey();
  Future<ConnectionTestResult> testConnection({required bool telemetry});
  Future<void> start();
  Future<void> stop();
  Future<void> reset();
  Future<Map<String, Object?>> sdkInfo();

  /// Keeps the screen from auto-locking during a game (SPEC.md §9).
  Future<void> setKeepAwake(bool on);
}

class MethodChannelPresage implements PresageApi {
  MethodChannelPresage({
    MethodChannel method = const MethodChannel('sus/presage'),
    EventChannel events = const EventChannel('sus/presage/stream'),
  }) : _method = method,
       _events = events;

  final MethodChannel _method;
  final EventChannel _events;

  // One shared broadcast stream, so several listeners use one native sink.
  late final Stream<PresageSample> _samples = _events
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .map((e) => PresageSample.fromMap(e as Map<Object?, Object?>));

  @override
  Stream<PresageSample> get samples => _samples;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _method.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw PresageException(e.code, e.message ?? e.code);
    } on MissingPluginException {
      throw const PresageException(
        'UNAVAILABLE',
        'The Presage bridge is only available on iPhone.',
      );
    }
  }

  @override
  Future<void> configure({required bool telemetry}) =>
      _call<void>('configure', {'telemetry': telemetry});

  @override
  Future<void> setApiKey(String key) => _call<void>('setApiKey', {'key': key});

  @override
  Future<bool> hasApiKey() async => await _call<bool>('hasApiKey') ?? false;

  @override
  Future<String?> apiKeyHint() => _call<String>('apiKeyHint');

  @override
  Future<void> clearApiKey() => _call<void>('clearApiKey');

  @override
  Future<ConnectionTestResult> testConnection({required bool telemetry}) async {
    final raw = await _call<Map<Object?, Object?>>('testConnection', {
      'telemetry': telemetry,
    });
    if (raw == null) {
      return const ConnectionTestResult(
        ok: false,
        code: 'UNKNOWN',
        message: 'No answer from the bridge.',
      );
    }
    return ConnectionTestResult.fromMap(raw);
  }

  @override
  Future<void> start() => _call<void>('start');

  @override
  Future<void> stop() => _call<void>('stop');

  @override
  Future<void> reset() => _call<void>('reset');

  @override
  Future<void> setKeepAwake(bool on) => _call<void>('setKeepAwake', {'on': on});

  @override
  Future<Map<String, Object?>> sdkInfo() async {
    final raw = await _call<Map<Object?, Object?>>('sdkInfo');
    return {
      if (raw != null)
        for (final e in raw.entries) e.key.toString(): e.value,
    };
  }
}
