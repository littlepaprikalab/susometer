import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the app's real fonts before every test file, so layout checks at
/// 390×844 measure text the way an iPhone does (the default test font draws
/// every glyph as a full square, which overstates widths).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Future<ByteData> bytes(String path) async =>
      ByteData.sublistView(Uint8List.fromList(await File(path).readAsBytes()));

  final bowlby = FontLoader('BowlbyOneSC')
    ..addFont(bytes('assets/fonts/BowlbyOneSC-Regular.ttf'));
  final work = FontLoader('WorkSans')
    ..addFont(bytes('assets/fonts/WorkSans-Medium.ttf'))
    ..addFont(bytes('assets/fonts/WorkSans-SemiBold.ttf'))
    ..addFont(bytes('assets/fonts/WorkSans-Bold.ttf'));
  await Future.wait([bowlby.load(), work.load()]);
  await testMain();
}
