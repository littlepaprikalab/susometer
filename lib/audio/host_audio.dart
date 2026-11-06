import 'dart:async';

import 'package:flutter/services.dart';

/// Sound effects (SPEC.md §12).
enum Sfx { jingle, drumroll, dingDing, wahWah, buzzer, applause }

/// The host's voice (text-to-speech) and sound effects. Both play through the
/// native audio session, which pauses speech recognition while they play so
/// transcripts never contain the host (half-duplex, SPEC.md §7).
abstract class HostAudio {
  /// Speaks [text]; completes when the host has finished.
  Future<void> say(String text);
  Future<void> stopSpeaking();

  /// Plays [sfx]; completes when it has finished.
  Future<void> play(Sfx sfx);
}

/// No audio at all (tests, and before the voice host existed).
class SilentHostAudio implements HostAudio {
  const SilentHostAudio();

  @override
  Future<void> say(String text) async {}

  @override
  Future<void> stopSpeaking() async {}

  @override
  Future<void> play(Sfx sfx) async {}
}

extension SfxFile on Sfx {
  /// File name under `assets/sfx/` (without `.wav`).
  String get fileName => switch (this) {
    Sfx.jingle => 'jingle',
    Sfx.drumroll => 'drumroll',
    Sfx.dingDing => 'ding_ding',
    Sfx.wahWah => 'wah_wah',
    Sfx.buzzer => 'buzzer',
    Sfx.applause => 'applause',
  };
}

/// Host voice and sounds through the native speech bridge (`sus/speech`),
/// which gates recognition while anything plays.
///
/// Every call has a timeout, so a lost native callback can never stall the
/// game; on timeout the voice is stopped and the call completes.
class MethodChannelHostAudio implements HostAudio {
  MethodChannelHostAudio({
    MethodChannel method = const MethodChannel('sus/speech'),
  }) : _method = method;

  final MethodChannel _method;

  /// Generous upper bound for speaking [text] (~2.5 words/s plus slack).
  static Duration speakTimeout(String text) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    return Duration(milliseconds: 2500 + words * 500);
  }

  Future<void> _call(
    String method,
    Map<String, Object?> args,
    Duration timeout,
  ) async {
    try {
      await _method.invokeMethod<void>(method, args).timeout(timeout);
    } on TimeoutException {
      if (method == 'speak') await stopSpeaking();
    } on PlatformException {
      // Audio is a nice-to-have.
    } on MissingPluginException {
      // Not on an iPhone (tests).
    }
  }

  @override
  Future<void> say(String text) =>
      _call('speak', {'text': text}, speakTimeout(text));

  @override
  Future<void> stopSpeaking() async {
    try {
      await _method.invokeMethod<void>('stopSpeaking');
    } on PlatformException {
      // Ignore.
    } on MissingPluginException {
      // Ignore.
    }
  }

  @override
  Future<void> play(Sfx sfx) =>
      _call('playSound', {'name': sfx.fileName}, const Duration(seconds: 6));
}

/// Haptic moments (SPEC.md §12). Never fired while measuring.
enum HapticCue { countdownTick, legit, hmm, sus, award }

abstract class HapticsApi {
  Future<void> cue(HapticCue cue);
}

class SystemHaptics implements HapticsApi {
  const SystemHaptics();

  @override
  Future<void> cue(HapticCue cue) async {
    switch (cue) {
      case HapticCue.countdownTick:
        await HapticFeedback.lightImpact();
      case HapticCue.legit:
        await HapticFeedback.lightImpact();
        await Future<void>.delayed(const Duration(milliseconds: 130));
        await HapticFeedback.lightImpact();
      case HapticCue.hmm:
        await HapticFeedback.mediumImpact();
      case HapticCue.sus:
        await HapticFeedback.heavyImpact();
      case HapticCue.award:
        await HapticFeedback.vibrate();
    }
  }
}
