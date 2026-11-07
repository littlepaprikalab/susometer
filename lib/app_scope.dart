import 'package:flutter/widgets.dart';

import 'audio/host_audio.dart';
import 'device/device_api.dart';
import 'game/game_controller.dart';
import 'game/scoring_config.dart';
import 'presage/presage_channel.dart';
import 'settings/app_settings.dart';
import 'voice/speech_service.dart';
import 'voice/turn_detector.dart';

/// App-wide services. Tests swap in fakes.
class AppServices {
  AppServices({
    required this.presage,
    required this.speech,
    DeviceApi? device,
    AppSettings? settings,
    HostAudio? host,
    HapticsApi? haptics,
    TurnConfig? turnConfig,
    ScoringConfig config = const ScoringConfig(),
    int Function()? now,
  }) : device = device ?? MethodChannelDevice(),
       settings = settings ?? AppSettings(),
       apiKey = ApiKeyController(presage) {
    game = GameController(
      presage: presage,
      speech: speech,
      device: this.device,
      settings: this.settings,
      apiKey: apiKey,
      host: host ?? const SilentHostAudio(),
      haptics: haptics ?? const SystemHaptics(),
      turnConfig: turnConfig ?? const TurnConfig(),
      config: config,
      now: now,
    );
  }

  final PresageApi presage;
  final SpeechApi speech;
  final DeviceApi device;
  final AppSettings settings;
  final ApiKeyController apiKey;
  late final GameController game;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this widget');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}

/// Gives screens the [GameController] and rebuilds them whenever it notifies.
class GameScope extends InheritedNotifier<GameController> {
  const GameScope({
    super.key,
    required GameController game,
    required super.child,
  }) : super(notifier: game);

  static GameController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<GameScope>();
    assert(scope != null, 'GameScope missing above this widget');
    return scope!.notifier!;
  }
}
