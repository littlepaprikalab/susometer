import 'dart:math' as math;

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
    final pulses = log.confidentPulse(start, end);
    if (pulses.isEmpty) return null;
    final chatExpr = log.exprMean(quietEnd, end);
    final latencies = warmupLatenciesS.where((l) => l >= 0).toList();
    return Baseline(
      pulse: median(pulses.map((p) => p.bpm).toList()),
      blinkRatePerMin: log.blinkRatePerMin(start, end),
      expr: chatExpr.isNotEmpty ? chatExpr : log.exprMean(start, end),
      latencyS: latencies.isEmpty
          ? config.defaultBaseLatencyS
          : median(latencies),
      confidentPulseMs: log.confidentCoverageMs(start, end),
      faceFraction: log.faceFraction(start, end),
      talkingBlinkRatePerMin: end > quietEnd
          ? log.blinkRatePerMin(quietEnd, end)
          : null,
    );
  }

  /// Valid once there are ≥ 12 s of confident pulse and the face was present
  /// ≥ 80% of the time (SPEC.md §5.2).
  bool baselineValid(Baseline? b) =>
      b != null &&
      b.confidentPulseMs >= config.calibMinConfidentPulseMs &&
      b.faceFraction >= config.calibMinFaceFraction;

  WindowFeatures features(SignalLog log, QuestionTiming timing, Baseline base) {
    final t0 = timing.tQ0;
    final t1 = timing.windowEnd(config.minWindowAfterQuestionMs);
    final pulses = log.confidentPulse(t0, t1);
    final meanPulse = pulses.isEmpty
        ? null
        : pulses.map((p) => p.bpm).reduce((a, b) => a + b) / pulses.length;
    final (peak, cat) = log.exprPeakDelta(
      t0,
      t1,
      base.expr,
      config.exprCategories,
      config.exprSmoothMs,
    );
    final answerStart = timing.tA0 ?? timing.tA1;
    final hesitation =
        math.max(0, answerStart - timing.hesitationFromMs) / 1000;
    return WindowFeatures(
      meanPulse: meanPulse,
      blinkRatePerMin: log.blinkRatePerMin(t0, t1),
      blinkFreeze: log.blinkFreeze(t0, t1, config.blinkFreezeMs),
      exprPeakDelta: peak,
      exprPeakCategory: cat,
      hesitationS: hesitation.toDouble(),
      cleanFraction: log.cleanFraction(t0, t1),
      confidentPulseSamples: pulses.length,
    );
  }

  /// Confidence gate (SPEC.md §5.5): never fake a verdict.
  bool isClean(WindowFeatures f) =>
      f.meanPulse != null &&
      f.confidentPulseSamples > 0 &&
      f.cleanFraction >= config.minCleanFraction;

  ScoreBreakdown score(WindowFeatures f, Baseline base) {
    final c = config;
    final zPulse = f.meanPulse == null
        ? 0.0
        : _clamp01((f.meanPulse! - base.pulse) / c.pulseScaleBpm);
    final blinkBase = math.max(base.blinkRatePerMin, c.blinkMinBaselinePerMin);
    var zBlink = _clamp01(
      ((f.blinkRatePerMin - base.blinkRatePerMin) / blinkBase) /
          c.blinkRelativeScale,
    );
    if (f.blinkFreeze &&
        base.blinkRatePerMin >= c.blinkFreezeMinBaselinePerMin) {
      zBlink = math.max(zBlink, c.blinkFreezeZ);
    }
    final zExpr = _clamp01(f.exprPeakDelta / c.exprScale);
    final zHes = _clamp01((f.hesitationS - base.latencyS) / c.hesitationScaleS);
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

/// Friendly title and fix for a live validation issue (E3 banner, SPEC.md §2).
class SignalIssue {
  const SignalIssue(this.code, this.title, this.fix);

  final String code;
  final String title;
  final String fix;

  /// Light-related issues get a "Light too low" style chip.
  bool get isLight => code == 'TOO_DARK' || code == 'TOO_BRIGHT';
  bool get isFace => code == 'NO_FACE_FOUND' || code == 'MULTIPLE_FACES_FOUND';

  static SignalIssue? fromCode(String? code) => switch (code) {
    null || 'OK' || 'CAMERA_TUNING' => null,
    'TOO_DARK' => const SignalIssue(
      'TOO_DARK',
      'Too dark in here',
      'Face a lamp or window. Reading paused.',
    ),
    'TOO_BRIGHT' => const SignalIssue(
      'TOO_BRIGHT',
      'Too bright behind you',
      'Turn away from the window or lamp.',
    ),
    'NO_FACE_FOUND' => const SignalIssue(
      'NO_FACE_FOUND',
      "Can't see a face",
      'Get your face inside the oval.',
    ),
    'MULTIPLE_FACES_FOUND' => const SignalIssue(
      'MULTIPLE_FACES_FOUND',
      'Too many faces',
      'Only the hot seat in frame, please.',
    ),
    'FACE_TOO_FAR' => const SignalIssue(
      'FACE_TOO_FAR',
      'Move closer',
      'Bring the phone a little nearer.',
    ),
    'FACE_TOO_CLOSE' || 'FACE_SIZE_OUT_OF_RANGE' => const SignalIssue(
      'FACE_TOO_CLOSE',
      'Move back a bit',
      'Hold the phone a little further away.',
    ),
    'FACE_NOT_CENTERED' ||
    'FACE_TOO_HIGH' ||
    'FACE_TOO_LOW' => const SignalIssue(
      'FACE_NOT_CENTERED',
      'Center your face',
      'Line your face up with the oval.',
    ),
    'FACE_NOT_FORWARD' => const SignalIssue(
      'FACE_NOT_FORWARD',
      'Look at the phone',
      'Face the camera straight on.',
    ),
    'EXCESSIVE_MOTION' => const SignalIssue(
      'EXCESSIVE_MOTION',
      'Hold still',
      'Rest your elbows or prop the phone up.',
    ),
    'FRAME_RATE_TOO_LOW' => const SignalIssue(
      'FRAME_RATE_TOO_LOW',
      'Phone is lagging',
      'Close other apps or let it cool down.',
    ),
    'CHEST_NOT_VISIBLE' => null,
    _ => SignalIssue(code, 'Adjusting the camera', 'Hold still for a moment.'),
  };
}
