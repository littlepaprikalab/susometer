import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the app's real fonts (and Material icons, when the Flutter SDK has
/// them cached) before every test file, so layout checks at 390×844 measure
/// text the way an iPhone does. The default test font draws every glyph as a
/// full square, which overstates widths.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadAppFonts();
  await testMain();
}

Future<void> loadAppFonts() async {
  Future<ByteData> bytes(String path) async =>
      ByteData.sublistView(Uint8List.fromList(await File(path).readAsBytes()));

  final bowlby = FontLoader('BowlbyOneSC')
    ..addFont(bytes('assets/fonts/BowlbyOneSC-Regular.ttf'));
  final work = FontLoader('WorkSans')
    ..addFont(bytes('assets/fonts/WorkSans-Medium.ttf'))
    ..addFont(bytes('assets/fonts/WorkSans-SemiBold.ttf'))
    ..addFont(bytes('assets/fonts/WorkSans-Bold.ttf'));
  final loads = [bowlby.load(), work.load()];

  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    loads.add((FontLoader('MaterialIcons')..addFont(bytes(icons.path))).load());
  }
  await Future.wait(loads);
}
