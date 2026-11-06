/// Data types for the SmartSpectra bridge stream (SPEC.md §6).
///
/// The Swift side sends one snapshot map about every 100 ms while a session
/// is active. Confidence values arrive normalized to 0..1 (the SDK reports
/// percentages), and all times are wall-clock milliseconds.
library;

enum PresageStatus { idle, starting, running, stopping, error, unknown }

PresageStatus parsePresageStatus(Object? value) => switch (value) {
  'idle' => PresageStatus.idle,
  'starting' => PresageStatus.starting,
  'running' => PresageStatus.running,
  'stopping' => PresageStatus.stopping,
  'error' => PresageStatus.error,
  _ => PresageStatus.unknown,
};

/// SDK validation status: a stable code plus a user-facing hint.
class ValidationInfo {
  const ValidationInfo({required this.code, required this.hint});

  final String code;
  final String hint;

  bool get isOk => code == 'OK';

  /// Codes that mean there's no single usable face in frame.
  bool get faceMissing =>
      code == 'NO_FACE_FOUND' || code == 'MULTIPLE_FACES_FOUND';

  static ValidationInfo? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return ValidationInfo(
      code: raw['code'] as String? ?? 'UNKNOWN',
      hint: raw['hint'] as String? ?? '',
    );
  }

  @override
  String toString() => hint.isEmpty ? code : '$code: $hint';
}

class PresageErrorInfo {
  const PresageErrorInfo({
    required this.code,
    required this.message,
    this.codeNum,
    this.retryable = false,
  });

  final String code;
  final String message;
  final int? codeNum;
  final bool retryable;

  static PresageErrorInfo? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return PresageErrorInfo(
      code: raw['code'] as String? ?? 'unknown',
      message: raw['message'] as String? ?? '',
      codeNum: (raw['codeNum'] as num?)?.toInt(),
      retryable: raw['retryable'] as bool? ?? false,
    );
  }
}

enum PresageEdgeType { blink, talkStart, talkEnd }

/// A blink or talking edge, timestamped when the bridge saw it.
class PresageEdge {
  const PresageEdge({required this.type, required this.tMs, this.sdkTsUs});

  final PresageEdgeType type;
  final int tMs;

  /// Raw SDK timestamp in microseconds, for the Proof Panel.
  final int? sdkTsUs;

  static PresageEdge? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final type = switch (raw['e']) {
      'blinkEvent' => PresageEdgeType.blink,
      'talkStart' => PresageEdgeType.talkStart,
      'talkEnd' => PresageEdgeType.talkEnd,
      _ => null,
    };
    final t = (raw['t'] as num?)?.toInt();
    if (type == null || t == null) return null;
    return PresageEdge(
      type: type,
      tMs: t,
      sdkTsUs: (raw['ts'] as num?)?.toInt(),
    );
  }
}

/// One sample of the SDK's pulse waveform (arterial pressure trace).
class TraceSample {
  const TraceSample(this.tsUs, this.value, this.conf);

  /// SDK timestamp in microseconds. Only differences between samples are
  /// trusted; [SignalLog] maps it to wall-clock time.
  final int tsUs;

  /// Unitless waveform value.
  final double value;

  /// SDK confidence 0..1, or null if the bridge didn't send one.
  final double? conf;
}

/// One snapshot from `sus/presage/stream`.
class PresageSample {
  const PresageSample({
    required this.tMs,
    required this.status,
    this.pulse,
    this.pulseConf,
    this.pulseAtMs,
    this.pulseStable = false,
    this.rmssd,
    this.hrvConf,
    this.hrvStable = false,
    this.blink = false,
    this.talking = false,
    this.expr = const {},
    this.exprAtMs,
    this.frameAtMs,
    this.validation,
    this.error,
    this.events = const [],
    this.trace = const [],
    this.traceSamples = const [],
    this.insightSeen = false,
    this.insight,
  });

  final int tMs;
  final PresageStatus status;

  /// Last valid pulse rate (BPM). Kept between SDK updates.
  final double? pulse;

  /// Confidence of [pulse], 0..1.
  final double? pulseConf;

  /// When the bridge received the current [pulse] sample. A new value means a
  /// fresh pulse sample, so Dart can collect samples without duplicates.
  final int? pulseAtMs;
  final bool pulseStable;

  /// HRV RMSSD (ms). Fills only after about 60 s of measurement.
  final double? rmssd;
  final double? hrvConf;
  final bool hrvStable;

  final bool blink;
  final bool talking;

  /// Expression probabilities 0..1, keyed by lowercase SDK category
  /// (angry, contempt, disgust, fear, happy, neutral, sad, surprise).
  final Map<String, double> expr;

  /// When the bridge received the current [expr] sample (the bridge keeps
  /// the last scores between SDK updates), or null if it hasn't said.
  final int? exprAtMs;

  /// When the SDK last published a camera frame, or when it started running
  /// if that's later; null before either. Snapshots keep coming while the
  /// SDK says it's running even if the camera has stalled, so this is how a
  /// frozen camera shows.
  final int? frameAtMs;

  /// How old the camera image was when this snapshot was sent.
  int? get frameAgeMs {
    final at = frameAtMs;
    return at == null ? null : tMs - at;
  }

  final ValidationInfo? validation;
  final PresageErrorInfo? error;

  /// Blink and talking edges since the previous snapshot.
  final List<PresageEdge> events;

  /// Arterial pressure trace samples since the previous snapshot (unitless),
  /// for drawing the live pulse waveform.
  final List<double> trace;

  /// The same samples with their SDK timestamps, for finding heartbeats.
  /// Empty if the bridge sent no timestamps (`traceTs`) or the two lists
  /// don't line up.
  final List<TraceSample> traceSamples;

