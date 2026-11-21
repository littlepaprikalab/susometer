import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/theme/sparkline.dart';

import 'world.dart';

SparklinePainter painter(
  List<(int, double)> points, {
  double? baseline,
  (int, int)? highlight,
  bool endDot = true,
}) => SparklinePainter(
  points: points,
  baseline: baseline,
  fromMs: 0,
  nowMs: 10000,
  minHalfRange: 12,
  minSpanMs: 15000,
  maxGapMs: 4000,
  highlight: highlight,
  endDot: endDot,
);

/// Records the path segments the painter draws.
class _Canvas implements Canvas {
  final paths = <Path>[];
  final circles = <Offset>[];
  final lines = <(Offset, Offset)>[];
  final rrects = <RRect>[];
  final paragraphs = <(Offset, double)>[];

  @override
  void drawPath(Path path, Paint paint) => paths.add(path);
  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add(c);
  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lines.add((p1, p2));
  @override
  void drawRRect(RRect rrect, Paint paint) => rrects.add(rrect);
  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      paragraphs.add((offset, paragraph.maxIntrinsicWidth));
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

    test('Verdict style: the answer is shaded, lone readings get a dot', () {
      final canvas = _Canvas();
      painter(
        [(0, 70), (1000, 72), (9000, 85)],
        baseline: 70,
        highlight: (3000, 6000),
        endDot: false,
      ).paint(canvas, const Size(150, 30));
      final band = canvas.rrects.single;
      expect(band.left, closeTo(30, 0.01), reason: '3 of 15 s');
      expect(band.right, closeTo(60, 0.01));
      expect(
        canvas.circles.length,
        1,
        reason: 'the reading at 9 s has no neighbour within 4 s',
      );
    });

    test('no answer start heard: a rule at the Final answer, no band', () {
      final canvas = _Canvas();
      SparklinePainter(
        points: const [(0, 70), (1000, 72), (2000, 71)],
        baseline: 70,
        fromMs: 0,
        nowMs: 15000,
        minHalfRange: 12,
        minSpanMs: 0,
        maxGapMs: 4000,
        marker: 9000,
        endDot: false,
      ).paint(canvas, const Size(150, 30));
      expect(canvas.rrects, isEmpty);
      final rule = canvas.lines.where((l) => l.$1.dx == l.$2.dx).single;
      expect(rule.$1.dx, closeTo(90, 0.01), reason: '9 of 15 s');
      expect(rule.$1.dy, 0);
      expect(rule.$2.dy, 30, reason: 'full height');
    });

    group('delta scale (the Verdict)', () {
      SparklinePainter scaled(double? baseline) => SparklinePainter(
        points: const [(0, 70), (5000, 75), (10000, 72)],
        baseline: baseline,
        fromMs: 0,
        nowMs: 10000,
        minHalfRange: 12,
        minSpanMs: 0,
        maxGapMs: 4000,
        endDot: false,
        deltaLabels: const TextStyle(fontSize: 11),
      );

      test('round steps well inside the range', () {
        expect(SparklinePainter.deltaTick(12), 10, reason: 'the usual ±12');
        expect(SparklinePainter.deltaTick(14), 10);
        expect(SparklinePainter.deltaTick(25.3), 20, reason: '+22 BPM');
        expect(SparklinePainter.deltaTick(40), 30);
        expect(SparklinePainter.deltaTick(100), 80);
      });

      test('+10 and −10 at the right edge, with faint rules; the line stops '
          'short of them', () {
        final canvas = _Canvas();
        const size = Size(200, 56);
        scaled(70).paint(canvas, size);
        expect(canvas.paragraphs, hasLength(2));
        final (top, topW) = canvas.paragraphs[0];
        final (bottom, bottomW) = canvas.paragraphs[1];
        expect(top.dx + topW, closeTo(size.width, 0.5), reason: 'right edge');
        expect(bottom.dx + bottomW, closeTo(size.width, 0.5));
        expect(top.dy, lessThan(bottom.dy), reason: '+10 above −10');
        final labelsLeft = size.width - math.max(topW, bottomW);
        final plotRight = labelsLeft - SparklinePainter.labelGap;
        final rules = canvas.lines
            .where((l) => l.$1.dy == l.$2.dy && l.$1.dx == 0)
            .where((l) => l.$2.dx > 50)
            .toList();
        expect(rules, hasLength(2), reason: 'one rule at +10, one at −10');
        for (final r in rules) {
          expect(r.$2.dx, closeTo(plotRight, 0.5));
        }
        // ±10 sits 10/12 of the way from the normal to the edge.
        const inner = 56 / 2 - 3.5;
        expect(rules[0].$1.dy, closeTo(28 - inner * 10 / 12, 0.01));
        expect(rules[1].$1.dy, closeTo(28 + inner * 10 / 12, 0.01));
        final line = canvas.paths.single.getBounds();
        expect(line.right, closeTo(plotRight, 0.5), reason: 'now = plot end');
        final dashes = canvas.lines.where(
          (l) => l.$1.dy == l.$2.dy && l.$2.dx - l.$1.dx <= 4,
        );
        expect(
          dashes.map((l) => l.$2.dx).reduce(math.max),
          lessThanOrEqualTo(plotRight),
        );
      });

      test('no normal, no scale: a delta needs something to be from', () {
        final canvas = _Canvas();
        scaled(null).paint(canvas, const Size(200, 56));
        expect(canvas.paragraphs, isEmpty);
        expect(canvas.paths.single.getBounds().right, closeTo(200, 0.5));
      });

      test('off by default (Replay rows, the live card)', () {
        final canvas = _Canvas();
        painter([
          (0, 70),
          (10000, 72),
        ], baseline: 70).paint(canvas, const Size(200, 24));
        expect(canvas.paragraphs, isEmpty);
      });
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
      // Privacy: Wipe everything leaves no pulse readings anywhere.
      w.game.wipeAll();
      w.elapse(500);
      expect(w.game.live.questionPulse, isEmpty);
      expect(w.game.turns, isEmpty);
      expect(w.game.currentResult, isNull);
      expect(w.game.log.pulse, isEmpty);
      w.dispose();
    });
  });

  test(
    'a scored result keeps its pulse trace and window end for the charts',
    () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        final r = w.askAndAnswer(answerPulse: 88);
        final timing = r.timing!;
        expect(r.traceEndMs, timing.windowEnd(12000));
        expect(r.pulseTrace.length, greaterThan(5));
        expect(
          r.pulseTrace.every(
            (p) => p.$1 >= timing.tQ0 && p.$1 <= r.traceEndMs!,
          ),
          isTrue,
        );
        expect(r.pulseTrace.map((p) => p.$2), contains(88));
        w.dispose();
      });
    },
  );
}
