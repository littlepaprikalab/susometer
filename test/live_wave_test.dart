import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/live_wave.dart';
import 'package:susometer/presage/presage_models.dart';
import 'package:susometer/theme/game_widgets.dart';

// The live waveform on Calibrate (SPEC.md decision 88): placed by time over
// a fixed window, broken at gaps, in a chart that takes all the card's room.

/// Samples every 1000/[hz] ms from [from] to [to] (SDK ms), value [v] of t.
List<TraceSample> samples(
  double from,
  double to,
  double hz, {
  double Function(double t)? v,
}) {
  final out = <TraceSample>[];
  final dt = 1000 / hz;
  for (var t = from; t <= to + 1e-9; t += dt) {
    out.add(TraceSample((t * 1000).round(), v?.call(t) ?? math.sin(t), 0.9));
  }
  return out;
}

/// Feeds [all] the way the bridge does: one batch per 100 ms.
LiveWave feed(List<TraceSample> all, {LiveWave? into}) {
  final wave = into ?? LiveWave();
  var batch = <TraceSample>[];
  int? batchEnd;
  for (final s in all) {
    batchEnd ??= s.tsUs + 100000;
    if (s.tsUs >= batchEnd) {
      wave.add(batch);
      batch = [];
      batchEnd = s.tsUs + 100000;
    }
    batch.add(s);
  }
  wave.add(batch);
  return wave;
}

WaveformLinePainter painter(List<(double, double)> points) =>
    WaveformLinePainter(points, Colors.red, windowMs: 8000, maxGapMs: 300);

const chart = Size(264, 30);

/// Records what the painter draws.
class _Canvas implements Canvas {
  final paths = <Path>[];
  final lines = <(Offset, Offset)>[];

  @override
  void drawPath(Path path, Paint paint) => paths.add(path);
  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lines.add((p1, p2));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('live wave buffer', () {
    test('keeps the last 8 s by SDK time, whatever the sample rate', () {
      for (final hz in [15.0, 30.0, 60.0]) {
        final wave = feed(samples(0, 20000, hz));
        final p = wave.points;
        expect(p.last.$1, closeTo(20000, 1000 / hz));
        expect(p.first.$1, lessThanOrEqualTo(p.last.$1 - 8000));
        expect(p[1].$1, greaterThan(p.last.$1 - 8000));
        expect(p.length, closeTo(8 * hz + 1, 2), reason: '$hz Hz');
      }
    });

    test('repeats are dropped and out-of-order batches are sorted', () {
      final wave = LiveWave();
      wave.add(samples(0, 1000, 30).reversed.toList());
      final n = wave.points.length;
      expect([
        for (final (t, _) in wave.points) t,
      ], orderedEquals([for (final (t, _) in wave.points) t]..sort()));
      wave.add(samples(500, 1000, 30));
      expect(wave.points.length, n, reason: 'all repeats');
    });

    test('the SDK clock going back (a restart) starts over', () {
      final wave = feed(samples(50000, 60000, 30));
      feed(samples(0, 2000, 30), into: wave);
      expect(wave.points.first.$1, 0);
      expect(wave.points.last.$1, closeTo(2000, 34));
    });

    test('odd timestamps never grow it past its cap', () {
      final wave = LiveWave();
      for (var b = 0; b < 50; b++) {
        wave.add([
          for (var i = 0; i < 300; i++)
            TraceSample(b * 300 + i, i.toDouble(), null), // 1 µs apart
        ]);
      }
      expect(wave.points.length, LiveWave.maxPoints);
      wave.clear();
      expect(wave.points, isEmpty);
    });
  });

