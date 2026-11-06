import '../presage/presage_models.dart';
import 'scoring_config.dart';

class PulsePoint {
  const PulsePoint(this.tMs, this.bpm, this.conf, {required this.validOk});

  final int tMs;
  final double bpm;
  final double conf;

  /// Validation was OK and the pipeline was running when the sample arrived.
  final bool validOk;
}

/// One stream snapshot (~10 Hz): face presence and pulse freshness.
class FaceFrame {
  const FaceFrame({
    required this.tMs,
    required this.running,
    required this.facePresent,
    required this.validationCode,
    required this.validationHint,
    required this.pulseFresh,
  });

  final int tMs;
  final bool running;
  final bool facePresent;
  final String? validationCode;
  final String? validationHint;
  final bool pulseFresh;

  bool get clean => running && facePresent && pulseFresh;
}

class ExprPoint {
  const ExprPoint(this.tMs, this.p);

  final int tMs;
  final Map<String, double> p;
}

/// One pulse-waveform sample (SPEC.md decision 63). [tsUs] is the SDK's own
/// clock; [SignalLog.traceIn] maps it to wall-clock time.
class TracePoint {
  const TracePoint(
    this.tsUs,
    this.value, {
    required this.ok,
    required this.clock,
  });

  final int tsUs;
  final double value;

  /// Validation was OK and the pipeline was running when it arrived (the
  /// same gate as [PulsePoint.validOk]).
  final bool ok;

  /// Which SDK-clock mapping applies (a new one starts if the SDK clock
  /// jumps, e.g. after a restart).
  final int clock;
}

class TalkEdge {
  const TalkEdge(this.tMs, this.talking);

  final int tMs;
  final bool talking;
}

/// Time series for the current player's turn, built from bridge snapshots.
/// In memory only, cleared at the start of every turn, and capped in size.
class SignalLog {
  SignalLog({
    this.config = const ScoringConfig(),
    this.maxFrames = 30000,
    this.maxTracePoints = 60000,
  });

  final ScoringConfig config;
  final int maxFrames;

  /// About 33 minutes of waveform at 30 Hz: a whole turn.
  final int maxTracePoints;

  final List<PulsePoint> pulse = [];
  final List<int> blinks = [];
  final List<FaceFrame> frames = [];
  final List<ExprPoint> expr = [];
  final List<TalkEdge> talkEdges = [];
  final List<TracePoint> trace = [];

  /// Wall-clock ms minus SDK-clock ms, one entry per [TracePoint.clock].
  final List<double> _traceOffsetMs = [];
  int? _lastTraceTsUs;
  int? _lastTraceAtMs;

  PresageSample? latest;
  int? _lastPulseAt;
  int? _lastConfidentPulseMs;

  void clear() {
    pulse.clear();
    blinks.clear();
    frames.clear();
    expr.clear();
    talkEdges.clear();
    trace.clear();
    _traceOffsetMs.clear();
    _lastTraceTsUs = null;
    _lastTraceAtMs = null;
    latest = null;
    _lastPulseAt = null;
    _lastConfidentPulseMs = null;
  }

  static const _faceMissingCodes = {
    'NO_FACE_FOUND',
    'MULTIPLE_FACES_FOUND',
    'CAMERA_TUNING',
  };

  void add(PresageSample s) {
    latest = s;
    final running = s.status == PresageStatus.running;
    final validation = s.validation;
    final validOk = running && (validation?.isOk ?? false);

    if (s.pulse != null &&
        s.pulseAtMs != null &&
        s.pulseAtMs != _lastPulseAt &&
        s.pulse! >= config.pulseMinBpm &&
        s.pulse! <= config.pulseMaxBpm) {
      _lastPulseAt = s.pulseAtMs;
      final point = PulsePoint(
        s.pulseAtMs!,
        s.pulse!,
        s.pulseConf ?? 0,
        validOk: validOk,
      );
      pulse.add(point);
      if (_isConfident(point)) _lastConfidentPulseMs = point.tMs;
    }

    for (final e in s.events) {
      switch (e.type) {
        case PresageEdgeType.blink:
          blinks.add(e.tMs);
        case PresageEdgeType.talkStart:
          talkEdges.add(TalkEdge(e.tMs, true));
        case PresageEdgeType.talkEnd:
          talkEdges.add(TalkEdge(e.tMs, false));
      }
    }

    if (s.expr.isNotEmpty) expr.add(ExprPoint(s.tMs, s.expr));
    _addTrace(s, validOk);

    final last = _lastConfidentPulseMs;
    frames.add(
      FaceFrame(
        tMs: s.tMs,
        running: running,
        facePresent:
            running &&
            validation != null &&
            !_faceMissingCodes.contains(validation.code),
        validationCode: validation?.code,
        validationHint: validation?.hint,
        pulseFresh: last != null && s.tMs - last <= config.pulseFreshMs,
      ),
    );
    _trim();
  }

