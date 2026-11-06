import 'dart:math' as math;

import 'scoring_config.dart';

/// The time between two heartbeats found in the pulse waveform.
class BeatInterval {
  const BeatInterval(this.startMs, this.endMs, {required this.accepted});

  /// Wall-clock times (ms) of the two beats.
  final double startMs;
  final double endMs;

  /// False if it looks like a missed or extra beat (SPEC.md decision 63).
  final bool accepted;

  double get ibiMs => endMs - startMs;
  double get bpm => 60000 / ibiMs;
}

/// Beat-by-beat heart rate: each accepted interval's rate holds from one beat
/// to the next, so averages over time weigh every moment equally.
class BeatSeries {
  BeatSeries(List<BeatInterval> intervals)
    : intervals = List.unmodifiable(intervals),
      _accepted = List.unmodifiable([
        for (final i in intervals)
          if (i.accepted) i,
      ]);

  static final empty = BeatSeries(const []);

  /// Every interval found, oldest first.
  final List<BeatInterval> intervals;
  final List<BeatInterval> _accepted;

  List<BeatInterval> get accepted => _accepted;

  /// Beats found (one more than the intervals in each unbroken piece).
  int get beatCount => intervals.length;

  /// Fraction of [t0, t1] covered by accepted intervals.
  double coverage(num t0, num t1) {
    if (t1 <= t0) return 0;
    var covered = 0.0;
    for (final i in _accepted) {
      covered += _overlap(i, t0, t1);
    }
    return (covered / (t1 - t0)).clamp(0.0, 1.0);
  }

  /// Time-weighted mean heart rate (BPM) over the covered parts of [t0, t1].
  double? meanBpm(num t0, num t1) {
    var weight = 0.0;
    var sum = 0.0;
    for (final i in _accepted) {
      final o = _overlap(i, t0, t1);
      if (o <= 0) continue;
      weight += o;
      sum += o * i.bpm;
    }
    return weight > 0 ? sum / weight : null;
  }

  /// Beat-to-beat variation over [t0, t1]: root mean square of the
  /// differences between back-to-back accepted intervals (ms), the same
  /// measure as the SDK's RMSSD. Null with fewer than 5 such pairs.
  double? rmssdMs(num t0, num t1) {
    var sum = 0.0;
    var n = 0;
    for (var k = 1; k < _accepted.length; k++) {
      final a = _accepted[k - 1];
      final b = _accepted[k];
      if (a.endMs != b.startMs || a.startMs < t0 || b.endMs > t1) continue;
      final d = b.ibiMs - a.ibiMs;
      sum += d * d;
      n++;
    }
    return n >= 5 ? math.sqrt(sum / n) : null;
  }

  /// Heart rate at [t], or null between accepted intervals.
  double? bpmAt(double t) {
    var lo = 0;
    var hi = _accepted.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final i = _accepted[mid];
      if (t < i.startMs) {
        hi = mid - 1;
      } else if (t >= i.endMs) {
        lo = mid + 1;
      } else {
        return i.bpm;
      }
    }
    return null;
  }

  /// Heart rate every [stepMs] from [t0] to [t1], each point the mean over
  /// [smoothMs] centred on it. Null where under half that span has beats.
  List<(double, double?)> smoothed(num t0, num t1, num stepMs, num smoothMs) {
    final half = smoothMs / 2;
    final out = <(double, double?)>[];
    for (var t = t0.toDouble(); t <= t1; t += stepMs) {
      if (coverage(t - half, t + half) < 0.5) {
        out.add((t, null));
      } else {
        out.add((t, meanBpm(t - half, t + half)));
      }
    }
    return out;
  }

  static double _overlap(BeatInterval i, num t0, num t1) {
    final a = math.max(i.startMs, t0.toDouble());
    final b = math.min(i.endMs, t1.toDouble());
    return b > a ? b - a : 0;
  }
}

