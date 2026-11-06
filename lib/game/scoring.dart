import 'dart:math' as math;

import 'beats.dart';
import 'models.dart';
import 'scoring_config.dart';
import 'signal_log.dart';

double _clamp01(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0);

double median(List<double> values) {
  if (values.isEmpty) return double.nan;
  final s = [...values]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/// Entertainment-grade stress score (SPEC.md §5). Pure functions over a
/// [SignalLog], so they're testable with synthetic streams.
class Scoring {
  const Scoring([this.config = const ScoringConfig()]);

  final ScoringConfig config;

  /// Baseline from calibration: quiet phase [start, quietEnd], chat phase
  /// [quietEnd, end]. Returns null until there's at least one confident pulse.
  Baseline? baseline(
    SignalLog log, {
    required int start,
    required int quietEnd,
    required int end,
    required List<double> warmupLatenciesS,
  }) {
    final c = config;
    final pulses = log.confidentPulse(start, end);
    if (pulses.isEmpty) return null;
    // Questions are mostly listening and talking, so compare them with the
    // warm-up chat rather than the still part: people blink more talking.
    final blinkFrom = end - quietEnd >= c.calibMinChatMs ? quietEnd : start;
    Map<String, double> peaks(int from) =>
        log.exprPeaks(from, end, c.exprCategories, c.exprSmoothMs);
    final chatPeaks = peaks(quietEnd);
    final latencies = warmupLatenciesS.where((l) => l >= 0).toList();
    return Baseline(
      pulse: median(pulses.map((p) => p.bpm).toList()),
      blinkRatePerMin: log.blinkRatePerMin(blinkFrom, end),
      blinkBaseMs: end - blinkFrom,
      exprPeak: chatPeaks.isNotEmpty ? chatPeaks : peaks(start),
      latencyS: latencies.isEmpty ? c.defaultBaseLatencyS : median(latencies),
      confidentPulseMs: log.confidentCoverageMs(start, end),
      faceFraction: log.faceFraction(start, end),
    );
  }

  /// Valid once there are ≥ 12 s of confident pulse and the face was present
  /// ≥ 80% of the time (SPEC.md §5.2).
  bool baselineValid(Baseline? b) =>
      b != null &&
      b.confidentPulseMs >= config.calibMinConfidentPulseMs &&
      b.faceFraction >= config.calibMinFaceFraction;

  /// Heartbeats in the waveform between [t0] and [t1] (SPEC.md decision 63).
  BeatSeries beats(SignalLog log, int t0, int t1) =>
      detectBeats(log.traceIn(t0, t1), config);

  /// The beat heart rate's shape over one question's window, or null if there
  /// weren't beats both before the question and during it.
  PulseShape? pulseShape(
    SignalLog log,
    BeatSeries beats,
    QuestionTiming timing,
  ) {
    final c = config;
    final t0 = timing.tQ0;
    final t1 = timing.windowEnd(c.minWindowAfterQuestionMs);
    double? pre;
    for (final span in [c.shapePreMs, c.shapePreFallbackMs]) {
      if (beats.coverage(t0 - span, t0) >= c.shapePreMinCoverage) {
        pre = beats.meanBpm(t0 - span, t0);
        break;
      }
    }
    final mean = beats.meanBpm(t0, t1);
    if (pre == null || mean == null) return null;
    final dipEnd = math.min(timing.tQ1 + c.shapeDipMs, t1);
    double? peak;
    double? low;
    for (final (t, bpm) in beats.smoothed(
      t0,
      t1,
      c.shapeGridMs,
      c.shapeSmoothMs,
    )) {
      if (bpm == null) continue;
      if (peak == null || bpm > peak) peak = bpm;
      if (t >= timing.tQ1 && t <= dipEnd && (low == null || bpm < low)) {
        low = bpm;
      }
    }
    if (peak == null) return null;
    return PulseShape(
      preBpm: pre,
      meanBpm: mean,
      rise: peak - pre,
      sustained: mean - pre,
      dip: low == null ? null : pre - low,
      coverage: beats.coverage(t0, t1),
      sdkDiffBpm: sdkDiff(log, beats, t0, t1),
    );
  }

  /// How far the beats are from the SDK's own pulse over [t0, t1]: the
  /// median difference between each confident SDK reading and the beats'
  /// average over the 12 s before it (the SDK's pulse is a 12 s average).
  /// The SDK's reading may also arrive late, so this tries one delay for the
  /// whole window, 0 to [ScoringConfig.beatSdkMaxLagMs] in 1 s steps, and
  /// keeps the best. A steady offset still shows; a delay alone doesn't.
  /// Null if no reading had enough beats before it.
  double? sdkDiff(SignalLog log, BeatSeries beats, int t0, int t1) {
    final c = config;
    final readings = log.confidentPulse(t0, t1);
    double? best;
    for (var lag = 0; lag <= c.beatSdkMaxLagMs; lag += 1000) {
      final diffs = <double>[];
      for (final p in readings) {
        final to = p.tMs - lag;
        final from = to - c.beatSdkWindowMs;
        if (beats.coverage(from, to) < 0.5) continue;
        diffs.add((beats.meanBpm(from, to)! - p.bpm).abs());
      }
      // Compare delays on the same readings: one that leaves readings out
      // can't win by dropping the hard ones.
      if (diffs.isEmpty || diffs.length < readings.length / 2) continue;
      final d = median(diffs);
      if (best == null || d < best) best = d;
    }
    return best;
  }

  /// Why [s] can't be scored, or null if it can: the beats must cover enough
  /// of the window and agree with the SDK's own pulse.
  String? shapeProblem(PulseShape? s) {
    final c = config;
    if (s == null) return 'no beats found';
    if (s.coverage < c.beatMinCoverage) {
      return 'beats cover ${(s.coverage * 100).round()}%';
    }
    final diff = s.sdkDiffBpm;
    if (diff == null) return 'beats not checked against the SDK';
    if (diff > c.beatMaxSdkDiffBpm) {
      return 'beats off the SDK by ${diff.toStringAsFixed(0)} BPM';
    }
    return null;
  }

  /// Ranks [q] against the player's earlier answers [refs] (warm-ups and
  /// earlier questions): each feature's distance from their median, in robust
  /// spreads (1.4826 × median absolute deviation, never under the feature's
  /// floor). The first [ScoringConfig.shapeZFree] spreads are free, and
  /// [ScoringConfig.shapeZFull] counts in full. Null with fewer than
  /// [ScoringConfig.shapeMinRefs] references.
  ShapeScore? rankShape(PulseShape q, List<PulseShape> refs) {
    final c = config;
    if (refs.length < c.shapeMinRefs) return null;
    double part(double? x, Iterable<double?> values, double floor) {
      final r = [for (final v in values) ?v];
      if (x == null || r.length < c.shapeMinRefs) return 0;
      final mid = median(r);
      final mad = median([for (final v in r) (v - mid).abs()]);
      final spread = math.max(1.4826 * mad, floor);
      return _clamp01(
        ((x - mid) / spread - c.shapeZFree) / (c.shapeZFull - c.shapeZFree),
      );
    }

    final rise = part(q.rise, refs.map((r) => r.rise), c.shapeRiseFloorBpm);
    final sustained = part(
      q.sustained,
      refs.map((r) => r.sustained),
      c.shapeSustainedFloorBpm,
    );
    final dip = part(q.dip, refs.map((r) => r.dip), c.shapeDipFloorBpm);
    final total = c.wShapeRise + c.wShapeSustained + c.wShapeDip;
    return ShapeScore(
      rise: rise,
      sustained: sustained,
      dip: dip,
      refs: refs.length,
      zPulse: _clamp01(
        (c.wShapeRise * rise +
                c.wShapeSustained * sustained +
                c.wShapeDip * dip) /
            total,
      ),
    );
  }

  WindowFeatures features(
    SignalLog log,
    QuestionTiming timing,
    Baseline base, {
    BeatSeries? beats,
  }) {
    final t0 = timing.tQ0;
    final t1 = timing.windowEnd(config.minWindowAfterQuestionMs);
    final pulses = log.confidentPulse(t0, t1);
    final meanPulse = pulses.isEmpty
        ? null
        : pulses.map((p) => p.bpm).reduce((a, b) => a + b) / pulses.length;
    final (peak, cat) = log.exprPeakDelta(
      t0,
      t1,
      base.exprPeak,
      config.exprCategories,
      config.exprSmoothMs,
    );
    final answerStart = timing.tA0 ?? timing.tA1;
    final hesitation =
        math.max(0, answerStart - timing.hesitationFromMs) / 1000;
    return WindowFeatures(
      meanPulse: meanPulse,
      windowMs: t1 - t0,
      blinkRatePerMin: log.blinkRatePerMin(t0, t1),
      blinkFreeze: log.blinkFreeze(
        t0,
        t1,
        blinkFreezeMs(base.blinkRatePerMin, t1 - t0),
      ),
      exprPeakDelta: peak,
      exprPeakCategory: cat,
      hesitationS: hesitation.toDouble(),
      cleanFraction: log.cleanFraction(t0, t1),
      confidentPulseSamples: pulses.length,
      pulseShape: beats == null ? null : pulseShape(log, beats, timing),
    );
  }

  /// How long a gap without blinks must be to count as a freeze in a window
  /// of [windowMs], at [ratePerMin]: blinks come at random, about
  /// rate × window of them, and the chance that any gap between them is at
  /// least g long is about rate × window × e^(−rate × g). This is the g where
  /// that chance is [ScoringConfig.blinkFreezeChance], and never less than
  /// [ScoringConfig.blinkFreezeMs].
  int blinkFreezeMs(double ratePerMin, int windowMs) {
    final c = config;
    final perMs = ratePerMin / 60000;
    if (perMs <= 0 || windowMs <= 0) return c.blinkFreezeMs;
    final g = math.log(perMs * windowMs / c.blinkFreezeChance) / perMs;
    return g.isFinite ? math.max(c.blinkFreezeMs, g.round()) : c.blinkFreezeMs;
  }

  /// The blink part (0..1): blinks beyond what the baseline rate plus chance
  /// would give. Blinks are random, so a count of about n wobbles by about
  /// √n on its own, and the baseline, counted over [Baseline.blinkBaseMs],
  /// adds its own wobble. [ScoringConfig.blinkChanceSpreads] of that is free.
  double blinkPart(WindowFeatures f, Baseline base) {
    final c = config;
    final mins = f.windowMs / 60000;
    if (mins <= 0) return 0;
    final rate = math.max(base.blinkRatePerMin, c.blinkMinBaselinePerMin);
    final expected = rate * mins;
    final baseMins = base.blinkBaseMs / 60000;
    final wobble = math.sqrt(
      expected * (1 + (baseMins > 0 ? mins / baseMins : 0)),
    );
    final excess =
        f.blinkRatePerMin * mins -
        base.blinkRatePerMin * mins -
        c.blinkChanceSpreads * wobble;
    var z = _clamp01(excess / (expected * c.blinkRelativeScale));
    if (f.blinkFreeze &&
        base.blinkRatePerMin >= c.blinkFreezeMinBaselinePerMin) {
      z = math.max(z, c.blinkFreezeZ);
    }
    return z;
  }

  /// Confidence gate (SPEC.md §5.5): never fake a verdict.
  bool isClean(WindowFeatures f) =>
      f.meanPulse != null &&
      f.confidentPulseSamples > 0 &&
      f.cleanFraction >= config.minCleanFraction;

  /// The 0–100 score. The pulse part comes from the beat shape ranked
  /// against the player's [warmups] and [earlier] questions when the beats
  /// are good; otherwise from the mean SDK pulse against the calibration
  /// median, as before (SPEC.md §5.4, decision 63).
  ///
  /// Beats need at least [ScoringConfig.shapeMinRefs] good warm-ups. Earlier
  /// questions add to the comparison but can't stand in for them, so a turn
  /// whose warm-ups had no usable beats stays on one scale (the SDK mean)
  /// instead of switching once enough questions have piled up.
  ScoreBreakdown score(
    WindowFeatures f,
    Baseline base, {
    List<PulseShape> warmups = const [],
    List<PulseShape> earlier = const [],
  }) {
    final c = config;
    var note = shapeProblem(f.pulseShape);
    ShapeScore? shape;
    if (note == null) {
      final goodWarmups = [
        for (final r in warmups)
          if (shapeProblem(r) == null) r,
      ];
      if (goodWarmups.length < c.shapeMinRefs) {
        final n = goodWarmups.length;
        note = 'only $n warm-up${n == 1 ? '' : 's'} with beats';
      } else {
        shape = rankShape(f.pulseShape!, [
          ...goodWarmups,
          for (final r in earlier)
            if (shapeProblem(r) == null) r,
        ]);
      }
    }
    final zPulse =
        shape?.zPulse ??
        (f.meanPulse == null
            ? 0.0
            : _clamp01((f.meanPulse! - base.pulse) / c.pulseScaleBpm));
    final zBlink = blinkPart(f, base);
    final zExpr = _clamp01(f.exprPeakDelta / c.exprScale);
    final zHes = _clamp01(
      (f.hesitationS - base.latencyS - c.hesitationGraceS) / c.hesitationScaleS,
    );
    final raw = _clamp01(
      c.wPulse * zPulse +
          c.wBlink * zBlink +
          c.wExpr * zExpr +
          c.wHesitation * zHes,
    );
    final score = (100 * math.pow(raw, c.scoreExponent)).round().clamp(0, 100);
    return ScoreBreakdown(
      zPulse: zPulse,
      zBlink: zBlink,
      zExpr: zExpr,
      zHesitation: zHes,
      raw: raw,
      score: score,
      verdict: verdictFor(score, legitBelow: c.legitBelow, susFrom: c.susFrom),
      pulseMethod: shape == null ? PulseMethod.sdkMean : PulseMethod.beats,
      shape: shape,
      pulseNote: note,
    );
  }

  /// Plain-language reasons for "No clean read", from the validation codes
  /// actually seen in the window (SPEC.md §5.5).
  List<String> noCleanReadReasons(
    SignalLog log,
    QuestionTiming timing,
    String name,
  ) {
    final t0 = timing.tQ0;
    final t1 = timing.windowEnd(config.minWindowAfterQuestionMs);
    final reasons = <String>[];
    for (final (code, ms, hint) in log.validationIssues(t0, t1)) {
      if (ms < 800) continue;
      final text = describeIssue(code, ms, name, hint);
      if (text != null && !reasons.contains(text)) reasons.add(text);
      if (reasons.length == 3) break;
    }
    if (reasons.isEmpty) {
      reasons.add("The pulse signal was too weak to read on that one");
    }
    return reasons;
  }

  /// E4 heading for the biggest issue in the window.
  String noCleanReadTitle(SignalLog log, QuestionTiming timing) {
    final t1 = timing.windowEnd(config.minWindowAfterQuestionMs);
    for (final (code, ms, _) in log.validationIssues(timing.tQ0, t1)) {
      if (ms < 800) continue;
      switch (code) {
        case 'EXCESSIVE_MOTION':
          return 'Too much wiggle on that one';
        case 'TOO_DARK' || 'TOO_BRIGHT':
          return 'The light got in the way';
        case 'NO_FACE_FOUND' || 'MULTIPLE_FACES_FOUND':
          return 'Lost the face on that one';
        case 'FACE_TOO_FAR' || 'FACE_TOO_CLOSE' || 'FACE_SIZE_OUT_OF_RANGE':
          return 'Not quite the right distance';
        case 'FACE_NOT_CENTERED' ||
            'FACE_TOO_HIGH' ||
            'FACE_TOO_LOW' ||
            'FACE_NOT_FORWARD':
          return 'The face drifted out of the oval';
      }
    }
    return 'The meter couldn\'t get a read';
  }

  static String? describeIssue(String code, int ms, String name, String hint) {
    final secs = (ms / 1000).round();
    return switch (code) {
      'EXCESSIVE_MOTION' => '$name moved around a lot while answering',
      'NO_FACE_FOUND' =>
        "The camera lost $name's face for about $secs second${secs == 1 ? '' : 's'}",
      'MULTIPLE_FACES_FOUND' => 'More than one face was in the frame',
      'TOO_DARK' => "It was too dark to read $name's face",
      'TOO_BRIGHT' => 'Too much light behind $name',
      'FACE_TOO_FAR' => '$name was too far from the camera',
      'FACE_TOO_CLOSE' ||
      'FACE_SIZE_OUT_OF_RANGE' => '$name was too close to the camera',
      'FACE_NOT_CENTERED' ||
      'FACE_TOO_HIGH' ||
      'FACE_TOO_LOW' => "$name's face drifted out of the oval",
      'FACE_NOT_FORWARD' => '$name looked away from the phone',
      'FRAME_RATE_TOO_LOW' => 'The phone was lagging',
      'CAMERA_TUNING' => 'The camera was still adjusting',
      'NOT_RUNNING' => 'The vitals engine paused for a moment',
      _ => hint.isEmpty ? null : hint,
    };
  }
}

/// A live validation issue (E3, SPEC.md §2 and decision 69): a word or two
/// stamped on the camera, a friendly title and a fix.
class SignalIssue {
  const SignalIssue(this.code, this.stamp, this.title, this.fix);

  final String code;

  /// Stamped on the camera where the expression tag goes, so short enough
  /// to read at a glance at full size.
  final String stamp;

  /// The problem in a few more words, for VoiceOver and calibration hints.
  final String title;

  /// What to do about it, under the stamp.
  final String fix;

  /// Light-related issues get a "Light too low" style chip.
  bool get isLight => code == 'TOO_DARK' || code == 'TOO_BRIGHT';
  bool get isFace => code == 'NO_FACE_FOUND' || code == 'MULTIPLE_FACES_FOUND';

  /// Stamped when calibration is slow and no single problem stands out.
  static const stillCalibrating = SignalIssue(
    'STILL_CALIBRATING',
    'Hold steady',
    'Still calibrating',
    'Keep your face in the oval and hold the phone steady.',
  );

  /// Calibration's hint once a clean baseline is slow to come: the most
  /// common recent problem ([recent] as from `SignalLog.validationIssues`,
  /// commonest first), or [stillCalibrating].
  static SignalIssue forSlowCalibration(
    Iterable<(String, int, String)> recent,
  ) {
    for (final (code, _, _) in recent) {
      final issue = fromCode(code);
      if (issue != null) return issue;
    }
    return stillCalibrating;
  }

  static SignalIssue? fromCode(String? code) => switch (code) {
    null || 'OK' || 'CAMERA_TUNING' => null,
    'TOO_DARK' => const SignalIssue(
      'TOO_DARK',
      'Too dark',
      'Too dark in here',
      'Face a lamp or window.',
    ),
    'TOO_BRIGHT' => const SignalIssue(
      'TOO_BRIGHT',
      'Too bright',
      'Too bright behind you',
      'Turn away from the window or lamp.',
    ),
    'NO_FACE_FOUND' => const SignalIssue(
      'NO_FACE_FOUND',
      'No face',
      "Can't see a face",
      'Get your face inside the oval.',
    ),
    'MULTIPLE_FACES_FOUND' => const SignalIssue(
      'MULTIPLE_FACES_FOUND',
      'Too many faces',
      'Too many faces',
      'Only the hot seat in frame, please.',
    ),
    'FACE_TOO_FAR' => const SignalIssue(
      'FACE_TOO_FAR',
      'Move closer',
      'Move closer',
      'Bring the phone a little nearer.',
    ),
    'FACE_TOO_CLOSE' || 'FACE_SIZE_OUT_OF_RANGE' => const SignalIssue(
      'FACE_TOO_CLOSE',
      'Move back',
      'Move back a bit',
      'Hold the phone a little further away.',
    ),
    'FACE_NOT_CENTERED' ||
    'FACE_TOO_HIGH' ||
    'FACE_TOO_LOW' => const SignalIssue(
      'FACE_NOT_CENTERED',
      'Off center',
      'Center your face',
      'Line your face up with the oval.',
    ),
    'FACE_NOT_FORWARD' => const SignalIssue(
      'FACE_NOT_FORWARD',
      'Look here',
      'Look at the phone',
      'Face the camera straight on.',
    ),
    'EXCESSIVE_MOTION' => const SignalIssue(
      'EXCESSIVE_MOTION',
      'Hold still',
      'Hold still',
      'Rest your elbows or prop the phone up.',
    ),
    'FRAME_RATE_TOO_LOW' => const SignalIssue(
      'FRAME_RATE_TOO_LOW',
      'Lagging',
      'Phone is lagging',
      'Close other apps or let it cool down.',
    ),
    'CHEST_NOT_VISIBLE' => null,
    _ => SignalIssue(
      code,
      'Adjusting',
      'Adjusting the camera',
      'Hold still for a moment.',
    ),
  };
}
