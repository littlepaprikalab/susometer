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
      expect(base.blinkBaseMs, 20000, reason: 'the warm-up chat');
      expect(base.exprPeak['surprise'], closeTo(0.05, 1e-9));
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
        blinkRate: 40,
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
      addQuestion(log, pulse: 80, blinkRate: 20);
      final f = scoring.features(log, timing(tA0: 56000), base);
      final s = scoring.score(f, base);
      expect(s.verdict, Verdict.hmm, reason: 'score was ${s.score}');
    });

    test('score follows the formula exactly', () {
      final base = const Baseline(
        pulse: 70,
        blinkRatePerMin: 15,
        blinkBaseMs: 30000,
        exprPeak: {'surprise': 0.1},
        latencyS: 1.0,
        confidentPulseMs: 20000,
        faceFraction: 1,
      );
      final f = WindowFeatures(
        meanPulse: 77.5, // zPulse 0.5
        windowMs: 60000,
        // Expected 15 in the minute; chance wobble √(15 · (1 + 1/0.5));
        // then 0.5 · 15 · 0.6 = 4.5 more.
        blinkRatePerMin: 15 + math.sqrt(45) + 4.5,
        blinkFreeze: false,
        exprPeakDelta: 0.15, // 0.15/0.3 = 0.5
        exprPeakCategory: 'surprise',
        hesitationS: 3.5, // (3.5 − 1 − 1 grace)/3 = 0.5
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
        exprPeak: {},
        latencyS: 2,
        confidentPulseMs: 20000,
        faceFraction: 1,
      );
      const f = WindowFeatures(
        meanPulse: 70,
        windowMs: 15000,
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
        exprPeak: {},
        latencyS: 1,
        confidentPulseMs: 20000,
        faceFraction: 1,
      );
      const f = WindowFeatures(
        meanPulse: 70,
        windowMs: 15000,
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
        exprPeak: {},
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

    test('a freeze must be longer than chance would explain', () {
      // At 17 blinks a minute, a 15 s window needs ~15.7 s without one (so
      // never); a fast blinker's freeze can be shorter; never under 6 s.
      expect(scoring.blinkFreezeMs(17, 15000), closeTo(15682, 5));
      expect(scoring.blinkFreezeMs(40, 15000), closeTo(7948, 5));
      expect(scoring.blinkFreezeMs(200, 15000), cfg.blinkFreezeMs);
      expect(scoring.blinkFreezeMs(0, 15000), cfg.blinkFreezeMs);
    });

    test('blinking like you did in the warm-ups is free', () {
      // Still 10/min, chatting 22/min: the chat rate is the baseline, and a
      // couple of blinks over it is chance.
      final log = SignalLog(config: cfg);
      for (final s in synth(
        start: 0,
        end: 40000,
        pulse: (_) => 70,
        blinks: [...every(0, 20000, 10), ...every(20000, 40000, 22)],
      )) {
        log.add(s);
      }
      final base = scoring.baseline(
        log,
        start: 0,
        quietEnd: 20000,
        end: 40000,
        warmupLatenciesS: const [1],
      )!;
      expect(base.blinkRatePerMin, closeTo(22, 1.5));
      for (final s in synth(
        start: 40100,
        end: 70000,
        pulse: (_) => 70,
        blinks: every(40100, 70000, 26),
      )) {
        log.add(s);
      }
      final f = scoring.features(log, timing(), base);
      expect(scoring.blinkPart(f, base), 0);
    });

    test('a short warm-up chat falls back to the whole calibration', () {
      final log = SignalLog(config: cfg);
      for (final s in synth(
        start: 0,
        end: 30000,
        pulse: (_) => 70,
        blinks: every(0, 30000, 12),
      )) {
        log.add(s);
      }
      final base = scoring.baseline(
        log,
        start: 0,
        quietEnd: 20000,
        end: 30000,
        warmupLatenciesS: const [],
      )!;
      expect(base.blinkBaseMs, 30000);
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
        exprPeak: {},
        latencyS: 1,
        confidentPulseMs: 20000,
        faceFraction: 1,
      );
      const f = WindowFeatures(
        meanPulse: 76,
        windowMs: 15000,
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

    test('pulse that arrives deep into a validation problem is ignored', () {
      // OK until 49.9 s, then 6 s of motion: the samples at 50.1 and 51.1 s
      // are within the grace, the ones at 52.1–55.1 s aren't (decision 79).
      final (log, base) = calmBaseline();
      for (final s in synth(
        start: 40100,
        end: 70000,
        pulse: (t) => t >= 52000 && t < 56000 ? 130 : 70,
        code: (t) => t >= 50000 && t < 56000 ? 'EXCESSIVE_MOTION' : 'OK',
      )) {
        log.add(s);
      }
      final f = scoring.features(log, timing(), base);
      expect(f.meanPulse, closeTo(70, 0.01));
      expect(log.confidentPulse(50000, 56000).map((p) => p.tMs), [
        50100,
        51100,
      ]);
    });

    test('a passing problem keeps its pulse samples (decision 79)', () {
      // A glance away or a laugh: 1.5 s of a code every 3 s, all through
      // the question. The old gate dropped every sample that landed on one.
      final (log, base) = calmBaseline();
      addQuestion(
        log,
        pulse: 72,
        code: (t) => t >= 50000 && t % 3000 < 1500 ? 'FACE_NOT_FORWARD' : 'OK',
      );
      final t = timing();
      final f = scoring.features(log, t, base);
      expect(f.confidentPulseSamples, 15, reason: 'one a second, 50–65 s');
      expect(f.cleanFraction, 1.0);
      expect(scoring.isClean(f), isTrue);
    });

    test('a confident pulse stays current for 5 s', () {
      final (log, base) = calmBaseline();
      for (final s in synth(
        start: 40100,
        end: 70000,
        pulse: (t) => 70,
        pulseEveryMs: 4500,
      )) {
        log.add(s);
      }
      final f = scoring.features(log, timing(), base);
      expect(cfg.pulseFreshMs, 5000);
      expect(f.cleanFraction, 1.0, reason: 'a sample every 4.5 s is enough');
    });

    test('the grace never spans a camera stop (decision 79)', () {
      // OK until 5 s, the camera stops, and the new session starts dark:
      // its pulse at 5.6 s is 0.6 s after the old session's last OK.
      final log = SignalLog(config: cfg);
      for (final s in synth(start: 0, end: 5000, pulse: (_) => 70)) {
        log.add(s);
      }
      for (final s in synth(start: 5100, end: 5500, status: 'idle')) {
        log.add(s);
      }
      for (final s in synth(
        start: 5600,
        end: 6800,
        pulse: (_) => 90,
        code: (_) => 'TOO_DARK',
      )) {
        log.add(s);
      }
      expect(log.confidentPulse(5600, 6800), isEmpty);
    });

    test('a long problem still stops the pulse after the grace', () {
      final log = SignalLog(config: cfg);
      for (final s in synth(
        start: 0,
        end: 20000,
        pulse: (_) => 70,
        code: (t) => t >= 5000 ? 'TOO_DARK' : 'OK',
      )) {
        log.add(s);
      }
      // Last OK at 4.9 s; samples at 5 and 6 s count, 7 s on don't.
      expect(log.lastConfidentPulseMs, 6000);
      expect(log.pulseFreshAt(11000), isTrue);
      expect(log.pulseFreshAt(11100), isFalse);
      expect(log.cleanFraction(12000, 20000), 0);
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

  group('expressions (warm-up peaks are free)', () {
    SignalLog faceLog(Map<String, double> Function(int t) expr) {
      final log = SignalLog(config: cfg);
      for (final s in synth(start: 0, end: 10000, expr: expr)) {
        log.add(s);
      }
      return log;
    }

    test('each stress expression counts on its own score', () {
      // Happy alongside it doesn't change it.
      final log = faceLog(
        (t) => t >= 4000 && t < 7000
            ? const {'happy': 0.4, 'contempt': 0.5}
            : const {'neutral': 0.9},
      );
      final (delta, cat) = log.exprPeakDelta(
        0,
        10000,
        const {},
        cfg.exprCategories,
        cfg.exprSmoothMs,
      );
      expect(delta, closeTo(0.5, 1e-9));
      expect(cat, 'contempt');
    });

    test('a smile alone adds nothing', () {
      final log = faceLog(
        (t) => t >= 4000 && t < 7000
            ? const {'happy': 0.8, 'neutral': 0.2}
            : const {'neutral': 0.9},
      );
      final (delta, cat) = log.exprPeakDelta(
        0,
        10000,
        const {},
        cfg.exprCategories,
        cfg.exprSmoothMs,
      );
      expect(delta, 0);
      expect(cat, isNull);
    });

    test('a face no stronger than in the warm-ups adds nothing', () {
      Map<String, double> wobble(int t) => {
        'neutral': 0.7,
        'surprise': 0.1 + 0.1 * math.sin(t / 700),
      };
      final log = SignalLog(config: cfg);
      for (final s in synth(
        start: 0,
        end: 70000,
        pulse: (_) => 70,
        expr: wobble,
      )) {
        log.add(s);
      }
      final base = scoring.baseline(
        log,
        start: 0,
        quietEnd: 20000,
        end: 40000,
        warmupLatenciesS: const [1],
      )!;
      expect(base.exprPeak['surprise'], closeTo(0.2, 0.01));
      final f = scoring.features(log, timing(), base);
      expect(f.exprPeakDelta, lessThan(0.01));
    });
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
