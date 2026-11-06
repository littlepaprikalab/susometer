/// The shape of one answer's heart rate, from individual beats (SPEC.md
/// decision 63). All values in BPM.
class PulseShape {
  const PulseShape({
    required this.preBpm,
    required this.meanBpm,
    required this.rise,
    required this.sustained,
    required this.dip,
    required this.coverage,
    required this.sdkDiffBpm,
  });

  /// The player's level just before the question started.
  final double preBpm;

  /// Mean over the scored window.
  final double meanBpm;

  /// Highest smoothed rate in the window, above [preBpm].
  final double rise;

  /// [meanBpm] above [preBpm]: how much the whole answer ran high.
  final double sustained;

  /// How far the smoothed rate fell below [preBpm] in the first seconds after
  /// the question ended (an orienting slowdown). Null if there were no beats
  /// then.
  final double? dip;

  /// Fraction of the window with accepted beats.
  final double coverage;

  /// Median difference between beat heart rate and the SDK's own pulse
  /// readings over the window, or null if they couldn't be compared.
  final double? sdkDiffBpm;
}

/// How one answer's [PulseShape] ranks against the player's earlier answers.
/// Each part is 0..1: 0 at or below the player's usual, 1 at
/// [ScoringConfig.shapeZFull] spreads above it.
class ShapeScore {
  const ShapeScore({
    required this.rise,
    required this.sustained,
    required this.dip,
    required this.refs,
    required this.zPulse,
  });

  final double rise;
  final double sustained;
  final double dip;

  /// How many earlier answers it was compared with.
  final int refs;

  /// The weighted mix that replaces the SDK-mean zPulse.
  final double zPulse;
}

/// Where a score's pulse part came from.
enum PulseMethod {
  /// Mean SDK pulse against the calibration median (the original formula).
  sdkMean,

  /// Beat-by-beat shape, ranked against the player's earlier answers.
  beats,
}
