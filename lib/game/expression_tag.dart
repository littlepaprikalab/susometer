import 'dart:math' as math;

/// Turns SmartSpectra's per-frame expression scores into the #tag stamped
/// on the camera.
///
/// The SDK gives no single label, only a score per expression, so the tag
/// is whichever of the [labels] scores highest. Scores arrive about 10 times
/// a second and close ones trade places, so the tagger:
///
/// - smooths each score over about [smoothMs],
/// - changes the tag only once a new leader has held for [holdMs],
/// - brings up a tag only when it leads the runner-up by [minMargin], so a
///   tie never shows an arbitrary expression, except that a close call
///   between a happier and a less happy expression goes to the happier one
///   (see [positivity]): the SDK often scores a smile as contempt too, and
///   a tie there shouldn't stamp the player #contempt,
/// - hides it when nothing scores at least [minScore], and drops it after
///   [lostMs] without a usable face or without a fresh expression sample
///   (none for over [staleMs]).
///
/// This is the SDK's raw reading, not compared to the player's normal (the
/// score does that), so it's only for show. O(1) per snapshot, no
/// allocation: it runs on every snapshot of every turn.
class ExpressionTagger {
  ExpressionTagger({
    this.smoothMs = 600,
    this.holdMs = 700,
    this.minScore = 0.3,
    this.minMargin = 0.05,
    this.lostMs = 1000,
    this.staleMs = 3000,
  });

  /// The SDK categories that can become a tag, as the bridge names them
  /// (PresageBridge.expressionName). Anything else the bridge may send
  /// ("unspecified", "unknown7") is ignored.
  static const labels = [
    'angry',
    'contempt',
    'disgust',
    'fear',
    'happy',
    'neutral',
    'sad',
    'surprise',
  ];

  /// How positive each expression is, for close calls: happy, then neutral
  /// and surprise, then the rest. The score's stress expressions are
  /// cancelled by a smile the same way (ScoringConfig.exprSmile).
  static int positivity(String label) => switch (label) {
    'happy' => 2,
    'neutral' || 'surprise' => 1,
    _ => 0,
  };

  final int smoothMs;
  final int holdMs;
  final double minScore;
  final double minMargin;
  final int lostMs;
  final int staleMs;

  /// The expression to show, or null for none.
  String? get tag => _shown;

  final List<double> _avg = List<double>.filled(labels.length, 0);
  bool _primed = false;
  int? _lastMs;
  String? _shown;
  bool _hasPending = false;
  String? _pending;
  int _pendingSinceMs = 0;
  int? _lostSinceMs;

  /// Feeds one snapshot taken at [tMs]. [faceOk] is false while there's no
  /// usable face (SmartSpectra not running, or its validation not OK).
  /// [exprAtMs] is when the bridge last got a new expression sample, if it
  /// says. Returns true when [tag] changed.
  bool add(
    int tMs,
    Map<String, double> expr, {
    required bool faceOk,
    int? exprAtMs,
  }) {
    final before = _shown;
    final last = _lastMs;
    // A wall clock that steps back: restart the timing, keep the averages.
    if (last != null && tMs < last) {
      _lastMs = null;
      _pendingSinceMs = tMs;
      final since = _lostSinceMs;
      if (since != null && tMs < since) _lostSinceMs = tMs;
    }
    final stale = exprAtMs != null && tMs - exprAtMs > staleMs;
    if (!faceOk || stale || !_hasKnown(expr)) {
      final since = _lostSinceMs ??= tMs;
      if (tMs - since >= lostMs) _forget();
      return _shown != before;
    }
    _lostSinceMs = null;

    final prev = _lastMs;
    _lastMs = tMs;
    if (!_primed) {
      for (var i = 0; i < labels.length; i++) {
        _avg[i] = expr[labels[i]] ?? 0;
      }
      _primed = true;
    } else if (prev != null) {
      // (With no previous time, the clock just stepped back: this frame only
      // restarts the timing.)
      final dt = (tMs - prev).clamp(0, 1000);
      final a = 1 - math.exp(-dt / smoothMs);
      for (var i = 0; i < labels.length; i++) {
        _avg[i] += a * ((expr[labels[i]] ?? 0) - _avg[i]);
      }
    }

    var lead = -1;
    var second = -1;
    for (var i = 0; i < labels.length; i++) {
      if (lead < 0 || _avg[i] > _avg[lead]) {
        second = lead;
        lead = i;
      } else if (second < 0 || _avg[i] > _avg[second]) {
        second = i;
      }
    }
    final best = _avg[lead];
    final String? candidate;
    if (best < minScore) {
      candidate = null;
    } else if (best - _avg[second] >= minMargin) {
      candidate = labels[lead];
    } else {
      final a = positivity(labels[lead]);
      final b = positivity(labels[second]);
      if (a != b) {
        // A close call between a happier and a less happy expression: the
        // happier one, so a smile also scored as contempt reads as a smile.
        candidate = a > b ? labels[lead] : labels[second];
      } else {
        // Otherwise which of the two leads is arbitrary, so it never brings
        // up a tag. A tag already shown stays while it's one of them, rather
        // than blinking off and on as the gap hovers at the margin.
        final shown = _shown;
        candidate = shown == labels[lead] || shown == labels[second]
            ? shown
            : null;
      }
    }

    if (candidate == _shown) {
      _hasPending = false;
    } else if (!_hasPending || candidate != _pending) {
      _hasPending = true;
      _pending = candidate;
      _pendingSinceMs = tMs;
    } else if (tMs - _pendingSinceMs >= holdMs) {
      _shown = candidate;
      _hasPending = false;
    }
    return _shown != before;
  }

  /// Forgets everything. The controller calls this whenever a measurement
  /// starts or stops, so one player's tag never shows for the next.
  void reset() {
    _forget();
    _lostSinceMs = null;
  }

  static bool _hasKnown(Map<String, double> expr) {
    if (expr.isEmpty) return false;
    for (final label in labels) {
      if (expr.containsKey(label)) return true;
    }
    return false;
  }

  void _forget() {
    _avg.fillRange(0, _avg.length, 0);
    _primed = false;
    _lastMs = null;
    _shown = null;
    _hasPending = false;
    _pending = null;
  }
}
