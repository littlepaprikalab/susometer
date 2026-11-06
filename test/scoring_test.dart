import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/game/scoring.dart';
import 'package:susometer/game/scoring_config.dart';
import 'package:susometer/game/signal_log.dart';
import 'package:susometer/presage/presage_models.dart';

import 'synthetic.dart';

const cfg = ScoringConfig();
const scoring = Scoring(cfg);

/// A calm 40 s calibration: pulse ~70, 15 blinks/min, face always present.
(SignalLog, Baseline) calmBaseline() {
  final log = SignalLog(config: cfg);
  for (final s in synth(
    start: 0,
    end: 40000,
    pulse: (t) => 70 + math.sin(t / 3000),
    blinks: every(0, 40000, 15),
    expr: (t) => const {'neutral': 0.85, 'surprise': 0.05, 'fear': 0.02},
  )) {
    log.add(s);
  }
  final base = scoring.baseline(
    log,
    start: 0,
    quietEnd: 20000,
    end: 40000,
    warmupLatenciesS: const [0.8, 1.0, 1.2],
  )!;
  return (log, base);
}

QuestionTiming timing({
  int tQ0 = 50000,
  int tQ1 = 53000,
  int? tA0 = 54000,
  int tA1 = 58000,
}) => QuestionTiming(
  tQ0: tQ0,
  tQ1: tQ1,
  tA0: tA0,
  tA1: tA1,
  hesitationFromMs: tQ1,
);

void addQuestion(
  SignalLog log, {
  required double pulse,
  double blinkRate = 15,
  double conf = 0.9,
  Map<String, double> Function(int t)? expr,
  String Function(int t)? code,
}) {
  for (final s in synth(
    start: 40100,
    end: 70000,
    pulse: (t) => t >= 50000 ? pulse : 70,
    conf: (_) => conf,
    blinks: [...every(40100, 50000, 15), ...every(50000, 70000, blinkRate)],
    expr: expr,
    code: code,
  )) {
    log.add(s);
  }
}