  /// True if the SDK ever published an LLM insight. SmartSpectra 3.4.0
  /// auto-fires them once the pulse is stable and offers no switch to turn
  /// them off (SPEC.md decision 67); the app never asks for one.
  final bool insightSeen;

  /// What the SDK's insights were, if it published any.
  final InsightInfo? insight;

  /// The strongest expression, if any.
  MapEntry<String, double>? get topExpression {
    MapEntry<String, double>? best;
    for (final entry in expr.entries) {
      if (best == null || entry.value > best.value) best = entry;
    }
    return best;
  }

  factory PresageSample.fromMap(Map<Object?, Object?> m) {
    final exprRaw = m['expr'];
    final expr = <String, double>{};
    if (exprRaw is Map) {
      exprRaw.forEach((key, value) {
        final v = _finite(value);
        if (key is String && v != null) expr[key] = v;
      });
    }
    final eventsRaw = m['events'];
    final events = <PresageEdge>[
      if (eventsRaw is List)
        for (final e in eventsRaw) ?PresageEdge.fromMap(e),
    ];
    final traceRaw = m['trace'];
    final trace = <double>[
      if (traceRaw is List)
        for (final v in traceRaw) ?_finite(v),
    ];
    final tsRaw = m['traceTs'];
    final confRaw = m['traceConf'];
    final traceSamples = <TraceSample>[];
    if (traceRaw is List && tsRaw is List && tsRaw.length == traceRaw.length) {
      final confOk = confRaw is List && confRaw.length == traceRaw.length;
      for (var i = 0; i < traceRaw.length; i++) {
        final v = _finite(traceRaw[i]);
        final ts = _int(tsRaw[i]);
        if (v == null || ts == null) continue;
        traceSamples.add(
          TraceSample(ts, v, confOk ? _finite(confRaw[i]) : null),
        );
      }
    }
    return PresageSample(
      tMs: _int(m['t']) ?? DateTime.now().millisecondsSinceEpoch,
      status: parsePresageStatus(m['status']),
      pulse: _finite(m['pulse']),
      pulseConf: _finite(m['pulseConf']),
      pulseAtMs: _int(m['pulseAt']),
      pulseStable: m['pulseStable'] as bool? ?? false,
      rmssd: _finite(m['rmssd']),
      hrvConf: _finite(m['hrvConf']),
      hrvStable: m['hrvStable'] as bool? ?? false,
      blink: m['blink'] as bool? ?? false,
      talking: m['talking'] as bool? ?? false,
      expr: expr,
      exprAtMs: _int(m['exprAt']),
      frameAtMs: _int(m['frameAt']),
      validation: ValidationInfo.fromMap(m['validation']),
      error: PresageErrorInfo.fromMap(m['error']),
      events: events,
      trace: trace,
      traceSamples: traceSamples,
      insightSeen: m['insightSeen'] as bool? ?? false,
      insight: InsightInfo.fromMap(m['insight']),
    );
  }
}

/// The LLM insights SmartSpectra published since launch (SPEC.md decision
/// 66). The bridge keeps only what kind the last one was, never its text.
class InsightInfo {
  const InsightInfo({
    required this.count,
    this.kind,
    this.error,
    this.chars = 0,
    this.at,
  });

  final int count;

  /// "analysis" (the LLM answered), "error", "empty", or "other" for a kind
  /// newer than SDK 3.4.0.
  final String? kind;

  /// The error message, e.g. an HTTP status or a transport error. A
  /// transport error may mean the values never left the phone.
  final String? error;

  /// Length of the analysis text (the text itself never crosses the bridge).
  final int chars;

  /// When Presage produced it (ISO time, as the SDK gives it).
  final String? at;

  static InsightInfo? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final count = _int(raw['count']) ?? 0;
    if (count <= 0) return null;
    String? text(Object? v) => v is String ? v : null;
    return InsightInfo(
      count: count,
      kind: text(raw['kind']),
      error: text(raw['error']),
      chars: _int(raw['chars']) ?? 0,
      at: text(raw['at']),
    );
  }

  /// One line for the Proof Panel.
  String get summary {
    final last = switch (kind) {
      'analysis' => 'answered, $chars chars',
      'error' => 'error: ${error ?? '?'}',
      null => 'empty',
      final other => other,
    };
    return 'LLM INSIGHT ×$count ($last)';
  }
}

/// Result of `testConnection()`.
class ConnectionTestResult {
  const ConnectionTestResult({
    required this.ok,
    required this.code,
    required this.message,
    this.phase,
    this.elapsedMs,
    this.startMs,
  });

  final bool ok;
  final String code;
  final String message;

  /// Where the outcome was decided: configure, start or running.
  final String? phase;
  final int? elapsedMs;

  /// How long `start()` took to return.
  final int? startMs;

  factory ConnectionTestResult.fromMap(Map<Object?, Object?> m) =>
      ConnectionTestResult(
        ok: m['ok'] as bool? ?? false,
        code: m['code'] as String? ?? 'UNKNOWN',
        message: m['message'] as String? ?? '',
        phase: m['phase'] as String?,
        elapsedMs: (m['ms'] as num?)?.toInt(),
        startMs: (m['startMs'] as num?)?.toInt(),
      );
}

/// A failed bridge call, carrying the SDK error code (e.g. authenticationFailed).
class PresageException implements Exception {
  const PresageException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'PresageException($code): $message';
}

/// A finite number from the platform channel, else null: NaN or infinity
/// from native code must never reach scoring or a chart.
double? _finite(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

int? _int(Object? v) => switch (v) {
  int() => v,
  double() when v.isFinite => v.toInt(),
  _ => null,
};
