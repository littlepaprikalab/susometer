/// Game data. Everything here lives in memory only (SPEC.md §8).
library;

import 'pulse_shape.dart';

export 'pulse_shape.dart';

enum GameMode { party, solo }

enum DeckKind { mild, spicy }

enum Verdict { legit, hmm, sus }

/// A room vote on Call it! (SPEC.md §5.6). Unset means abstain.
enum Vote { legit, sus }

extension VerdictText on Verdict {
  String get label => switch (this) {
    Verdict.legit => 'Legit',
    Verdict.hmm => 'Hmm…',
    Verdict.sus => 'Sus!',
  };
}

class Player {
  Player({required this.id, required this.name});

  final String id;
  final String name;

  String get initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }
}

/// The player's normal, measured during calibration (SPEC.md §5.2).
class Baseline {
  const Baseline({
    required this.pulse,
    required this.blinkRatePerMin,
    required this.expr,
    required this.latencyS,
    required this.confidentPulseMs,
    required this.faceFraction,
    this.talkingBlinkRatePerMin,
  });

  /// Median confident pulse (BPM).
  final double pulse;
  final double blinkRatePerMin;

  /// Mean probability per expression category (0..1), from the chat phase.
  final Map<String, double> expr;

  /// Median warm-up answer latency (s).
  final double latencyS;
  final int confidentPulseMs;
  final double faceFraction;

  /// Blink rate while chatting, for the Proof Panel.
  final double? talkingBlinkRatePerMin;
}

/// Features of one question window, before weighting.
class WindowFeatures {
  const WindowFeatures({
    required this.meanPulse,
    required this.blinkRatePerMin,
    required this.blinkFreeze,
    required this.exprPeakDelta,
    required this.exprPeakCategory,
    required this.hesitationS,
    required this.cleanFraction,
    required this.confidentPulseSamples,
    this.pulseShape,
  });

  final double? meanPulse;
  final double blinkRatePerMin;
  final bool blinkFreeze;
  final double exprPeakDelta;
  final String? exprPeakCategory;
  final double hesitationS;
  final double cleanFraction;
  final int confidentPulseSamples;

  /// Beat-by-beat heart-rate shape, if beats could be found in the window.
  final PulseShape? pulseShape;
}

class ScoreBreakdown {
  const ScoreBreakdown({
    required this.zPulse,
    required this.zBlink,
    required this.zExpr,
    required this.zHesitation,
    required this.raw,
    required this.score,
    required this.verdict,
    this.pulseMethod = PulseMethod.sdkMean,
    this.shape,
    this.pulseNote,
  });

  final double zPulse;
  final double zBlink;
  final double zExpr;
  final double zHesitation;
  final double raw;
  final int score;
  final Verdict verdict;

  /// How [zPulse] was worked out.
  final PulseMethod pulseMethod;

  /// The beat-shape ranking, when [pulseMethod] is [PulseMethod.beats].
  final ShapeScore? shape;

  /// Why the beats weren't used, for the Proof Panel.
  final String? pulseNote;
}

/// Timing markers for one question (SPEC.md §5.3), wall-clock ms.
class QuestionTiming {
  const QuestionTiming({
    required this.tQ0,
    required this.tQ1,
    required this.tA0,
    required this.tA1,
    required this.hesitationFromMs,
  });

  final int tQ0;
  final int tQ1;
  final int? tA0;
  final int tA1;

  /// Where hesitation is measured from: tQ1, or the end of the host's
  /// "{name}, your answer?" prompt when the question ended on silence.
  final int hesitationFromMs;

  int windowEnd(int minAfterQuestionMs) {
    final minEnd = tQ1 + minAfterQuestionMs;
    return tA1 > minEnd ? tA1 : minEnd;
  }
}

/// Outcome of one question.
class QuestionResult {
  QuestionResult({
    required this.index,
    required this.question,
    required this.answer,
    required this.timing,
    this.features,
    this.breakdown,
    this.noCleanReadReasons = const [],
    this.noCleanReadTitle,
    this.pulseTrace = const [],
    this.traceEndMs,
    this.basePulse,
    this.baseBlinkRate,
    this.skipped = false,
  });

  final int index;
  final String question;
  final String answer;
  final QuestionTiming? timing;
  final WindowFeatures? features;
  final ScoreBreakdown? breakdown;
  final List<String> noCleanReadReasons;

  /// E4 heading, e.g. "Too much wiggle on that one".
  final String? noCleanReadTitle;

  /// Confident pulse readings (time ms, BPM) across the scored window, from
  /// the question's start to [traceEndMs], for the Verdict and Replay charts.
  /// Kept in memory only, like everything else.
  final List<(int, double)> pulseTrace;

  /// End of the scored window (ms).
  final int? traceEndMs;
  final double? basePulse;
  final double? baseBlinkRate;
  final bool skipped;

  /// Votes cast on Call it!, keyed by voter player id.
  final Map<String, Vote> votes = {};

  bool get scored => breakdown != null && !skipped;
  int? get score => breakdown?.score;
  Verdict? get verdict => breakdown?.verdict;

  /// Pulse change vs baseline (BPM), for the stat tiles.
  double? get pulseDelta {
    final mean = features?.meanPulse;
    final base = basePulse;
    if (mean == null || base == null) return null;
    return mean - base;
  }

  /// Blink rate change vs baseline (fraction, e.g. 0.41 = +41%).
  double? get blinkDeltaFraction {
    final rate = features?.blinkRatePerMin;
    final base = baseBlinkRate;
    if (rate == null || base == null || base <= 0) return null;
    return (rate - base) / base;
  }
}

/// One player's turn.
class PlayerTurn {
  PlayerTurn(this.player);

  final Player player;
  Baseline? baseline;

  /// Timing of each answered warm-up, so its pulse shape can be a reference
  /// for this player's questions (SPEC.md decision 63).
  List<QuestionTiming> warmupTimings = const [];
  bool skipped = false;
  final List<QuestionResult> results = [];

  List<QuestionResult> get scored => results.where((r) => r.scored).toList();

  double? get averageScore {
    final s = scored;
    if (s.isEmpty) return null;
    return s.map((r) => r.score!).reduce((a, b) => a + b) / s.length;
  }

  int get questionsPlayed => results.where((r) => !r.skipped).length;
}

Verdict verdictFor(int score, {required int legitBelow, required int susFrom}) {
  if (score >= susFrom) return Verdict.sus;
  if (score < legitBelow) return Verdict.legit;
  return Verdict.hmm;
}