void main() {
  group('baseline (SPEC §5.2)', () {
    test('calm calibration gives the expected baseline and is valid', () {
      final (_, base) = calmBaseline();
      expect(base.pulse, closeTo(70, 1.2));
      expect(base.blinkRatePerMin, closeTo(15, 1.5));
      expect(base.latencyS, 1.0);
      expect(base.confidentPulseMs, greaterThanOrEqualTo(12000));
      expect(base.faceFraction, 1.0);
      expect(base.expr['surprise'], closeTo(0.05, 1e-9));
      expect(scoring.baselineValid(base), isTrue);
    });

    test('low-confidence pulse never makes a valid baseline', () {
      final log = SignalLog(config: cfg);
      for (final s in synth(
        start: 0,
        end: 40000,
        pulse: (_) => 70,
        conf: (_) => 0.2,
      )) {
        log.add(s);
      }
      final base = scoring.baseline(
        log,
        start: 0,
        quietEnd: 20000,
        end: 40000,
        warmupLatenciesS: const [],
      );
      expect(base, isNull, reason: 'no confident samples at all');
      expect(scoring.baselineValid(base), isFalse);
    });

    test('face missing too often keeps calibrating', () {
      final log = SignalLog(config: cfg);
      for (final s in synth(
        start: 0,
        end: 40000,
        pulse: (_) => 70,
        code: (t) => (t ~/ 1000) % 3 == 0 ? 'NO_FACE_FOUND' : 'OK',
      )) {
        log.add(s);
      }
      final base = scoring.baseline(
        log,
        start: 0,
        quietEnd: 20000,
        end: 40000,
        warmupLatenciesS: const [],
      );
      expect(base, isNotNull);
      expect(base!.faceFraction, lessThan(0.8));
      expect(scoring.baselineValid(base), isFalse);
    });

    test('baseline latency defaults to 1.0 s with no warm-up answers', () {
      final log = SignalLog(config: cfg);
      for (final s in synth(start: 0, end: 30000, pulse: (_) => 70)) {
        log.add(s);
      }
      final base = scoring.baseline(
        log,
        start: 0,
        quietEnd: 20000,
        end: 30000,
        warmupLatenciesS: const [],
      );
      expect(base!.latencyS, cfg.defaultBaseLatencyS);
    });
  });

  group('question score (SPEC §5.3–5.4)', () {
    test('a calm answer is Legit', () {
      final (log, base) = calmBaseline();
      addQuestion(log, pulse: 71);
      final f = scoring.features(log, timing(), base);
      expect(scoring.isClean(f), isTrue);
      final s = scoring.score(f, base);
      expect(s.verdict, Verdict.legit);
      expect(s.score, lessThan(cfg.legitBelow));
    });

    test('a stressed answer is Sus', () {
      final (log, base) = calmBaseline();
      addQuestion(
        log,
        pulse: 90,
        blinkRate: 32,
        expr: (t) => t >= 55000 && t <= 58000
            ? const {'neutral': 0.3, 'surprise': 0.55, 'fear': 0.1}
            : const {'neutral': 0.85, 'surprise': 0.05, 'fear': 0.02},
      );
      final f = scoring.features(log, timing(tA0: 56500), base);
      final s = scoring.score(f, base);
      expect(s.zPulse, 1.0);
      expect(s.zBlink, 1.0);
      expect(s.zExpr, greaterThan(0.9));
      expect(f.hesitationS, closeTo(3.5, 1e-9));
      expect(s.verdict, Verdict.sus);
      expect(s.score, greaterThanOrEqualTo(cfg.susFrom));
    });

    test('a moderate reaction lands in Hmm…', () {
      final (log, base) = calmBaseline();
      addQuestion(log, pulse: 79, blinkRate: 20);
      final f = scoring.features(log, timing(tA0: 55000), base);
      final s = scoring.score(f, base);
      expect(s.verdict, Verdict.hmm, reason: 'score was ${s.score}');
    });

    test('score follows the formula exactly', () {
      final base = const Baseline(
        pulse: 70,
        blinkRatePerMin: 15,
        expr: {'surprise': 0.1},
        latencyS: 1.0,
        confidentPulseMs: 20000,
        faceFraction: 1,
      );
      const f = WindowFeatures(
        meanPulse: 77.5, // zPulse 0.5
        blinkRatePerMin: 19.5, // (4.5/15)/0.6 = 0.5
        blinkFreeze: false,
        exprPeakDelta: 0.2, // 0.2/0.4 = 0.5
        exprPeakCategory: 'surprise',
        hesitationS: 2.5, // (1.5)/3 = 0.5
        cleanFraction: 1,
        confidentPulseSamples: 10,
      );
      final s = scoring.score(f, base);
      expect(s.zPulse, closeTo(0.5, 1e-9));
      expect(s.zBlink, closeTo(0.5, 1e-9));
      expect(s.zExpr, closeTo(0.5, 1e-9));
      expect(s.zHesitation, closeTo(0.5, 1e-9));
      expect(s.raw, closeTo(0.5, 1e-9));
      expect(s.score, (100 * math.pow(0.5, 0.8)).round()); // 57
      expect(s.verdict, Verdict.hmm);
    });

    test('features below baseline clamp to zero', () {
      final base = const Baseline(
        pulse: 80,
        blinkRatePerMin: 20,
        expr: {},
        latencyS: 2,
        confidentPulseMs: 20000,
        faceFraction: 1,
      );
      const f = WindowFeatures(
        meanPulse: 70,
        blinkRatePerMin: 5,
        blinkFreeze: false,
        exprPeakDelta: 0,
        exprPeakCategory: null,
        hesitationS: 0,
        cleanFraction: 1,
        confidentPulseSamples: 5,
      );
      final s = scoring.score(f, base);
      expect(s.raw, 0);
      expect(s.score, 0);
      expect(s.verdict, Verdict.legit);
    });

    test('a blink freeze counts as at least 0.6', () {
      final base = const Baseline(
        pulse: 70,
        blinkRatePerMin: 20,
        expr: {},
        latencyS: 1,
        confidentPulseMs: 20000,
        faceFraction: 1,
      );
      const f = WindowFeatures(
        meanPulse: 70,
        blinkRatePerMin: 0,
        blinkFreeze: true,
        exprPeakDelta: 0,
        exprPeakCategory: null,
        hesitationS: 1,
        cleanFraction: 1,
        confidentPulseSamples: 5,
      );
      expect(scoring.score(f, base).zBlink, cfg.blinkFreezeZ);
      // ...but not when the baseline rate is too low to tell.
      final lowBase = const Baseline(
        pulse: 70,
        blinkRatePerMin: 8,
        expr: {},
        latencyS: 1,
        confidentPulseMs: 20000,
        faceFraction: 1,
      );
      expect(scoring.score(f, lowBase).zBlink, 0);
    });

    test('blink freeze detection on a real log', () {
      final log = SignalLog(config: cfg);
      for (final s in synth(
        start: 0,
        end: 20000,
        blinks: [1000, 2000, 3000, 12000],
      )) {
        log.add(s);
      }
      expect(log.blinkFreeze(3000, 11000, 6000), isTrue);
      expect(log.blinkFreeze(0, 4000, 6000), isFalse);
      expect(
        log.blinkFreeze(12000, 20000, 6000),
        isTrue,
        reason: 'gap to window end',
      );
    });

    test('custom ScoringConfig weights are honored', () {
      const pulseOnly = Scoring(
        ScoringConfig(
          wPulse: 1,
          wBlink: 0,
          wExpr: 0,
          wHesitation: 0,
          scoreExponent: 1,
        ),
      );
      final base = const Baseline(
        pulse: 70,
        blinkRatePerMin: 15,
        expr: {},
        latencyS: 1,
        confidentPulseMs: 20000,
        faceFraction: 1,
      );
      const f = WindowFeatures(
        meanPulse: 76,
        blinkRatePerMin: 60,
        blinkFreeze: false,
        exprPeakDelta: 1,
        exprPeakCategory: 'fear',
        hesitationS: 10,
        cleanFraction: 1,
        confidentPulseSamples: 5,
      );
      expect(pulseOnly.score(f, base).score, 40);
    });
  });

  group('confidence gating (SPEC §5.5)', () {
    test('low-confidence pulse samples are ignored in the window', () {
      final (log, base) = calmBaseline();
      for (final s in synth(
        start: 40100,
        end: 70000,
        pulse: (t) => t >= 50000 && t < 60000 ? 130 : 70,
        conf: (t) => t >= 50000 && t < 60000 ? 0.2 : 0.9,
      )) {
        log.add(s);
      }
      final f = scoring.features(log, timing(), base);
      expect(f.meanPulse, closeTo(70, 0.01));
    });

    test('pulse that arrives while validation is not OK is ignored', () {
      final (log, base) = calmBaseline();
      for (final s in synth(
        start: 40100,
        end: 70000,
        pulse: (t) => t >= 50000 && t < 56000 ? 130 : 70,
        code: (t) => t >= 50000 && t < 56000 ? 'EXCESSIVE_MOTION' : 'OK',
      )) {
        log.add(s);
      }
      final f = scoring.features(log, timing(), base);
      expect(f.meanPulse, closeTo(70, 0.01));
    });

    test('losing the face for most of the window means No clean read', () {
      final (log, base) = calmBaseline();
      addQuestion(
        log,
        pulse: 85,
        code: (t) => t >= 51000 && t < 62000 ? 'NO_FACE_FOUND' : 'OK',
      );
      final t = timing();
      final f = scoring.features(log, t, base);
      expect(f.cleanFraction, lessThan(cfg.minCleanFraction));
      expect(scoring.isClean(f), isFalse);
      final reasons = scoring.noCleanReadReasons(log, t, 'Sam');
      expect(reasons.first, contains("lost Sam's face"));
    });

    test('motion shows up as a reason', () {
      final (log, base) = calmBaseline();
      addQuestion(
        log,
        pulse: 85,
        code: (t) => t >= 50000 && t < 64000 ? 'EXCESSIVE_MOTION' : 'OK',
      );
      final t = timing();
      expect(scoring.isClean(scoring.features(log, t, base)), isFalse);
      expect(
        scoring.noCleanReadReasons(log, t, 'Sam'),
        contains('Sam moved around a lot while answering'),
      );
    });

    test('no pulse at all is never scored', () {
      final (log, base) = calmBaseline();
      for (final s in synth(start: 40100, end: 70000)) {
        log.add(s);
      }
      final f = scoring.features(log, timing(), base);
      expect(f.meanPulse, isNull);
      expect(scoring.isClean(f), isFalse);
    });
  });

  test('a single noisy expression frame is smoothed away', () {
    final log = SignalLog(config: cfg);
    for (final s in synth(
      start: 0,
      end: 10000,
      expr: (t) =>
          t == 5000 ? const {'surprise': 0.95} : const {'surprise': 0.05},
    )) {
      log.add(s);
    }
    final (peak, _) = log.exprPeakDelta(
      0,
      10000,
      const {'surprise': 0.05},
      const ['surprise'],
      500,
    );
    expect(peak, lessThan(0.2));
    final (sustained, cat) = log.exprPeakDelta(
      0,
      10000,
      const {'surprise': 0.0},
      const ['surprise'],
      0,
    );
    expect(sustained, closeTo(0.95, 1e-9));
    expect(cat, 'surprise');
  });

  test('verdict bands: <35 Legit, 35–59 Hmm…, ≥60 Sus!', () {
    Verdict v(int s) => verdictFor(s, legitBelow: 35, susFrom: 60);
    expect(v(0), Verdict.legit);
    expect(v(34), Verdict.legit);
    expect(v(35), Verdict.hmm);
    expect(v(59), Verdict.hmm);
    expect(v(60), Verdict.sus);
    expect(v(100), Verdict.sus);
  });

  test('signal log stays bounded', () {
    final log = SignalLog(config: cfg, maxFrames: 500, maxTracePoints: 600);
    for (final s in synth(
      start: 0,
      end: 200000,
      pulse: (_) => 70,
      blinks: every(0, 200000, 20),
      wave: pulseWave(start: 0, end: 200000, bpm: (_) => 70),
    )) {
      log.add(s);
    }
    expect(log.frames.length, 500);
    expect(log.pulse.length, lessThanOrEqualTo(500));
    expect(log.trace.length, 600);
  });

  group('bad values from native code', () {
    PresageSample sample(Map<String, Object?> extra) => PresageSample.fromMap({
      't': 1000,
      'status': 'running',
      'pulseConf': 0.9,
      'pulseAt': 1000,
      'validation': {'code': 'OK', 'hint': ''},
      ...extra,
    });

    test('NaN and infinity never get past parsing', () {
      final s = PresageSample.fromMap({
        't': double.nan,
        'status': 'running',
        'pulse': double.infinity,
        'pulseConf': double.nan,
        'pulseAt': double.infinity,
        'rmssd': double.negativeInfinity,
        'expr': {'happy': double.nan, 'neutral': 0.5},
        'trace': [1.0, double.nan, 2.0],
      });
      expect(s.pulse, isNull);
      expect(s.pulseConf, isNull);
      expect(s.pulseAtMs, isNull);
      expect(s.rmssd, isNull);
      expect(s.expr, {'neutral': 0.5});
      expect(s.trace, [1.0, 2.0]);
      expect(s.tMs, greaterThan(0), reason: 'falls back to now, no throw');
    });

    test('glitch pulse readings are dropped, plausible ones kept', () {
      final log = SignalLog();
      var at = 1000;
      for (final bpm in [72.0, 900.0, 4.0, 220.0, 30.0]) {
        log.add(sample({'pulse': bpm, 'pulseAt': at, 't': at}));
        at += 1000;
      }
      expect(log.confidentPulse(0, at).map((p) => p.bpm), [72, 220, 30]);
    });
  });
}
