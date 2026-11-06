import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'audio/host_audio.dart';
import 'game/decks.dart';
import 'game_root.dart';
import 'presage/presage_channel.dart';
import 'theme/tokens.dart';
import 'voice/speech_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final services = AppServices(
    presage: MethodChannelPresage(),
    speech: MethodChannelSpeech(),
    host: MethodChannelHostAudio(),
  );
  try {
    services.game.setDecks(await DeckLibrary.load(rootBundle));
  } catch (_) {
    // Fall back to the small built-in decks.
  }
  runApp(SusApp(services: services));
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
      child: GameScope(
        game: services.game,
        child: MaterialApp(
          title: 'Sus-o-meter',
          debugShowCheckedModeBanner: false,
          theme: buildSusTheme(),
          // Large accessibility text still scales up, but is capped so the
          // fixed 390x844 game-show layouts don't break.
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3),
              ),
              child: child!,
            );
          },
          home: home ?? const GameRoot(),
        ),
      ),
    );
  }
}
