/// Every scoring and calibration constant in one place (SPEC.md §5), so they
/// can be tuned after play-testing without touching the logic.
class ScoringConfig {
  const ScoringConfig({
    this.wPulse = 0.45,
    this.wBlink = 0.25,
    this.wExpr = 0.15,
    this.wHesitation = 0.15,
    this.scoreExponent = 0.8,
    this.pulseScaleBpm = 15,
    this.blinkRelativeScale = 0.6,
    this.blinkMinBaselinePerMin = 6,
    this.blinkFreezeMs = 6000,
    this.blinkFreezeMinBaselinePerMin = 12,
    this.blinkFreezeZ = 0.6,
    this.exprScale = 0.4,
    this.exprCategories = const ['surprise', 'fear', 'contempt', 'disgust'],
    this.exprSmoothMs = 500,
    this.hesitationScaleS = 3.0,
    this.defaultBaseLatencyS = 1.0,
    this.pulseConfMin = 0.4,
    this.pulseMinBpm = 30,
    this.pulseMaxBpm = 220,
    this.pulseFreshMs = 3000,
    this.pulseMaxGapMs = 2000,
    this.minWindowAfterQuestionMs = 12000,
    this.minCleanFraction = 0.6,
    this.legitBelow = 35,
    this.susFrom = 60,
    this.calibQuietMs = 20000,
    this.calibMinWarmups = 2,
    this.calibMaxWarmups = 3,
    this.calibMinConfidentPulseMs = 12000,
    this.calibMinFaceFraction = 0.8,
    this.calibHintAfterMs = 45000,
  });

  // --- Score weights (raw = Σ w·z, score = round(100 · raw^exponent)) ---
  final double wPulse;
  final double wBlink;
  final double wExpr;
  final double wHesitation;
  final double scoreExponent;

  // --- Feature normalization ---
  /// zPulse = (mean window pulse − basePulse) / this.
  final double pulseScaleBpm;

  /// zBlink = ((rate − base) / max(base, blinkMinBaselinePerMin)) / this.
  final double blinkRelativeScale;
  final double blinkMinBaselinePerMin;

  /// A blink "freeze" (no blinks for this long, when the baseline rate is at
  /// least [blinkFreezeMinBaselinePerMin]) sets zBlink to at least
  /// [blinkFreezeZ].
  final int blinkFreezeMs;
  final double blinkFreezeMinBaselinePerMin;
  final double blinkFreezeZ;

  /// zExpr = max over the window of (p[cat] − baseExpr[cat]) / this.
  final double exprScale;

  /// SDK expression categories that count as a stress reaction.
  final List<String> exprCategories;

  /// Moving-average width applied to expressions before taking the max, so a
  /// single noisy frame can't spike the score.
  final int exprSmoothMs;

  /// zHes = (hesitation − baseLatency) / this.
  final double hesitationScaleS;
  final double defaultBaseLatencyS;

  // --- Confidence gating (SPEC.md §5.5) ---
  /// Pulse samples below this confidence (0..1) are ignored. The SDK marks
  /// pulse `stable` at 40% and above.
  final double pulseConfMin;

  /// Pulse readings outside this range (BPM) are treated as glitches and
  /// dropped, so one bad value can't skew a score or a chart's scale.
  final double pulseMinBpm;
  final double pulseMaxBpm;

  /// A confident pulse value counts as current for this long.
  final int pulseFreshMs;

  /// When adding up "seconds of confident pulse", one sample covers at most
  /// this gap to the previous one.
  final int pulseMaxGapMs;

  /// Window = [tQ0, max(tA1, tQ1 + this)].
  final int minWindowAfterQuestionMs;

  /// Below this fraction of the window with a present face and a fresh
  /// confident pulse, the result is "No clean read".
  final double minCleanFraction;

  // --- Verdict bands ---
  final int legitBelow;
  final int susFrom;

  // --- Calibration (SPEC.md §5.2) ---
  final int calibQuietMs;
  final int calibMinWarmups;
  final int calibMaxWarmups;
  final int calibMinConfidentPulseMs;
  final double calibMinFaceFraction;

  /// After this long without a valid baseline, show the E3-style hints.
  final int calibHintAfterMs;
}
