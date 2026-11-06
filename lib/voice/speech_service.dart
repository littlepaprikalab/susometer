import 'package:flutter/services.dart';

/// On-device speech recognition through the native bridge (SPEC.md §7, §8).
///
/// Recognition runs with `requiresOnDeviceRecognition = true`. If on-device
/// recognition isn't available, `start` fails with ON_DEVICE_UNAVAILABLE
/// rather than falling back to Apple's servers.
abstract class SpeechApi {
  Stream<SpeechEvent> get events;
  Future<SpeechPermissions> permissionStatus();
  Future<SpeechPermissions> requestPermissions();
  Future<void> start({String? locale});
  Future<void> stop();

  /// Half-duplex: stop feeding audio while the host speaks (SPEC.md §7).
  Future<void> pause();
  Future<void> resume();

  /// Closes the current recognition segment (it still delivers its final
  /// text) and starts a new one. Returns the new segment's id, or null if
  /// not listening. Used to keep question text and answer text apart.
  Future<int?> newSegment();
}

class SpeechPermissions {
  const SpeechPermissions({
    required this.mic,
    required this.speech,
    required this.onDevice,
  });

  /// granted | denied | undetermined
  final String mic;

  /// authorized | denied | restricted | notDetermined
  final String speech;

  /// Whether on-device recognition is supported for the current language.
  final bool onDevice;

  bool get granted => mic == 'granted' && speech == 'authorized';
  bool get undetermined => mic == 'undetermined' || speech == 'notDetermined';

  factory SpeechPermissions.fromMap(Map<Object?, Object?> m) =>
      SpeechPermissions(
        mic: m['mic'] as String? ?? 'unknown',
        speech: m['speech'] as String? ?? 'unknown',
        onDevice: m['onDevice'] as bool? ?? false,
      );

  static const unknown = SpeechPermissions(
    mic: 'unknown',
    speech: 'unknown',
    onDevice: false,
  );
}

sealed class SpeechEvent {
  const SpeechEvent(this.tMs);

  final int tMs;

  static SpeechEvent? fromMap(Map<Object?, Object?> m) {
    final t =
        (m['t'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    switch (m['type']) {
      case 'partial':
      case 'final':
        final text = m['text'] as String?;
        final seg = (m['seg'] as num?)?.toInt();
        if (text == null || seg == null) return null;
        return SpeechText(
          text: text,
          segment: seg,
          isFinal: m['type'] == 'final',
          tMs: t,
        );
      case 'level':
        return SpeechLevel((m['level'] as num?)?.toDouble() ?? 0, t);
      case 'state':
        return SpeechStateChange(m['state'] as String? ?? 'unknown', t);
      case 'error':
        return SpeechError(
          m['code'] as String? ?? 'UNKNOWN',
          m['message'] as String? ?? '',
          t,
        );
    }
    return null;
  }
}

/// Partial or final text for one recognition segment. Partial results for a
/// segment replace each other; a new segment starts after silence or a pause.
class SpeechText extends SpeechEvent {
  const SpeechText({
    required this.text,
    required this.segment,
    required this.isFinal,
    required int tMs,
  }) : super(tMs);

  final String text;
  final int segment;
  final bool isFinal;
}

/// Mic level 0..1 (peak over the last ~100 ms).
class SpeechLevel extends SpeechEvent {
  const SpeechLevel(this.level, int tMs) : super(tMs);

  final double level;
}

/// listening | paused | stopped | interrupted
class SpeechStateChange extends SpeechEvent {
  const SpeechStateChange(this.state, int tMs) : super(tMs);

  final String state;
}

class SpeechError extends SpeechEvent {
  const SpeechError(this.code, this.message, int tMs) : super(tMs);

  final String code;
  final String message;
}

/// Thrown when a speech bridge call fails, e.g. MIC_DENIED.
class SpeechException implements Exception {
  const SpeechException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'SpeechException($code): $message';
}

class MethodChannelSpeech implements SpeechApi {
  MethodChannelSpeech({
    MethodChannel method = const MethodChannel('sus/speech'),
    EventChannel events = const EventChannel('sus/speech/stream'),
  }) : _method = method,
       _events = events;

  final MethodChannel _method;
  final EventChannel _events;

  late final Stream<SpeechEvent> _stream = _events
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .map((e) => SpeechEvent.fromMap(e as Map<Object?, Object?>))
      .where((e) => e != null)
      .cast<SpeechEvent>();

  @override
  Stream<SpeechEvent> get events => _stream;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _method.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw SpeechException(e.code, e.message ?? e.code);
    } on MissingPluginException {
      throw const SpeechException(
        'UNAVAILABLE',
        'Speech recognition is only available on iPhone.',
      );
    }
  }

  @override
  Future<SpeechPermissions> permissionStatus() async {
    final raw = await _call<Map<Object?, Object?>>('permissionStatus');
    return raw == null
        ? SpeechPermissions.unknown
        : SpeechPermissions.fromMap(raw);
  }

  @override
  Future<SpeechPermissions> requestPermissions() async {
    final raw = await _call<Map<Object?, Object?>>('requestPermissions');
    return raw == null
        ? SpeechPermissions.unknown
        : SpeechPermissions.fromMap(raw);
  }

  @override
  Future<void> start({String? locale}) =>
      _call<void>('start', {'locale': ?locale});

  @override
  Future<void> stop() => _call<void>('stop');

  @override
  Future<void> pause() => _call<void>('pause');

  @override
  Future<void> resume() => _call<void>('resume');

  @override
  Future<int?> newSegment() => _call<int>('newSegment');
}

/// Builds a running transcript from segment-based partial/final results.
/// In memory only (SPEC.md §8).
class TranscriptBuffer {
  final Map<int, String> _segments = {};
  int? _lastSegment;
  int? lastUpdateMs;

  void add(SpeechText event) {
    final text = event.text.trim();
    if (text.isEmpty) return;
    _segments[event.segment] = text;
    _lastSegment = event.segment;
    lastUpdateMs = event.tMs;
  }

  String get text {
    final keys = _segments.keys.toList()..sort();
    return keys.map((k) => _segments[k]!).join(' ');
  }

  /// Text of the most recent segment only.
  String get latestSegment =>
      _lastSegment == null ? '' : (_segments[_lastSegment] ?? '');

  bool get isEmpty => _segments.isEmpty;

  void clear() {
    _segments.clear();
    _lastSegment = null;
    lastUpdateMs = null;
  }
}