  /// Stores waveform samples with their SDK timestamps. The SDK clock is
  /// mapped to wall-clock time by the smallest delay seen between a sample's
  /// SDK time and the snapshot that carried it: delays only ever add to the
  /// true offset, so the minimum is the best estimate, and every sample on
  /// the same clock uses the latest one (so a first batch that arrived late
  /// is corrected once the next ones show the real delay).
  ///
  /// A new mapping starts only if the SDK clock itself jumps: it goes back
  /// while the wall clock doesn't (a restart), or its next sample is further
  /// ahead of the previous one than the wall clock moved, by over
  /// [ScoringConfig.traceClockJumpMs]. Samples that are simply old, with the
  /// same offset, are dropped as repeats.
  void _addTrace(PresageSample s, bool ok) {
    if (s.traceSamples.isEmpty) return;
    final samples = [...s.traceSamples]
      ..sort((a, b) => a.tsUs.compareTo(b.tsUs));
    final newest = samples.last.tsUs;
    final d = s.tMs - newest / 1000;
    final last = _lastTraceTsUs;
    final lastAt = _lastTraceAtMs;
    final current = _traceOffsetMs.isEmpty ? null : _traceOffsetMs.last;
    final jump = config.traceClockJumpMs;
    final wentBack = last != null && newest < last;
    final ahead = last == null || lastAt == null || wentBack
        ? 0.0
        : (samples.first.tsUs - last) / 1000 - (s.tMs - lastAt);
    if (current == null || (wentBack && d > current + jump) || ahead > jump) {
      _traceOffsetMs.add(d);
      _lastTraceTsUs = null;
    } else if (d < current) {
      _traceOffsetMs[_traceOffsetMs.length - 1] = d;
    }
    _lastTraceAtMs = s.tMs;
    final clock = _traceOffsetMs.length - 1;
    for (final p in samples) {
      final prev = _lastTraceTsUs;
      if (prev != null && p.tsUs <= prev) continue;
      _lastTraceTsUs = p.tsUs;
      trace.add(TracePoint(p.tsUs, p.value, ok: ok, clock: clock));
    }
    if (trace.length > maxTracePoints) {
      trace.removeRange(0, trace.length - maxTracePoints);
    }
  }

