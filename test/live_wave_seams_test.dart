import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/theme/game_widgets.dart';
import 'package:susometer/voice/speech_service.dart';

import 'rig.dart';

// The live waveform on Calibrate through the real screens and the seams it
// meets (SPEC.md decisions 88 and 89). The fake SDK's clock carries on from
// one camera session to the next, so a session that isn't cleared would join
// straight onto the last one's line.

extension on Rig {
  Future<void> startParty(List<String> names) async {
    presage.storedKey = 'k';
    for (final n in names) {
      await addPlayer(n);
    }
    await tap('Start the show');
    await wait(300);
    if (game.phase == GamePhase.howToPlay) await tap("Got it, let's play");
  }

  /// Consent → calibrating with the waveform drawn.
  Future<void> toCalibration() async {
    await tap('I agree, measure me');
    await until(
      () =>
          game.phase == GamePhase.calibrate &&
          find.byType(Waveform).evaluate().isNotEmpty &&
          game.live.wave.points.length > 1,
      what: 'the waveform',
    );
  }
}

/// The line on the card now, in pieces, and the chart's width.
(List<List<Offset>>, double) line(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(Waveform),
      matching: find.byType(CustomPaint),
    ),
  );
  final size = tester.getSize(find.byType(Waveform));
  return ((paint.painter! as WaveformLinePainter).segments(size), size.width);
}

/// Peaks above the middle of the chart: one per beat.
int peaks(List<Offset> line, double height) => [
  for (var i = 1; i < line.length - 1; i++)
    if (line[i].dx >= 0 &&
        line[i].dy < height / 2 &&
        line[i].dy <= line[i - 1].dy &&
        line[i].dy < line[i + 1].dy)
      i,
].length;

