import 'dart:async';
import 'dart:typed_data';

import 'package:susometer/audio/host_audio.dart';
import 'package:susometer/device/device_api.dart';

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

  /// Thrown by [start], like iOS refusing the mic to an app in the
  /// background.
  SpeechException? startError;

  /// How long the native start takes; [startError] is checked at the end.
  int startTakesMs = 0;

  @override
  Future<void> start({String? locale}) async {
    calls.add('start');
    if (startTakesMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: startTakesMs));
    }
    final error = startError;
    if (error != null) throw error;
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  int segment = 0;

  /// How long the native newSegment takes. Until it returns, the old
  /// segment is still the current one: its partials keep coming.
  int newSegmentTakesMs = 0;

  @override
  Future<int?> newSegment() async {
    calls.add('newSegment');
    if (newSegmentTakesMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: newSegmentTakesMs));
    }
    return ++segment;
  }
}

class FakeDevice implements DeviceApi {
  String camera = 'granted';
  String thermal = 'nominal';
  final List<String> calls = [];
  int shares = 0;

  @override
  Future<String> cameraPermission() async => camera;

  @override
  Future<bool> requestCameraPermission() async {
    calls.add('requestCamera');
    if (camera == 'undetermined') camera = 'granted';
    return camera == 'granted';
  }

  @override
  Future<void> openAppSettings() async => calls.add('openAppSettings');

  @override
  Future<void> openPortal() async => calls.add('openPortal');

  @override
  Future<void> setKeepAwake(bool on) async => calls.add('keepAwake($on)');

  @override
  Future<String> thermalState() async => thermal;

  @override
  Future<void> shareImage(Uint8List png, {String? text}) async => shares++;
}

/// Records host lines and sounds; completes immediately.
class FakeHostAudio implements HostAudio {
  final List<String> said = [];
  final List<Sfx> played = [];

  /// Every call in order: `say:<text>`, `stop`, `play:<name>`.
  final List<String> calls = [];

  /// When true, lines and sounds keep playing until [finishLine] or
  /// [finishSounds]; a stop ends every line, like the native bridge.
  bool hold = false;
  final Map<int, Completer<void>> _lines = {};
  final List<Completer<void>> _sounds = [];

  @override
  Future<void> say(String text) {
    said.add(text);
    calls.add('say:$text');
    if (!hold) return Future.value();
    final line = Completer<void>();
    _lines[said.length - 1] = line;
    return line.future;
  }

  @override
  Future<void> stopSpeaking() async {
    calls.add('stop');
    for (final line in _lines.values) {
      if (!line.isCompleted) line.complete();
    }
    _lines.clear();
  }

  @override
  Future<void> play(Sfx sfx) {
    played.add(sfx);
    calls.add('play:${sfx.name}');
    if (!hold) return Future.value();
    final sound = Completer<void>();
    _sounds.add(sound);
    return sound.future;
  }

  /// The line at [index] in [said] finishes, if it's still playing.
  void finishLine(int index) {
    final line = _lines.remove(index);
    if (line != null && !line.isCompleted) line.complete();
  }

  void finishSounds() {
    for (final sound in _sounds) {
      if (!sound.isCompleted) sound.complete();
    }
    _sounds.clear();
  }
}

class FakeHaptics implements HapticsApi {
  final List<HapticCue> cues = [];

  @override
  Future<void> cue(HapticCue cue) async => cues.add(cue);
}
