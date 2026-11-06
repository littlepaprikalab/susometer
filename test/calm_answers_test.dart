// Monte Carlo check of the score's zero point: thousands of made-up players
// answer through the real baseline and feature code, and the verdicts are
// counted. A calm, honest answer must come out Legit nearly every time, and
// a clear stress reaction must still come out Sus.
//
// The noise levels are assumptions (SmartSpectra's real expression noise
// isn't documented), chosen on the high side so the test is a fair bar.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/game/scoring.dart';
import 'package:susometer/game/scoring_config.dart';
import 'package:susometer/game/signal_log.dart';

const cfg = ScoringConfig();
const scoring = Scoring(cfg);

/// What one kind of answer looks like, compared with the warm-ups.
class Scenario {
  const Scenario({
    this.stillBlinks = 17,
    this.chatBlinks = 17,
    this.answerBlinks = 17,
    this.exprSd = 0.1,
    this.thinkFactor = 1,
    this.extraPauseS = 0,
    this.riseUp = 0,
    this.sustainedUp = 0,
    this.smile = 0,
    this.stress = 0,
  });

  /// Blinks per minute while sitting still, chatting through the warm-ups,
  /// and during the question.
  final double stillBlinks;
  final double chatBlinks;
  final double answerBlinks;

  /// How much each expression score wobbles on its own (0..1 scale).
  final double exprSd;

  /// Answer latency vs the warm-ups: × [thinkFactor], + [extraPauseS].
  final double thinkFactor;
  final double extraPauseS;

  /// Heart rate vs the warm-ups (BPM): a higher peak and a higher mean.
  final double riseUp;
  final double sustainedUp;

  /// A 2 s smile (happy only).
  final double smile;

  /// A 3 s burst of surprise and fear with no smile.
  final double stress;
}

class Tally {
  final counts = {for (final v in Verdict.values) v: 0};
  var n = 0;
  var sum = 0;
  final parts = [0.0, 0.0, 0.0, 0.0];

  double share(Verdict v) => counts[v]! / n;
  double get mean => sum / n;

  @override
  String toString() =>
      'mean ${mean.round()}, Legit ${(100 * share(Verdict.legit)).round()}%'
      ', Hmm ${(100 * share(Verdict.hmm)).round()}%'
      ', Sus ${(100 * share(Verdict.sus)).round()}%'
      ' | pulse ${(0.45 * parts[0] / n).toStringAsFixed(3)}'
      ' blink ${(0.25 * parts[1] / n).toStringAsFixed(3)}'
      ' expr ${(0.15 * parts[2] / n).toStringAsFixed(3)}'
      ' hes ${(0.15 * parts[3] / n).toStringAsFixed(3)}';
}

