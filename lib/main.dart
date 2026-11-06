import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const SusApp());
}

class SusApp extends StatelessWidget {
  const SusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sus-o-meter',
      debugShowCheckedModeBanner: false,
      theme: buildSusTheme(),
      home: const _Placeholder(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sus-o-meter', style: SusText.display(40)),
            const SizedBox(height: 12),
            Text(
              'For fun only. Measures stress reactions, not truth.',
              style: SusText.body(15, weight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