  /// Waveform samples whose wall-clock time is in [t0, t1], oldest first, as
  /// (time ms, value, ok).
  List<(double, double, bool)> traceIn(int t0, int t1) {
    final out = <(double, double, bool)>[];
    for (final p in trace) {
      final t = p.tsUs / 1000 + _traceOffsetMs[p.clock];
      if (t >= t0 && t <= t1) out.add((t, p.value, p.ok));
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  void _trim() {
    if (frames.length > maxFrames) {
      frames.removeRange(0, frames.length - maxFrames);
    }
    if (expr.length > maxFrames) expr.removeRange(0, expr.length - maxFrames);
    if (pulse.length > maxFrames) {
      pulse.removeRange(0, pulse.length - maxFrames);
    }
    if (blinks.length > maxFrames) {
      blinks.removeRange(0, blinks.length - maxFrames);
    }
    if (talkEdges.length > maxFrames) {
      talkEdges.removeRange(0, talkEdges.length - maxFrames);
    }
  }

  bool _isConfident(PulsePoint p) => p.validOk && p.conf >= config.pulseConfMin;

  // ---------------------------------------------------------------------------
  // Window queries. Windows are [t0, t1] in wall-clock ms.

  List<PulsePoint> confidentPulse(int t0, int t1) => [
    for (final p in pulse)
      if (p.tMs >= t0 && p.tMs <= t1 && _isConfident(p)) p,
  ];

  /// Milliseconds "covered" by confident pulse samples: each sample covers the
  /// gap since the previous confident one, capped at [ScoringConfig.pulseMaxGapMs].
  int confidentCoverageMs(int t0, int t1) {
    final points = confidentPulse(t0, t1);
    if (points.isEmpty) return 0;
    var total = 0;
    int? prev;
    for (final p in points) {
      final gap = prev == null ? config.pulseMaxGapMs : p.tMs - prev;
      total += gap.clamp(0, config.pulseMaxGapMs);
      prev = p.tMs;
    }
    return total;
  }

  List<FaceFrame> framesIn(int t0, int t1) => [
    for (final f in frames)
      if (f.tMs >= t0 && f.tMs <= t1) f,
  ];

  double faceFraction(int t0, int t1) {
    final fs = framesIn(t0, t1);
    if (fs.isEmpty) return 0;
    return fs.where((f) => f.facePresent).length / fs.length;
  }

  double cleanFraction(int t0, int t1) {
    final fs = framesIn(t0, t1);
    if (fs.isEmpty) return 0;
    return fs.where((f) => f.clean).length / fs.length;
  }

  int blinkCount(int t0, int t1) =>
      blinks.where((t) => t >= t0 && t <= t1).length;

  double blinkRatePerMin(int t0, int t1) {
    final minutes = (t1 - t0) / 60000;
    if (minutes <= 0) return 0;
    return blinkCount(t0, t1) / minutes;
  }

  /// True if there's a stretch of at least [freezeMs] with no blinks inside
  /// [t0, t1] (window edges count as boundaries).
  bool blinkFreeze(int t0, int t1, int freezeMs) {
    if (t1 - t0 < freezeMs) return false;
    var prev = t0;
    for (final t in blinks) {
      if (t < t0 || t > t1) continue;
      if (t - prev >= freezeMs) return true;
      prev = t;
    }
    return t1 - prev >= freezeMs;
  }

  Map<String, double> exprMean(int t0, int t1) {
    final sums = <String, double>{};
    var n = 0;
    for (final e in expr) {
      if (e.tMs < t0 || e.tMs > t1) continue;
      n++;
      e.p.forEach((k, v) => sums[k] = (sums[k] ?? 0) + v);
    }
    if (n == 0) return {};
    return sums.map((k, v) => MapEntry(k, v / n));
  }

  /// Largest smoothed rise of any category above the baseline mean.
  (double, String?) exprPeakDelta(
    int t0,
    int t1,
    Map<String, double> base,
    List<String> categories,
    int smoothMs,
  ) {
    final points = [
      for (final e in expr)
        if (e.tMs >= t0 && e.tMs <= t1) e,
    ];
    var best = 0.0;
    String? bestCat;
    for (final cat in categories) {
      final baseline = base[cat] ?? 0;
      var start = 0;
      var sum = 0.0;
      for (var i = 0; i < points.length; i++) {
        sum += points[i].p[cat] ?? 0;
        while (points[i].tMs - points[start].tMs > smoothMs) {
          sum -= points[start].p[cat] ?? 0;
          start++;
        }
        final avg = sum / (i - start + 1);
        final delta = avg - baseline;
        if (delta > best) {
          best = delta;
          bestCat = cat;
        }
      }
    }
    return (best, bestCat);
  }

  /// Non-OK validation codes seen in the window, with how long each lasted
  /// (ms, from snapshot counts), longest first.
  List<(String, int, String)> validationIssues(int t0, int t1) {
    final fs = framesIn(t0, t1);
    if (fs.isEmpty) return [];
    final frameMs = fs.length > 1
        ? ((fs.last.tMs - fs.first.tMs) / (fs.length - 1)).round()
        : 100;
    final counts = <String, int>{};
    final hints = <String, String>{};
    for (final f in fs) {
      final code = f.validationCode;
      if (!f.running) {
        counts['NOT_RUNNING'] = (counts['NOT_RUNNING'] ?? 0) + 1;
        continue;
      }
      if (code == null || code == 'OK') continue;
      counts[code] = (counts[code] ?? 0) + 1;
      if (f.validationHint != null) hints[code] = f.validationHint!;
    }
    final out = [
      for (final e in counts.entries)
        (e.key, e.value * frameMs, hints[e.key] ?? ''),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return out;
  }

  /// First confirmed talk start at or after [t].
  int? firstTalkStartAfter(int t) {
    for (final e in talkEdges) {
      if (e.talking && e.tMs >= t) return e.tMs;
    }
    return null;
  }
}
