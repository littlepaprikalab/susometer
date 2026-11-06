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
