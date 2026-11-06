import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/theme/sparkline.dart';

import 'world.dart';

SparklinePainter painter(List<(int, double)> points, {double? baseline}) =>
    SparklinePainter(
      points: points,
      baseline: baseline,
      fromMs: 0,
      nowMs: 10000,
      minHalfRange: 12,
      minSpanMs: 15000,
      maxGapMs: 4000,
    );

/// Records the path segments the painter draws.
class _Canvas implements Canvas {
  final paths = <Path>[];
  final circles = <Offset>[];
  final lines = <(Offset, Offset)>[];

  @override
  void drawPath(Path path, Paint paint) => paths.add(path);
  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add(c);
  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lines.add((p1, p2));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('pulse sparkline scale', () {
    test('small wobbles around the normal stay small (fixed ±12 BPM)', () {
      final (center, half) = painter([
        (0, 69),
        (1000, 71),
        (2000, 70),
      ], baseline: 70).scale();
      expect(center, 70, reason: 'centred on the calibrated normal');
      expect(half, 12, reason: 'a 1 BPM wobble must not fill the height');
    });

    test('a big change still fits', () {
      final (center, half) = painter([
        (0, 70),
        (1000, 95),
      ], baseline: 70).scale();
      expect(center, 70);
      expect(half, greaterThanOrEqualTo(25));
    });

    test('without a baseline it centres on the readings', () {
      final (center, _) = painter([(0, 80), (1000, 90)]).scale();
      expect(center, 85);
    });

    test('a gap with no confident reading breaks the line', () {
      final canvas = _Canvas();
      painter([
        (0, 70),
        (1000, 72),
        (8000, 80), // 7 s gap: drawn as a new segment
        (9000, 81),
      ], baseline: 70).paint(canvas, const Size(100, 30));
      final metrics = canvas.paths.single.computeMetrics().toList();
      expect(metrics.length, 2);
      expect(canvas.circles.single.dx, closeTo(60, 0.01), reason: '9 of 15 s');
      expect(canvas.lines, isNotEmpty, reason: 'dashed normal line');
    });

    test('no readings yet: only the normal line, no crash', () {
      final canvas = _Canvas();
      painter(const [], baseline: 70).paint(canvas, const Size(100, 30));
      expect(canvas.paths, isEmpty);
      expect(canvas.circles, isEmpty);
      expect(canvas.lines, isNotEmpty);
    });
  });

  test('the controller collects this question\'s confident readings, on Ask '
      'too, and starts over for the next question', () {
    fakeAsync((async) {
      final w = World(async);
      w.startGame(['Sam', 'Alex']);
      w.calibrate();
      w.until(() => w.game.phase == GamePhase.ask);
      final start = w.game.questionStartMs;
      w.elapse(4000);
      expect(w.game.phase, GamePhase.ask);
      final asked = w.game.live.questionPulse;
      expect(asked.length, greaterThanOrEqualTo(3));
      expect(asked.every((p) => p.tMs >= start), isTrue);
      expect(w.game.live.questionBlinkRate, isNotNull, reason: 'Ask too');

      w.askAndAnswer();
      w.game.nextQuestion();
      w.elapse(100);
      w.until(() => w.game.phase == GamePhase.ask);
      final next = w.game.questionStartMs;
      expect(next, greaterThan(start));
      expect(w.game.live.questionPulse.every((p) => p.tMs >= next), isTrue);
      w.dispose();
    });
  });
}