Tally simulate(Scenario sc, {int players = 1500, int seed = 7}) {
  final rng = math.Random(seed);
  double gauss() {
    final u = 1 - rng.nextDouble();
    return math.sqrt(-2 * math.log(u)) *
        math.cos(2 * math.pi * rng.nextDouble());
  }

  void blinks(SignalLog log, int t0, int t1, double perMin) {
    var t = t0.toDouble();
    while (true) {
      t += -math.log(1 - rng.nextDouble()) / (perMin / 60000);
      if (t > t1) return;
      log.blinks.add(t.round());
    }
  }

  // Each expression drifts around its own level with ~1 s of memory.
  const levels = {
    'neutral': 0.5,
    'happy': 0.15,
    'surprise': 0.1,
    'fear': 0.05,
    'contempt': 0.1,
    'disgust': 0.05,
  };
  final x = Map.of(levels);
  final phi = math.exp(-0.1);
  void face(SignalLog log, int t0, int t1, {int? smileAt, int? stressAt}) {
    for (var t = t0; t <= t1; t += 100) {
      for (final e in levels.entries) {
        x[e.key] =
            e.value +
            phi * (x[e.key]! - e.value) +
            sc.exprSd * math.sqrt(1 - phi * phi) * gauss();
      }
      final p = {for (final e in x.entries) e.key: e.value.clamp(0.0, 1.0)};
      if (smileAt != null && t >= smileAt && t < smileAt + 2000) {
        p['happy'] = p['happy']! + sc.smile;
      }
      if (stressAt != null && t >= stressAt && t < stressAt + 3000) {
        p['surprise'] = p['surprise']! + sc.stress;
        p['fear'] = p['fear']! + sc.stress * 0.6;
      }
      log.expr.add(ExprPoint(t, p));
    }
  }

  void steady(SignalLog log, int t0, int t1) {
    for (var t = t0; t <= t1; t += 100) {
      if (t % 1000 == 0) log.pulse.add(PulsePoint(t, 70, 0.9, validOk: true));
      log.frames.add(
        FaceFrame(
          tMs: t,
          running: true,
          facePresent: true,
          validationCode: 'OK',
          validationHint: '',
          pulseFresh: true,
        ),
      );
    }
  }

  double latency() => math.exp(gauss() * 0.5); // median 1 s
  PulseShape shape({double up = 0, double sustainedUp = 0}) => PulseShape(
    preBpm: 70,
    meanBpm: 70,
    rise: 5 + up + 2.5 * gauss(),
    sustained: 1.5 + sustainedUp + 2 * gauss(),
    dip: 1 + 2 * gauss(),
    coverage: 0.95,
    sdkDiffBpm: 1,
  );

  final tally = Tally();
  for (var i = 0; i < players; i++) {
    final log = SignalLog(config: cfg);
    // Calibration: 20 s sitting still, then three warm-ups (~8 s each).
    blinks(log, 0, 20000, sc.stillBlinks);
    blinks(log, 20000, 44000, sc.chatBlinks);
    face(log, 0, 44000);
    steady(log, 0, 44000);
    final base = scoring.baseline(
      log,
      start: 0,
      quietEnd: 20000,
      end: 44000,
      warmupLatenciesS: [latency(), latency(), latency()],
    )!;

    // One question, asked a minute later.
    const tQ0 = 100000;
    const tQ1 = 103000;
    final h = latency() * sc.thinkFactor + sc.extraPauseS;
    final tA0 = tQ1 + (h * 1000).round();
    final timing = QuestionTiming(
      tQ0: tQ0,
      tQ1: tQ1,
      tA0: tA0,
      tA1: tA0 + 6000,
      hesitationFromMs: tQ1,
    );
    final t1 = timing.windowEnd(cfg.minWindowAfterQuestionMs);
    blinks(log, tQ0, t1, sc.answerBlinks);
    face(
      log,
      tQ0,
      t1,
      smileAt: sc.smile > 0 ? tA0 + 2000 : null,
      stressAt: sc.stress > 0 ? tQ1 : null,
    );
    steady(log, tQ0, t1);

    final f = scoring.features(log, timing, base);
    final withShape = WindowFeatures(
      meanPulse: f.meanPulse,
      windowMs: f.windowMs,
      blinkRatePerMin: f.blinkRatePerMin,
      blinkFreeze: f.blinkFreeze,
      exprPeakDelta: f.exprPeakDelta,
      exprPeakCategory: f.exprPeakCategory,
      hesitationS: f.hesitationS,
      cleanFraction: f.cleanFraction,
      confidentPulseSamples: f.confidentPulseSamples,
      pulseShape: shape(up: sc.riseUp, sustainedUp: sc.sustainedUp),
    );
    final b = scoring.score(
      withShape,
      base,
      warmups: [shape(), shape(), shape()],
    );
    tally.counts[b.verdict] = tally.counts[b.verdict]! + 1;
    tally.n++;
    tally.sum += b.score;
    tally.parts[0] += b.zPulse;
    tally.parts[1] += b.zBlink;
    tally.parts[2] += b.zExpr;
    tally.parts[3] += b.zHesitation;
  }
  return tally;
}

void main() {
  test('nothing changed since the warm-ups: Legit', () {
    final t = simulate(const Scenario());
    expect(t.share(Verdict.legit), greaterThanOrEqualTo(0.9), reason: '$t');
    expect(t.share(Verdict.sus), lessThanOrEqualTo(0.01), reason: '$t');
  });

  test('an ordinary honest answer to a real question: still Legit', () {
    // Sitting still blinks less than chatting; a real question takes longer
    // to think about and to answer than "coffee or tea?", talking raises the
    // heart rate a little, and the answer comes with a smile.
    final t = simulate(
      const Scenario(
        stillBlinks: 10,
        chatBlinks: 22,
        answerBlinks: 20,
        thinkFactor: 2,
        riseUp: 4,
        sustainedUp: 2.5,
        smile: 0.3,
      ),
    );
    expect(t.share(Verdict.legit), greaterThanOrEqualTo(0.75), reason: '$t');
    expect(t.share(Verdict.sus), lessThanOrEqualTo(0.03), reason: '$t');
  });

  test('a clear stress reaction: Sus', () {
    final t = simulate(
      const Scenario(
        stillBlinks: 10,
        chatBlinks: 22,
        answerBlinks: 40,
        extraPauseS: 3,
        riseUp: 12,
        sustainedUp: 8,
        stress: 0.4,
      ),
    );
    expect(t.share(Verdict.sus), greaterThanOrEqualTo(0.8), reason: '$t');
  });

  test('a racing heart alone: mostly Hmm…', () {
    final t = simulate(const Scenario(riseUp: 12, sustainedUp: 8));
    expect(t.share(Verdict.legit), lessThanOrEqualTo(0.15), reason: '$t');
  });
}