/// Finds heartbeats in the SDK's pulse waveform. [points] are (wall-clock ms,
/// value, ok) in time order, as [SignalLog.traceIn] returns them.
///
/// 1. Split into unbroken pieces of good samples (no gap over
///    [ScoringConfig.traceMaxGapMs], validation OK).
/// 2. Resample each piece evenly and band-pass it (zero-phase Butterworth,
///    about 42–210 BPM) so only the heartbeat's rhythm is left.
/// 3. Each beat is a peak at least [ScoringConfig.beatMinIbiMs] after the
///    previous one and not much lower than its neighbours, timed between
///    samples by fitting a parabola through the top three.
/// 4. Intervals out of range, or far from their neighbours' median (a missed
///    or extra beat), are kept but marked not accepted.
BeatSeries detectBeats(List<(double, double, bool)> points, ScoringConfig c) {
  final intervals = <BeatInterval>[];
  for (final piece in _pieces(points, c)) {
    intervals.addAll(_beatsIn(piece, c));
  }
  return BeatSeries(intervals);
}

List<List<(double, double)>> _pieces(
  List<(double, double, bool)> points,
  ScoringConfig c,
) {
  final out = <List<(double, double)>>[];
  var current = <(double, double)>[];
  void close() {
    if (current.length > 1 &&
        current.last.$1 - current.first.$1 >= c.beatMinSegmentMs) {
      out.add(current);
    }
    current = [];
  }

  for (final (t, v, ok) in points) {
    if (!ok || !t.isFinite || !v.isFinite) {
      close();
      continue;
    }
    if (current.isNotEmpty) {
      final gap = t - current.last.$1;
      if (gap <= 0) continue;
      if (gap > c.traceMaxGapMs) close();
    }
    current.add((t, v));
  }
  close();
  return out;
}

List<BeatInterval> _beatsIn(List<(double, double)> piece, ScoringConfig c) {
  final fs = c.traceResampleHz;
  final dt = 1000 / fs;
  final start = piece.first.$1;
  final n = ((piece.last.$1 - start) / dt).floor() + 1;
  if (n < 8) return const [];

  // Even resampling by linear interpolation.
  final x = List<double>.filled(n, 0);
  var j = 0;
  for (var i = 0; i < n; i++) {
    final t = start + i * dt;
    while (j < piece.length - 2 && piece[j + 1].$1 < t) {
      j++;
    }
    final (ta, va) = piece[j];
    final (tb, vb) = piece[j + 1];
    final f = tb > ta ? ((t - ta) / (tb - ta)).clamp(0.0, 1.0) : 0.0;
    x[i] = va + (vb - va) * f;
  }

  final y = _bandPass(x, fs, c.beatBandLowHz, c.beatBandHighHz);

  // Peaks above zero, with a refractory period.
  final minGap = c.beatMinIbiMs / dt;
  final peaks = <int>[];
  for (var i = 1; i < n - 1; i++) {
    if (!(y[i] > 0 && y[i] > y[i - 1] && y[i] >= y[i + 1])) continue;
    if (peaks.isNotEmpty && i - peaks.last < minGap) {
      if (y[i] > y[peaks.last]) peaks[peaks.length - 1] = i;
      continue;
    }
    peaks.add(i);
  }

  // Drop small bumps: under a fraction of the median of the peaks within
  // 5 s. Peaks are in order, so the neighbours are a sliding range.
  final window = (5000 / dt).round();
  final kept = <int>[];
  var lo = 0;
  var hi = 0;
  for (final p in peaks) {
    while (peaks[lo] < p - window) {
      lo++;
    }
    while (hi < peaks.length && peaks[hi] <= p + window) {
      hi++;
    }
    final near = [for (var k = lo; k < hi; k++) y[peaks[k]]];
    if (y[p] >= c.beatMinPeakFraction * _median(near)) kept.add(p);
  }

  // Sub-sample timing from a parabola through the top three samples.
  final times = <double>[];
  for (final p in kept) {
    final a = y[p - 1];
    final b = y[p];
    final d = y[p + 1];
    final denom = a - 2 * b + d;
    final shift = denom.abs() < 1e-12
        ? 0.0
        : (0.5 * (a - d) / denom).clamp(-0.5, 0.5);
    times.add(start + (p + shift) * dt);
  }

  final ibis = [for (var i = 1; i < times.length; i++) times[i] - times[i - 1]];
  bool inRange(double ibi) => ibi >= c.beatMinIbiMs && ibi <= c.beatMaxIbiMs;
  final out = <BeatInterval>[];
  for (var i = 0; i < ibis.length; i++) {
    final ibi = ibis[i];
    final near = [
      for (
        var k = math.max(0, i - 5);
        k <= math.min(ibis.length - 1, i + 5);
        k++
      )
        if (inRange(ibis[k])) ibis[k],
    ];
    final ref = near.isEmpty ? double.nan : _median(near);
    final ok =
        inRange(ibi) &&
        near.length >= 3 &&
        (ibi - ref).abs() <= c.beatIbiMaxDeviation * ref;
    out.add(BeatInterval(times[i], times[i + 1], accepted: ok));
  }
  return out;
}