void main() {
  testWidgets('cost: Calibrate with the waveform draws one frame per tick, '
      'at about the cost of Calibrate without one', (tester) async {
    Future<(int, double, double)> run({required bool wave}) async {
      final rig = Rig(tester);
      rig.presage.wave = wave;
      await rig.pumpApp();
      await rig.startParty(['Sam', 'Alex']);
      await rig.tap('I agree, measure me');
      await rig.until(
        () => rig.game.phase == GamePhase.calibrate,
        what: 'calibration',
      );
      await rig.wait(9000);
      final frames = await framesWhileTalking(rig);
      final a = await msPerTick(rig);
      final b = await msPerTick(rig);
      expect(rig.game.phase, GamePhase.calibrate);
      await rig.finish();
      return (frames, a, b);
    }

    await run(wave: true); // warm up
    final (_, plainA, plainB) = await run(wave: false);
    final (frames, waveA, waveB) = await run(wave: true);
    // ignore: avoid_print
    print(
      'Calibrate tick: ${plainA.toStringAsFixed(2)}, '
      '${plainB.toStringAsFixed(2)} ms without the waveform; '
      '${waveA.toStringAsFixed(2)}, ${waveB.toStringAsFixed(2)} ms with it; '
      '$frames frames in 2 s (debug)',
    );
    expect(frames, inInclusiveRange(16, 24), reason: '$frames frames in 2 s');
    final plain = plainA < plainB ? plainA : plainB;
    final withWave = waveA < waveB ? waveA : waveB;
    expect(withWave, lessThan(plain * 2 + 2), reason: '$withWave vs $plain');
  });

  testWidgets('Calibrate: the line draws itself from the left, then shows '
      'the last 8 s, about 9 beats at 65 BPM', (tester) async {
    final rig = Rig(tester);
    rig.presage.wave = true;
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex']);
    await rig.toCalibration();
    await rig.wait(3000);
    var (lines, w) = line(tester);
    expect(lines, hasLength(1));
    expect(lines.single.first.dx, 0, reason: 'starts at the left edge');
    expect(lines.single.last.dx, inInclusiveRange(w * 0.3, w * 0.55));

    await rig.wait(7000);
    (lines, w) = line(tester);
    expect(lines, hasLength(1));
    expect(lines.single.first.dx, lessThanOrEqualTo(0));
    expect(lines.single.last.dx, closeTo(w, 0.01), reason: 'newest at right');
    final h = tester.getSize(find.byType(Waveform)).height;
    expect(peaks(lines.single, h), inInclusiveRange(8, 9));
    expect(tester.takeException(), isNull);
    await rig.finish();
  });

  testWidgets('a camera problem hides the card; back, the line carries on', (
    tester,
  ) async {
    final rig = Rig(tester);
    rig.presage.wave = true;
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex']);
    await rig.toCalibration();
    await rig.wait(9000);
    rig.presage.code = 'TOO_DARK';
    await rig.wait(2500);
    expect(find.byType(Waveform), findsNothing, reason: 'the fix row shows');
    rig.presage.code = 'OK';
    await rig.wait(1500);
    final (lines, w) = line(tester);
    expect(lines, hasLength(1), reason: 'same camera session, no gap');
    expect(lines.single.first.dx, lessThanOrEqualTo(0));
    expect(lines.single.last.dx, closeTo(w, 0.01));
    await rig.finish();
  });

  testWidgets('Pause and Resume: the camera ran on, so does the line', (
    tester,
  ) async {
    final rig = Rig(tester);
    rig.presage.wave = true;
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex']);
    await rig.toCalibration();
    await rig.wait(9000);
    rig.game.pause();
    await rig.wait(1500);
    await rig.tap('Resume');
    await rig.wait(500);
    expect(rig.game.phase, GamePhase.calibrate);
    final (lines, w) = line(tester);
    expect(lines, hasLength(1));
    expect(lines.single.first.dx, lessThanOrEqualTo(0));
    expect(lines.single.last.dx, closeTo(w, 0.01));
    await rig.finish();
  });

  testWidgets('a trip out of the app: the new camera session starts its own '
      'line from the left', (tester) async {
    final rig = Rig(tester);
    rig.presage.wave = true;
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex']);
    await rig.toCalibration();
    await rig.wait(9000);
    await rig.leaveApp(3000);
    await rig.until(
      () =>
          rig.game.phase == GamePhase.calibrate &&
          find.byType(Waveform).evaluate().isNotEmpty &&
          rig.game.live.wave.points.length > 1,
      what: 'the waveform again',
    );
    await rig.wait(1000);
    final (lines, w) = line(tester);
    expect(lines, hasLength(1), reason: 'nothing kept from before the trip');
    expect(lines.single.first.dx, 0);
    expect(lines.single.last.dx, lessThan(w * 0.5));
    await rig.finish();
  });

  testWidgets('a lost signal restarts the camera in place: the new session '
      'starts its own line from the left', (tester) async {
    final rig = Rig(tester);
    rig.presage.wave = true;
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex']);
    await rig.toCalibration();
    await rig.wait(9000);
    // No snapshots for over 6 s: the controller restarts the SDK (its
    // clock carries on from where it stopped, as the fake's does).
    rig.presage.emitting = false;
    await rig.wait(7000);
    rig.presage.emitting = true;
    await rig.wait(1500);
    expect(rig.game.phase, GamePhase.calibrate, reason: 'same calibration');
    final (lines, w) = line(tester);
    expect(lines, hasLength(1));
    expect(lines.single.first.dx, 0, reason: 'not joined onto the old line');
    expect(lines.single.last.dx, lessThan(w * 0.5));
    await rig.finish();
  });

  testWidgets('the next contestant\'s line starts empty', (tester) async {
    final rig = Rig(tester);
    rig.presage.wave = true;
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex']);
    await rig.toCalibration();
    await rig.wait(9000);
    rig.game.pause();
    await rig.wait(500);
    await rig.tap('Skip my turn');
    await rig.wait(700);
    expect(find.text('Contestant 2 of 2'), findsOneWidget);
    expect(rig.game.live.wave.points, isEmpty, reason: 'camera stopped');
    await rig.toCalibration();
    await rig.wait(1000);
    final (lines, w) = line(tester);
    expect(lines, hasLength(1));
    expect(lines.single.first.dx, 0);
    expect(lines.single.last.dx, lessThan(w * 0.5));
    await rig.finish();
  });

  testWidgets('waveform missing for a second shows as a gap that scrolls '
      'off', (tester) async {
    final rig = Rig(tester);
    rig.presage.wave = true;
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex']);
    await rig.toCalibration();
    await rig.wait(9000);
    rig.presage.waveDropping = true;
    await rig.wait(1000);
    rig.presage.waveDropping = false;
    await rig.wait(2000);
    var (lines, w) = line(tester);
    expect(lines, hasLength(2));
    final gap = lines[1].first.dx - lines[0].last.dx;
    expect(gap, closeTo(w / 8, w / 40), reason: 'about 1 s of 8');
    await rig.wait(7000);
    (lines, w) = line(tester);
    expect(lines, hasLength(1), reason: 'the gap has scrolled off');
    await rig.finish();
  });
}

/// Frames drawn in [seconds] of 60 Hz vsyncs while someone talks: a new
/// mic level every 100 ms, out of step with the snapshots (as in
/// pathways_test). A vsync draws only if something asked for a frame.
Future<int> framesWhileTalking(Rig rig, {int seconds = 2}) async {
  final tester = rig.tester;
  var n = 0;
  final levels = Timer.periodic(const Duration(milliseconds: 100), (_) {
    n++;
    rig.speech.controller.add(
      SpeechLevel(0.2 + 0.1 * (n % 7), rig.presage.now),
    );
  });
  var frames = 0;
  for (var i = 0; i < seconds * 60; i++) {
    await tester.binding.delayed(const Duration(microseconds: 16667));
    if (tester.binding.hasScheduledFrame) {
      frames++;
      await tester.pump();
    }
  }
  levels.cancel();
  return frames;
}

/// Debug ms per 100 ms tick on Calibrate over 10 s, with the room talking.
Future<double> msPerTick(Rig rig) async {
  final sw = Stopwatch()..start();
  for (var i = 0; i < 100; i++) {
    rig.speech.controller.add(
      SpeechLevel(0.2 + 0.1 * (i % 7), rig.presage.now),
    );
    await rig.tester.pump(const Duration(milliseconds: 100));
  }
  return sw.elapsedMicroseconds / 100 / 1000;
}
