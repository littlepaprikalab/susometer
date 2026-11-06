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
  exprPeak: {},
  latencyS: 1,
  confidentPulseMs: 20000,
  faceFraction: 1,
);

WindowFeatures featuresWith(PulseShape? s, {double meanPulse = 76}) =>
    WindowFeatures(
      meanPulse: meanPulse,
      windowMs: 15000,
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
      final b = scoring.score(f, base, warmups: [shape(), shape()]);
      expect(b.pulseMethod, PulseMethod.sdkMean);
      expect(b.pulseNote, 'no beats found');
      expect(b.zPulse, closeTo(6 / cfg.pulseScaleBpm, 0.02));
    });

    test('beats that disagree with the SDK are not trusted', () {
      final log = logOf((_) => 100, sdk: (_) => 70);
      final s = shapeOf(log, timing());
      expect(s.sdkDiffBpm, closeTo(30, 2));
      expect(scoring.shapeProblem(s), 'beats off the SDK by 30 BPM');
      final b = scoring.score(
        featuresWith(s),
        base,
        warmups: [shape(), shape()],
      );
      expect(b.pulseMethod, PulseMethod.sdkMean);
    });

    test('an SDK pulse that arrives a few seconds late still matches', () {
      // A big jump (+35 BPM) is where a late SDK reading differs most from
      // the beats' latest 12 s; it mustn't send the strongest reactions back
      // to the SDK-mean formula.
      double heart(double t) => t < 54000 ? 70 : (t < 66000 ? 105 : 75);
      for (final lagS in [0, 2, 4, 6]) {
        final log = logOf(heart, sdk: (t) => sdkOf(heart)(t - lagS * 1000));
        final s = shapeOf(log, timing());
        expect(s.sdkDiffBpm, lessThan(2), reason: 'SDK ${lagS}s late');
        expect(scoring.shapeProblem(s), isNull, reason: 'SDK ${lagS}s late');
      }
    });

    test('a steady offset from the SDK still fails, whatever the delay', () {
      final log = logOf((_) => 82, sdk: (_) => 70);
      final s = shapeOf(log, timing());
      expect(s.sdkDiffBpm, closeTo(12, 1.5));
      expect(scoring.shapeProblem(s), startsWith('beats off the SDK'));
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
      // rise: median 3, MAD 1 → spread max(1.48, 4) = 4; +7 BPM is 1.75
      // spreads: the first is free, so it's half way from 1 to 2.5.
      final r = scoring.rankShape(shape(rise: 10, sustained: 1, dip: 1), refs)!;
      expect(r.rise, closeTo(0.5, 1e-9));
      expect(
        r.zPulse,
        closeTo(cfg.wShapeRise * 0.5, 1e-9),
        reason: 'weights sum to 1',
      );
    });

    test('alike earlier answers don\'t turn a wobble into a spike', () {
      final same = [for (var i = 0; i < 4; i++) shape(rise: 2)];
      // +1 BPM is a quarter of the 4 BPM floor: inside the free spread.
      expect(scoring.rankShape(shape(rise: 3), same)!.rise, 0);
      // +6 BPM is 1.5 floors: a third of the way from 1 to 2.5.
      expect(
        scoring.rankShape(shape(rise: 8), same)!.rise,
        closeTo(1 / 3, 1e-9),
      );
    });

    test('a missing dip counts as none', () {
      final r = scoring.rankShape(shape(dip: null), refs)!;
      expect(r.dip, 0);
    });

    test('needs enough warm-ups with good beats', () {
      expect(scoring.rankShape(shape(), [shape()]), isNull);
      final b = scoring.score(
        featuresWith(shape(rise: 20)),
        base,
        warmups: [shape(), shape(coverage: 0.3)],
      );
      expect(b.pulseMethod, PulseMethod.sdkMean);
      expect(b.pulseNote, 'only 1 warm-up with beats');
      expect(b.zPulse, closeTo(6 / cfg.pulseScaleBpm, 1e-9));
    });

    test('earlier questions add to the warm-ups but can\'t replace them', () {
      // Without this, a turn whose warm-ups were skipped would switch from
      // the SDK mean to beats at Q3, mixing two scales in one turn.
      final noWarmups = scoring.score(
        featuresWith(shape(rise: 20)),
        base,
        earlier: [shape(), shape(), shape()],
      );
      expect(noWarmups.pulseMethod, PulseMethod.sdkMean);
      expect(noWarmups.pulseNote, 'only 0 warm-ups with beats');
      final both = scoring.score(
        featuresWith(shape(rise: 20)),
        base,
        warmups: [shape(), shape()],
        earlier: [shape(), shape(coverage: 0.2)],
      );
      expect(both.pulseMethod, PulseMethod.beats);
      expect(both.shape!.refs, 3, reason: 'the bad earlier one is left out');
    });

    test('good beats and enough references replace the SDK-mean pulse', () {
      final b = scoring.score(
        featuresWith(shape(rise: 20, sustained: 12, dip: 10), meanPulse: 70),
        base,
        warmups: refs.take(2).toList(),
        earlier: refs.skip(2).toList(),
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

    test('a racing first question isn\'t compared with itself', () {
      // The warm-ups' windows used to run 12 s past their question, into
      // Q1, so a racing Q1 raised its own references.
      fakeAsync((async) {
        final w = World(async);
        w.heart = (_) =>
            w.game.phase == GamePhase.answer || w.game.phase == GamePhase.settle
            ? 90
            : 70;
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        final turn = w.game.currentTurn;
        final q1Start = w.now;
        for (var i = 0; i < turn.warmupTimings.length; i++) {
          final end = turn.warmupTimings[i].windowEnd(
            cfg.minWindowAfterQuestionMs,
          );
          expect(end, lessThanOrEqualTo(q1Start), reason: 'warm-up $i');
          if (i + 1 < turn.warmupTimings.length) {
            expect(
              end,
              lessThanOrEqualTo(turn.warmupTimings[i + 1].tQ0),
              reason: 'warm-up $i runs into the next one',
            );
          }
        }
        final r = w.askAndAnswer();
        final b = r.breakdown!;
        expect(b.pulseMethod, PulseMethod.beats, reason: '${b.pulseNote}');
        for (final ref in turn.warmupShapes!) {
          expect(ref.rise, lessThan(3), reason: 'a warm-up saw Q1\'s race');
        }
        expect(b.zPulse, greaterThan(0.6));
        w.dispose();
      });
    });

    test('skipped warm-ups keep the whole turn on the SDK mean', () {
      fakeAsync((async) {
        final w = World(async);
        w.heart = (_) => 70;
        w.autoAnswerWarmups = false;
        w.startGame(['Sam', 'Alex'], questions: 5);
        w.game.agreeToMeasure();
        w.until(
          () => w.game.phase == GamePhase.ask,
          what: 'calibration with every warm-up skipped',
          step: () {
            if (w.game.currentWarmup != null) w.game.skipWarmup();
          },
        );
        expect(w.game.currentTurn.warmupTimings, isEmpty);
        for (var q = 0; q < 5; q++) {
          final r = w.askAndAnswer(question: 'Q$q?');
          expect(r.breakdown!.pulseMethod, PulseMethod.sdkMean, reason: 'Q$q');
          expect(r.breakdown!.pulseNote, 'only 0 warm-ups with beats');
          if (q < 4) w.game.nextQuestion();
        }
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