/// Zero-phase band-pass: a 2nd-order Butterworth high-pass and low-pass,
/// run forwards then backwards, with odd reflection at the ends so the
/// filter's start-up swing lands in the padding.
List<double> _bandPass(List<double> x, double fs, double lowHz, double highHz) {
  final n = x.length;
  final mean = x.reduce((a, b) => a + b) / n;
  final pad = math.min(n - 1, (1.5 * fs).round());
  final padded = <double>[
    for (var i = pad; i >= 1; i--) 2 * x[0] - x[i] - mean,
    for (final v in x) v - mean,
    for (var i = n - 2; i >= n - 1 - pad; i--) 2 * x[n - 1] - x[i] - mean,
  ];
  final hp = _Biquad.highPass(lowHz, fs);
  final lp = _Biquad.lowPass(highHz, fs);
  var y = lp.run(hp.run(padded));
  y = lp.run(hp.run(y.reversed.toList())).reversed.toList();
  return y.sublist(pad, pad + n);
}

/// RBJ audio-cookbook biquad, Q = 1/√2 (Butterworth).
class _Biquad {
  _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory _Biquad.lowPass(double f, double fs) {
    final w = 2 * math.pi * f / fs;
    final cw = math.cos(w);
    final alpha = math.sin(w) / math.sqrt2;
    final a0 = 1 + alpha;
    return _Biquad(
      (1 - cw) / 2 / a0,
      (1 - cw) / a0,
      (1 - cw) / 2 / a0,
      -2 * cw / a0,
      (1 - alpha) / a0,
    );
  }

  factory _Biquad.highPass(double f, double fs) {
    final w = 2 * math.pi * f / fs;
    final cw = math.cos(w);
    final alpha = math.sin(w) / math.sqrt2;
    final a0 = 1 + alpha;
    return _Biquad(
      (1 + cw) / 2 / a0,
      -(1 + cw) / a0,
      (1 + cw) / 2 / a0,
      -2 * cw / a0,
      (1 - alpha) / a0,
    );
  }

  final double b0, b1, b2, a1, a2;

  List<double> run(List<double> x) {
    final y = List<double>.filled(x.length, 0);
    var z1 = 0.0;
    var z2 = 0.0;
    for (var i = 0; i < x.length; i++) {
      final v = x[i];
      final out = b0 * v + z1;
      z1 = b1 * v - a1 * out + z2;
      z2 = b2 * v - a2 * out;
      y[i] = out;
    }
    return y;
  }
}

double _median(List<double> values) {
  if (values.isEmpty) return double.nan;
  final s = [...values]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}
