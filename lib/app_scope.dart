import 'package:flutter/widgets.dart';

import 'presage/presage_channel.dart';
import 'settings/app_settings.dart';
import 'voice/speech_service.dart';

/// App-wide services. Tests swap in fakes.
class AppServices {
  AppServices({
    required this.presage,
    required this.speech,
    AppSettings? settings,
  }) : settings = settings ?? AppSettings(),
       apiKey = ApiKeyController(presage);

  final PresageApi presage;
  final SpeechApi speech;
  final AppSettings settings;
  final ApiKeyController apiKey;
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
