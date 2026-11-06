import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/game/scoring.dart';
import 'package:susometer/game/scoring_config.dart';
import 'package:susometer/game/signal_log.dart';

import 'synthetic.dart';
import 'world.dart';

const cfg = ScoringConfig();
const scoring = Scoring(cfg);

/// The SDK reports a 12 s average, so the fake SDK pulse does too.
double Function(int t) sdkOf(double Function(double t) heart) => (t) {
  var sum = 0.0;
  var n = 0;
  for (var s = t - 12000; s <= t; s += 100) {
    sum += heart(s.toDouble());
    n++;
  }
  return sum / n;
};

/// 0–70 s of signal: a heart beating at [heart], and the SDK's pulse the
/// 12 s average of it unless [sdk] says otherwise.
SignalLog logOf(
  double Function(double t) heart, {
  double Function(int t)? sdk,
  bool wave = true,
}) {
  final log = SignalLog(config: cfg);
  for (final s in synth(
    start: 0,
    end: 70000,
    pulse: sdk ?? sdkOf(heart),
    wave: wave ? pulseWave(start: 0, end: 70000, bpm: heart) : const [],
  )) {
    log.add(s);
  }
  return log;
}

QuestionTiming timing({int tQ0 = 50000, int tQ1 = 53000}) => QuestionTiming(
  tQ0: tQ0,
  tQ1: tQ1,
  tA0: tQ1 + 1000,
  tA1: tQ1 + 5000,
  hesitationFromMs: tQ1,
);

PulseShape shapeOf(SignalLog log, QuestionTiming t) =>
    scoring.pulseShape(log, scoring.beats(log, 0, 70000), t)!;

PulseShape shape({
  double rise = 1,
  double sustained = 0.5,
  double? dip = 0.5,
  double coverage = 0.95,
  double? sdkDiffBpm = 1,
}) => PulseShape(
  preBpm: 70,
  meanBpm: 70 + sustained,
  rise: rise,
  sustained: sustained,
  dip: dip,
  coverage: coverage,
  sdkDiffBpm: sdkDiffBpm,
);

const base = Baseline(
  pulse: 70,
  blinkRatePerMin: 15,
  expr: {},
  latencyS: 1,
  confidentPulseMs: 20000,
  faceFraction: 1,
);

WindowFeatures featuresWith(PulseShape? s, {double meanPulse = 76}) =>
    WindowFeatures(
      meanPulse: meanPulse,
      blinkRatePerMin: 15,
      blinkFreeze: false,
      exprPeakDelta: 0,
      exprPeakCategory: null,
      hesitationS: 1,
      cleanFraction: 1,
      confidentPulseSamples: 15,
      pulseShape: s,
    );