  group('live waveform drawing', () {
    test('the chart is always 8 s wide, newest sample at the right edge', () {
      for (final hz in [20.0, 25.0, 50.0]) {
        final wave = feed(samples(0, 20000, hz));
        final lines = painter(wave.points).segments(chart);
        expect(lines, hasLength(1));
        final line = lines.single;
        expect(line.last.dx, closeTo(chart.width, 0.01));
        // 2 s before the newest sample sits 6/8 of the way across.
        final i = wave.points.indexWhere(
          (p) => (p.$1 - (wave.points.last.$1 - 2000)).abs() < 1e-6,
        );
        expect(line[i].dx, closeTo(chart.width * 6 / 8, 0.01), reason: '$hz');
      }
    });

    test('until 8 s have arrived, the line draws itself from the left', () {
      final wave = feed(samples(1000, 4000, 25));
      final line = painter(wave.points).segments(chart).single;
      expect(line.first.dx, 0);
      expect(line.last.dx, closeTo(chart.width * 3 / 8, 0.01));
    });

    test('a 65 BPM pulse shows about 9 beats, evenly spaced', () {
      // A clean systolic peak per beat, 30 Hz, for 20 s.
      double beat(double t) {
        final f = (t * 65 / 60000) % 1;
        return math.exp(-math.pow((f - 0.15) / 0.07, 2).toDouble());
      }

      final wave = feed(samples(0, 20000, 30, v: beat));
      final line = painter(wave.points).segments(chart).single;
      final peaks = <double>[
        for (var i = 1; i < line.length - 1; i++)
          if (line[i].dx >= 0 &&
              line[i].dy < chart.height / 2 &&
              line[i].dy <= line[i - 1].dy &&
              line[i].dy < line[i + 1].dy)
            line[i].dx,
      ];
      expect(peaks.length, inInclusiveRange(8, 9), reason: '8 s × 65/60');
      final perBeat = chart.width * (60000 / 65) / 8000;
      for (var i = 1; i < peaks.length; i++) {
        expect(peaks[i] - peaks[i - 1], closeTo(perBeat, 3));
      }
    });

    test('missing waveform breaks the line instead of joining it', () {
      final wave = feed([
        ...samples(0, 3000, 30),
        ...samples(4000, 7000, 30), // a 1 s gap
        ...samples(7600, 7600, 30), // a lone sample after a 0.6 s gap
      ]);
      final lines = painter(wave.points).segments(chart);
      expect(lines, hasLength(2), reason: 'the lone sample draws nothing');
      expect(lines[0].last.dx, lessThan(lines[1].first.dx - 25));
    });

    test('no waveform yet: a flat unlit line, no crash', () {
      for (final points in [
        <(double, double)>[],
        [(0.0, 1.0)],
      ]) {
        final canvas = _Canvas();
        painter(points).paint(canvas, chart);
        expect(canvas.paths, isEmpty);
        expect(canvas.lines, hasLength(1));
      }
    });
  });

  group('live card layout', () {
    Future<void> pumpCard(
      WidgetTester t, {
      required double width,
      String value = '65 BPM',
      double? delta,
      Widget? trailing,
    }) => t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: LiveStatCard(
                label: 'Pulse · live',
                value: value,
                delta: delta,
                trend: Waveform(
                  points: [
                    for (final s in samples(0, 8000, 30)) (s.tsUs / 1000, 1.0),
                  ],
                  windowMs: 8000,
                  maxGapMs: 300,
                ),
                trailing: trailing,
              ),
            ),
          ),
        ),
      ),
    );

    // Border 2.5 + padding 10 on each side.
    const edge = 12.5;

    testWidgets('the chart takes all the room the words leave', (t) async {
      for (final w in [300.0, 358.0, 400.0]) {
        await pumpCard(t, width: w);
        final card = t.getRect(find.byType(LiveStatCard));
        final wave = t.getRect(find.byType(Waveform));
        final words = math.max(
          t.getRect(find.text('Pulse · live')).width,
          t.getRect(find.text('65 BPM')).width,
        );
        expect(wave.left, closeTo(card.left + edge + words + 8, 0.5));
        expect(wave.right, closeTo(card.right - edge, 0.5), reason: '$w');
      }
    });

    testWidgets('with "Talking", the chart runs up to it', (t) async {
      await pumpCard(
        t,
        width: 358,
        trailing: const Text('Talking', style: TextStyle(fontSize: 11)),
      );
      final wave = t.getRect(find.byType(Waveform));
      final talking = t.getRect(find.text('Talking'));
      expect(wave.right + 6, closeTo(talking.left, 0.5));
      expect(
        talking.right,
        closeTo(t.getRect(find.byType(LiveStatCard)).right - edge, 0.5),
      );
    });

    testWidgets('with a change arrow, the chart runs up to it', (t) async {
      await pumpCard(t, width: 210, value: '72 BPM', delta: 7);
      final wave = t.getRect(find.byType(Waveform));
      final arrow = t.getRect(find.byType(Icon));
      expect(wave.right, closeTo(arrow.left, 0.5));
    });

    testWidgets('a long number shrinks instead of squeezing the chart', (
      t,
    ) async {
      await pumpCard(t, width: 300, value: '1234567890 BPM');
      final inside = 300 - 2 * edge;
      final value = t.getRect(find.text('1234567890 BPM'));
      final wave = t.getRect(find.byType(Waveform));
      expect(
        value.width,
        lessThanOrEqualTo(inside * LiveStatCard.textMaxShare + 0.5),
      );
      expect(wave.width, greaterThanOrEqualTo(inside * 0.55));
      expect(t.takeException(), isNull);
    });
  });
}
