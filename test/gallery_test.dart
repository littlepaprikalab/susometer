// Renders every screen to PNG at 390×844 @2x for visual review against
// docs/design/mocks. Only runs when GALLERY_OUT is set:
//
//   GALLERY_OUT=docs/screens flutter test test/gallery_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/app_scope.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/main.dart';
import 'package:susometer/presage/presage_models.dart';
import 'package:susometer/screens/settings_screen.dart';
import 'package:susometer/voice/speech_service.dart';
import 'package:susometer/voice/turn_detector.dart';

import 'rig.dart';

final out = Platform.environment['GALLERY_OUT'];

Future<void> shot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.pump(const Duration(milliseconds: 50));
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$out/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('screen gallery', skip: out == null, (tester) async {
    final rig = Rig(tester);
    final key = GlobalKey();
    useRealPhone(tester, const Size(390, 844));
    rig.services = AppServices(
      presage: rig.presage,
      speech: rig.speech,
      device: rig.device,
      host: rig.host,
      turnConfig: const TurnConfig(),
    );
    rig.presage.begin();
    rig.presage.pulse = 84;
    rig.presage.expr = const {'happy': 0.7, 'neutral': 0.2, 'surprise': 0.05};
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: SusApp(services: rig.services),
      ),
    );
    await tester.pump();

    for (final n in ['Sam', 'Alex', 'Priya', 'Jordan']) {
      await rig.addPlayer(n);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await rig.wait(300);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, 600),
    );
    await rig.wait(300);
    await shot(tester, key, '01-lobby');

    rig.presage.storedKey = 'fake-gallery-key-1a2b';
    await rig.services.apiKey.refresh();
    await rig.services.apiKey.test(telemetry: false);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    await rig.wait(600);
    await shot(tester, key, '08-settings');
    nav.pop();
    await rig.wait(600);
    await tester.tap(find.byTooltip("How it's scored"));
    await rig.wait(600);
    await shot(tester, key, '09-score-guide');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1500));
    await rig.wait(300);
    await shot(tester, key, '09b-score-guide-tags');
    nav.pop();
    await rig.wait(600);

    await rig.tap('Start the show');
    await rig.wait(300);
    await shot(tester, key, 'E1-how-to-play');
    await rig.tap("Got it, let's play");
    await rig.wait(200);
    await shot(tester, key, '02-consent');
    await rig.tap('I agree, measure me');
    await rig.until(() => rig.game.currentWarmup != null);
    await rig.wait(400);
    rig.presage.talk(true);
    await rig.wait(400);
    await shot(tester, key, '03-calibrate');
    rig.presage.talk(false);
    rig.presage.code = 'EXCESSIVE_MOTION';
    await rig.wait(2000);
    await shot(tester, key, '03b-calibrate-bad-signal');
    rig.presage.code = 'OK';
    rig.presage.expr = const {'neutral': 0.8, 'happy': 0.1, 'surprise': 0.05};
    rig.autoTaps = false;
    await rig.until(() {
      final w = rig.game.currentWarmup;
      if (w != null && w.latencyS != null && !rig.presage.talking) {
        rig.game.nextWarmup();
      }
      return rig.game.calibStage == CalibStage.ready;
    }, what: 'the normal locked in');
    await rig.wait(700);
    await shot(tester, key, '03c-calibrate-ready');
    await rig.tap('Start the questions');
    rig.autoTaps = true;
    await rig.until(() => rig.game.phase == GamePhase.ask);
    rig.services.settings.proofPanel = true;
    await rig.wait(300);
    rig.speech.controller.add(
      SpeechText(
        text: 'Have you ever re-gifted a',
        segment: rig.speech.segment,
        isFinal: false,
        tMs: rig.presage.now,
      ),
    );
    await rig.wait(400);
    await shot(tester, key, '10-proof-panel');
    rig.services.settings.proofPanel = false;
    await rig.wait(200);
    await shot(tester, key, '04a-ask');

    rig.speech.controller.add(
      SpeechText(
        text: 'Have you ever re-gifted a present?',
        segment: rig.speech.segment,
        isFinal: true,
        tMs: rig.presage.now,
      ),
    );
    await rig.wait(300);
    await rig.tap('Done asking');
    await rig.wait(1200);
    rig.presage.talk(true);
    rig.presage.pulse = 95;
    rig.presage.expr = const {'surprise': 0.6, 'neutral': 0.3, 'fear': 0.05};
    await rig.wait(500);
    rig.speech.controller.add(
      SpeechText(
        text: 'No way. Okay… maybe once.',
        segment: rig.speech.segment,
        isFinal: false,
        tMs: rig.presage.now,
      ),
    );
    await rig.wait(3000);
    await shot(tester, key, '04b-answer');
    rig.presage.talk(false);
    await rig.wait(600);
    await rig.tap('Final answer');
    await rig.wait(3000);
    await shot(tester, key, '04c-settle');
    await rig.until(() => rig.game.phase == GamePhase.callIt);
    final voters = rig.game.voters;
    rig.game.castVote(voters[0].id, Vote.legit);
    rig.game.castVote(voters[1].id, Vote.sus);
    await rig.wait(200);
    await shot(tester, key, '04d-call-it');
    rig.game.reveal();
    await rig.wait(400);
    await shot(tester, key, '04e-countdown');
    await rig.until(() => rig.game.phase == GamePhase.verdict);
    rig.presage.pulse = 84;
    await rig.wait(300);
    await shot(tester, key, '05-verdict');

    await rig.tap('Next question');
    await rig.wait(300);
    rig.game.doneAsking();
    rig.presage.code = 'TOO_DARK';
    await rig.wait(2500);
    await shot(tester, key, 'E3-bad-signal');
    await rig.tap('Final answer');
    await rig.until(() => rig.game.phase == GamePhase.redo);
    await shot(tester, key, 'E4-redo');
    rig.presage.code = 'OK';
    await rig.tap('Ask it again');
    await rig.wait(300);
    await waitOutTapGuard(tester);
    await tester.tap(find.bySemanticsLabel('Pause the game'));
    await rig.wait(300);
    await shot(tester, key, 'pause');
    await rig.tap('End the show');
    await rig.wait(300);
    await shot(tester, key, 'E6-end-show');
    await rig.tap('End and see scores');
    await rig.wait(800);
    await shot(tester, key, '06-leaderboard');
    await rig.tap('Watch the replay');
    await rig.wait(300);
    await shot(tester, key, '07-replay');

    // Only Sam played before the show ended, so that shot is the one-player
    // name line. Give two more contestants Sam's answers for the tab row.
    for (final t in rig.game.turns.skip(1).take(2)) {
      t.results.addAll(rig.game.turns.first.results);
    }
    rig.game.backToLeaderboard();
    rig.game.openReplay();
    await rig.wait(300);
    await shot(tester, key, '07b-replay-tabs');

    // E2, E5 and solo mode.
    await rig.tap('Play again');
    await rig.wait(300);
    rig.speech.permissions = const SpeechPermissions(
      mic: 'denied',
      speech: 'authorized',
      onDevice: true,
    );
    await rig.tap('Start the show');
    await rig.wait(300);
    await shot(tester, key, 'E2-permissions');
    await rig.tap('Play without voice');
    await rig.wait(300);
    rig.presage.startError = const PresageException(
      'authenticationFailed',
      'Invalid API key',
    );
    await rig.tap('I agree, measure me');
    await rig.wait(300);
    await shot(tester, key, 'E5-sdk-offline');
    await rig.tap('Back to lobby');
    await rig.wait(300);
    rig.presage.startError = null;
    rig.speech.permissions = const SpeechPermissions(
      mic: 'granted',
      speech: 'authorized',
      onDevice: true,
    );
    await rig.tap('Solo · host asks');
    rig.host.say('x');
    rig.services.settings.hostVoice = false;
    await rig.tap('Start the show');
    await rig.wait(300);
    await rig.tap('I agree, measure me');
    await rig.until(() => rig.game.phase == GamePhase.ask);
    await rig.wait(300);
    await shot(tester, key, '04a-solo');

    await rig.finish();
  });
}
