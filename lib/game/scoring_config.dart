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
    this.blinkFreezeChance = 0.05,
    this.blinkChanceSpreads = 1.0,
    this.exprScale = 0.3,
    this.exprCategories = const ['surprise', 'fear', 'contempt', 'disgust'],
    this.exprSmile = 'happy',
    this.exprSmoothMs = 1000,
    this.hesitationScaleS = 3.0,
    this.hesitationGraceS = 1.0,
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
    this.calibMinChatMs = 15000,
    this.calibMaxWarmups = 3,
    this.calibWarmupMs = 12000,
    this.calibWarmupTalkingMs = 25000,
    this.calibMinConfidentPulseMs = 12000,
    this.calibMinFaceFraction = 0.8,
    this.calibHintAfterMs = 45000,
    this.traceClockJumpMs = 2000,
    this.traceResampleHz = 30,
    this.traceMaxGapMs = 300,
    this.beatMinSegmentMs = 4000,
    this.beatBandLowHz = 0.7,
    this.beatBandHighHz = 3.5,
    this.beatMinIbiMs = 333,
    this.beatMaxIbiMs = 1500,
    this.beatMinPeakFraction = 0.35,
    this.beatIbiMaxDeviation = 0.3,
    this.beatLookbackMs = 20000,
    this.beatMinCoverage = 0.6,
    this.beatSdkWindowMs = 12000,
    this.beatMaxSdkDiffBpm = 8,
    this.beatSdkMaxLagMs = 6000,
    this.shapePreMs = 5000,
    this.shapePreFallbackMs = 15000,
    this.shapePreMinCoverage = 0.5,
    this.shapeGridMs = 250,
    this.shapeSmoothMs = 3000,
    this.shapeDipMs = 6000,
    this.shapeMinRefs = 2,
    this.shapeZFree = 1.0,
    this.shapeZFull = 2.5,
    this.shapeRiseFloorBpm = 4,
    this.shapeSustainedFloorBpm = 3,
    this.shapeDipFloorBpm = 3,
    this.wShapeRise = 0.4,
    this.wShapeSustained = 0.4,
    this.wShapeDip = 0.2,
  });

  // --- Score weights (raw = Σ w·z, score = round(100 · raw^exponent)) ---
  final double wPulse;
  final double wBlink;
  final double wExpr;
  final double wHesitation;
  final double scoreExponent;

  // --- Feature normalization ---
  /// zPulse = (mean window pulse − basePulse) / this, when the heartbeat
  /// shape can't be used (SPEC.md decision 63).
  final double pulseScaleBpm;

  /// zBlink = (blinks − expected − chance) / (expected · this), where
  /// expected = base rate × window, never under [blinkMinBaselinePerMin],
  /// and chance is [blinkChanceSpreads] of the count's own random wobble.
  final double blinkRelativeScale;
  final double blinkMinBaselinePerMin;

  /// Blinks come at random, so a 15 s window's count wobbles by about its
  /// square root (Poisson) even when nothing changed. This many of those
  /// wobbles (also allowing for the baseline's own) are free.
  final double blinkChanceSpreads;

  /// A blink "freeze" sets zBlink to at least [blinkFreezeZ]: no blinks for
  /// so long that, at the player's own rate, a gap like it would turn up in
  /// the window by chance less than [blinkFreezeChance] of the time. Never
  /// shorter than [blinkFreezeMs], and only when the baseline is at least
  /// [blinkFreezeMinBaselinePerMin] (below that, long gaps are normal).
  final int blinkFreezeMs;
  final double blinkFreezeChance;
  final double blinkFreezeMinBaselinePerMin;
  final double blinkFreezeZ;

  /// zExpr = max over the window of (x[cat] − warm-up peak of x[cat]) / this,
  /// where x is the expression's score minus [exprSmile]'s.
  final double exprScale;

  /// SDK expression categories that count as a stress reaction.
  final List<String> exprCategories;

  /// A stress expression counts only by how far it's above this one, so a
  /// smile the SDK also scores as contempt (or a laugh as surprise) cancels
  /// out, and a tie goes to the smile.
  final String exprSmile;

  /// Moving-average width applied to expressions before taking the max, so a
  /// single noisy frame can't spike the score.
  final int exprSmoothMs;

  /// zHes = (hesitation − baseLatency − grace) / this.
  final double hesitationScaleS;

  /// Real questions take a little longer to think about than warm-ups, so
  /// this much extra pause is free.
  final double hesitationGraceS;
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

  /// Calibration chats through warm-ups for at least this long (one more
  /// warm-up if the answers were quick). The baseline blink rate and
  /// expression peaks come from the chat (people blink more talking than
  /// sitting still); a shorter chat falls back to the whole calibration.
  final int calibMinChatMs;
  final int calibMaxWarmups;

  /// A warm-up moves on this long after it's asked, unless the player is
  /// still talking; then it waits up to [calibWarmupTalkingMs]. Warm-ups ask
  /// for a sentence, so they can be compared with real answers.
  final int calibWarmupMs;
  final int calibWarmupTalkingMs;
  final int calibMinConfidentPulseMs;
  final double calibMinFaceFraction;

  /// After this long without a valid baseline, stamp a hint on the camera
  /// (SPEC.md decision 69).
  final int calibHintAfterMs;

  // --- Heartbeats from the pulse waveform (SPEC.md decision 63) ---
  /// A waveform batch whose SDK clock runs ahead of the wall clock by more
  /// than this starts a new clock mapping.
  final int traceClockJumpMs;

  /// The waveform is resampled to this rate before filtering.
  final double traceResampleHz;

  /// A gap longer than this between waveform samples splits the waveform.
  final int traceMaxGapMs;

  /// Waveform pieces shorter than this are too short to filter.
  final int beatMinSegmentMs;

  /// Band-pass filter edges (Hz): about 42 to 210 BPM.
  final double beatBandLowHz;
  final double beatBandHighHz;

  /// Allowed time between beats: 180 down to 40 BPM.
  final double beatMinIbiMs;
  final double beatMaxIbiMs;

  /// A peak lower than this fraction of the nearby peaks' median isn't a beat.
  final double beatMinPeakFraction;

  /// An interval further than this fraction from its neighbours' median is
  /// an artifact (a missed or extra beat) and isn't used.
  final double beatIbiMaxDeviation;

  /// Waveform before the question's start that goes into beat finding, for
  /// the pre-question level and so the filter has settled by then.
  final int beatLookbackMs;

  /// Beats must cover at least this fraction of a window to be scored.
  final double beatMinCoverage;

  /// Beat heart rate is checked against each SDK pulse reading over this
  /// span (the SDK's pulse is a 12 s average).
  final int beatSdkWindowMs;

  /// The beats are trusted only if their median difference from the SDK's
  /// pulse is at most this.
  final double beatMaxSdkDiffBpm;

  /// The SDK's pulse may arrive this much later than the beats it averages;
  /// the cross-check tries delays up to this, in 1 s steps.
  final int beatSdkMaxLagMs;

  // --- Pulse shape and the question-vs-question comparison ---
  /// The pre-question level is the mean beat heart rate over this span before
  /// the question starts, or over the fallback span if that's too gappy.
  final int shapePreMs;
  final int shapePreFallbackMs;
  final double shapePreMinCoverage;

  /// Beat heart rate is sampled on this grid and smoothed over this span
  /// (about one breath, so breathing's own pulse swing mostly averages out).
  final int shapeGridMs;
  final int shapeSmoothMs;

  /// The early slowdown is looked for in this span after the question ends.
  final int shapeDipMs;

  /// Fewest earlier answers (warm-ups and questions) to compare against.
  final int shapeMinRefs;

  /// A feature up to this many spreads above the player's usual is their
  /// normal wobble and counts for nothing...
  final double shapeZFree;

  /// ...and one this many spreads above it counts in full.
  final double shapeZFull;

  /// Smallest spread (BPM) used for each feature, so a player whose earlier
  /// answers were all alike doesn't turn a 1 BPM wobble into a spike.
  final double shapeRiseFloorBpm;
  final double shapeSustainedFloorBpm;
  final double shapeDipFloorBpm;

  /// How the three shape features make up zPulse (normalized to sum to 1).
  final double wShapeRise;
  final double wShapeSustained;
  final double wShapeDip;
}