void main() {
  group('pulse shape (SPEC.md decision 63)', () {
    test(
      'a jump while answering: level before, peak, and how long it held',
      () {
        // 70 until the answer starts at 54 s, 88 until 62 s, then 72.
        final log = logOf((t) => t < 54000 ? 70 : (t < 62000 ? 88 : 72));
        final s = shapeOf(log, timing());
        expect(s.preBpm, closeTo(70, 1));
        expect(s.rise, closeTo(18, 2));
        // Window 50–65 s: 4 s at 70, 8 s at 88, 3 s at 72 → mean 80.
        expect(s.sustained, closeTo(10, 1.5));
        expect(s.dip, lessThan(1));
        expect(s.coverage, greaterThan(0.9));
        expect(s.sdkDiffBpm, lessThan(3));
        expect(scoring.shapeProblem(s), isNull);
      },
    );

    test('an early slowdown after the question shows as a dip', () {
      // Steady 75, then 67 for 4 s right after the question ends.
      final log = logOf((t) => t > 53500 && t < 57500 ? 67 : 75);
      final s = shapeOf(log, timing());
      expect(s.dip, closeTo(7, 2));
      expect(s.rise, lessThan(2));
    });

    test('the level before the question is from just before it', () {
      // 60 until the question, then 80: a calibration-wide median would
      // hide this; the 5 s before the question doesn't.
      final log = logOf((t) => t < 50000 ? 60 : 80);
      final s = shapeOf(log, timing());
      expect(s.preBpm, closeTo(60, 1));
      expect(s.sustained, closeTo(20, 1.5));
    });

    test('no waveform, no shape, and the old pulse formula', () {
      final log = logOf((_) => 76, wave: false);
      final f = scoring.features(
        log,
        timing(),
        base,
        beats: scoring.beats(log, 0, 70000),
      );
      expect(f.pulseShape, isNull);
      final b = scoring.score(f, base, refs: [shape(), shape()]);
      expect(b.pulseMethod, PulseMethod.sdkMean);
      expect(b.pulseNote, 'no beats found');
      expect(b.zPulse, closeTo(6 / cfg.pulseScaleBpm, 0.02));
    });

    test('beats that disagree with the SDK are not trusted', () {
      final log = logOf((_) => 100, sdk: (_) => 70);
      final s = shapeOf(log, timing());
      expect(s.sdkDiffBpm, closeTo(30, 2));
      expect(scoring.shapeProblem(s), 'beats off the SDK by 30 BPM');
      final b = scoring.score(featuresWith(s), base, refs: [shape(), shape()]);
      expect(b.pulseMethod, PulseMethod.sdkMean);
    });

    test('too few beats in the window are not trusted', () {
      expect(scoring.shapeProblem(shape(coverage: 0.4)), 'beats cover 40%');
      expect(
        scoring.shapeProblem(shape(sdkDiffBpm: null)),
        'beats not checked against the SDK',
      );
      expect(scoring.shapeProblem(null), 'no beats found');
    });
  });

  group('question vs question (SPEC.md decision 63)', () {
    final refs = [
      shape(rise: 2, sustained: 1, dip: 1),
      shape(rise: 4, sustained: 2, dip: 0),
      shape(rise: 3, sustained: 0, dip: 2),
    ];

    test('an answer like the earlier ones scores nothing', () {
      final r = scoring.rankShape(shape(rise: 3, sustained: 1, dip: 1), refs)!;
      expect(r.rise, 0);
      expect(r.sustained, 0);
      expect(r.dip, 0);
      expect(r.zPulse, 0);
      expect(r.refs, 3);
    });

    test('an answer far above the earlier ones scores in full', () {
      final r = scoring.rankShape(
        shape(rise: 20, sustained: 12, dip: 10),
        refs,
      )!;
      expect(r.zPulse, 1);
    });

    test('each part is distance from the median in spreads', () {
      // rise: median 3, MAD 1 → spread max(1.48, 4) = 4; +5 BPM is 1.25
      // spreads, half of the 2.5 for full marks.
      final r = scoring.rankShape(shape(rise: 8, sustained: 1, dip: 1), refs)!;
      expect(r.rise, closeTo(0.5, 1e-9));
      expect(
        r.zPulse,
        closeTo(cfg.wShapeRise * 0.5, 1e-9),
        reason: 'weights sum to 1',
      );
    });

    test('alike earlier answers don\'t turn a wobble into a spike', () {
      final same = [for (var i = 0; i < 4; i++) shape(rise: 2)];
      final r = scoring.rankShape(shape(rise: 3), same)!;
      expect(r.rise, closeTo(1 / cfg.shapeRiseFloorBpm / cfg.shapeZFull, 1e-9));
    });

    test('a missing dip counts as none', () {
      final r = scoring.rankShape(shape(dip: null), refs)!;
      expect(r.dip, 0);
    });

    test('needs enough earlier answers with good beats', () {
      expect(scoring.rankShape(shape(), [shape()]), isNull);
      final b = scoring.score(
        featuresWith(shape(rise: 20)),
        base,
        refs: [shape(), shape(coverage: 0.3)],
      );
      expect(b.pulseMethod, PulseMethod.sdkMean);
      expect(b.pulseNote, 'only 1 earlier answer with beats');
      expect(b.zPulse, closeTo(6 / cfg.pulseScaleBpm, 1e-9));
    });

    test('good beats and enough references replace the SDK-mean pulse', () {
      final b = scoring.score(
        featuresWith(shape(rise: 20, sustained: 12, dip: 10), meanPulse: 70),
        base,
        refs: refs,
      );
      expect(b.pulseMethod, PulseMethod.beats);
      expect(b.pulseNote, isNull);
      expect(b.zPulse, 1, reason: 'not the SDK mean, which is +0');
      expect(b.shape!.refs, 3);
    });
  });

  group('in a game (SPEC.md decision 63)', () {
    test('warm-ups become references and a racing answer stands out', () {
      fakeAsync((async) {
        final w = World(async);
        var hot = 70.0;
        w.heart = (_) =>
            w.game.phase == GamePhase.answer || w.game.phase == GamePhase.settle
            ? hot
            : 70;
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        final turn = w.game.currentTurn;
        expect(turn.warmupTimings, hasLength(w.game.warmupsDone));
        for (final t in turn.warmupTimings) {
          expect(t.tQ1, greaterThanOrEqualTo(t.tQ0));
          expect(t.tA0, greaterThan(t.tQ1));
          expect(t.tA1, greaterThanOrEqualTo(t.tA0!));
        }

        final calm = w.askAndAnswer();
        final b1 = calm.breakdown!;
        expect(b1.pulseMethod, PulseMethod.beats, reason: '${b1.pulseNote}');
        expect(b1.shape!.refs, turn.warmupTimings.length);
        expect(b1.zPulse, lessThan(0.2));

        w.game.nextQuestion();
        hot = 90;
        final racing = w.askAndAnswer(question: 'Do you floss every day?');
        hot = 70;
        final b2 = racing.breakdown!;
        expect(b2.pulseMethod, PulseMethod.beats, reason: '${b2.pulseNote}');
        expect(b2.shape!.refs, turn.warmupTimings.length + 1);
        expect(racing.features!.pulseShape!.rise, closeTo(20, 3));
        expect(b2.zPulse, greaterThan(0.6));
        expect(racing.score!, greaterThan(calm.score!));
        w.dispose();
      });
    });

    test('no waveform from the bridge: scored as before', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        final r = w.askAndAnswer(answerPulse: 85);
        expect(r.features!.pulseShape, isNull);
        expect(r.breakdown!.pulseMethod, PulseMethod.sdkMean);
        expect(r.breakdown!.pulseNote, 'no beats found');
        w.dispose();
      });
    });
  });
}
