import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'debug/bridge_spike_screen.dart';
import 'presage/presage_channel.dart';
import 'theme/tokens.dart';
import 'voice/speech_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(
    SusApp(
      services: AppServices(
        presage: MethodChannelPresage(),
        speech: MethodChannelSpeech(),
      ),
    ),
  );
}

class SusApp extends StatelessWidget {
  const SusApp({super.key, required this.services, this.home});

  final AppServices services;

  /// Overrides the first screen (tests).
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        title: 'Sus-o-meter',
        debugShowCheckedModeBanner: false,
        theme: buildSusTheme(),
        // Milestone 1: the bridge spike is the home screen. The Lobby
        // replaces it in milestone 2.
        home: home ?? const BridgeSpikeScreen(),
      ),
    );
  }
}
