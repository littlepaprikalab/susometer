import 'dart:math' as math;

import 'package:susometer/presage/presage_models.dart';

/// Builds made-up SmartSpectra snapshot streams (SPEC.md §13): one frame
/// every [frameMs], a fresh pulse sample every [pulseEveryMs], and blink /
/// talking edges at the given times.
List<PresageSample> synth({
  required int start,
  required int end,
  int frameMs = 100,
  double Function(int t)? pulse,
  double Function(int t)? conf,
  int pulseEveryMs = 1000,
  List<int> blinks = const [],
  List<(int, bool)> talk = const [],
  String Function(int t)? code,
  Map<String, double> Function(int t)? expr,
  String status = 'running',
  List<(double, double)> wave = const [],
  int waveLatencyMs = 150,
  int sdkClockOffsetMs = 0,
}) {
  final out = <PresageSample>[];
  int? pulseAt;
  double? pulseValue;
  double? pulseConf;
  var prev = start - frameMs;
  var talking = false;
  var w = 0;
  for (var t = start; t <= end; t += frameMs) {
    if (pulse != null && (pulseAt == null || t - pulseAt >= pulseEveryMs)) {
      pulseAt = t;
      pulseValue = pulse(t);
      pulseConf = conf?.call(t) ?? 0.9;
    }
    final events = <Map<String, Object?>>[];
    for (final b in blinks) {
      if (b > prev && b <= t) events.add({'e': 'blinkEvent', 't': b});
    }
    for (final (at, on) in talk) {
      if (at > prev && at <= t) {
        events.add({'e': on ? 'talkStart' : 'talkEnd', 't': at});
        talking = on;
      }
    }
    // Waveform samples reach the bridge [waveLatencyMs] after they happen,
    // stamped with the SDK's clock ([sdkClockOffsetMs] behind wall time).
    final trace = <double>[];
    final traceTs = <int>[];
    while (w < wave.length && wave[w].$1 <= t - waveLatencyMs) {
      if (wave[w].$1 > prev - waveLatencyMs) {
        trace.add(wave[w].$2);
        traceTs.add(((wave[w].$1 - sdkClockOffsetMs) * 1000).round());
      }
      w++;
    }
    final c = code?.call(t) ?? 'OK';
    out.add(
      PresageSample.fromMap({
        't': t,
        'status': status,
        'pulse': pulseValue,
        'pulseConf': pulseConf,
        'pulseAt': pulseAt,
        'talking': talking,
        'expr':
            expr?.call(t) ??
            const {'neutral': 0.8, 'surprise': 0.05, 'fear': 0.02},
        'validation': {'code': c, 'hint': c == 'OK' ? '' : 'hint for $c'},
        'events': events,
        if (trace.isNotEmpty) ...{
          'trace': trace,
          'traceTs': traceTs,
          'traceConf': [for (final _ in trace) 0.9],
        },
      }),
    );
    prev = t;
  }
  return out;
}

/// Evenly spaced times from [start] to [end] (exclusive), [perMinute] per minute.
List<int> every(int start, int end, double perMinute) {
  if (perMinute <= 0) return const [];
  final step = (60000 / perMinute).round();
  return [for (var t = start + step ~/ 2; t < end; t += step) t];
}

/// Makes a pulse waveform one sample at a time: each beat a sharp systolic
/// peak and a smaller wave after it, plus breathing drift and noise. A beat
/// happens where the phase crosses a whole number (the peak is 15% into each
/// cycle).
class PulseWaveGen {
  PulseWaveGen({this.noise = 0.05, int seed = 1}) : _rnd = math.Random(seed);

  final double noise;
  final math.Random _rnd;
  double _phase = 0;

  /// The value at wall-clock [t] (ms), [dtMs] after the previous sample.
  double next(double t, double bpm, double dtMs) {
    _phase += bpm / 60000 * dtMs;
    final f = _phase - _phase.floor();
    double bump(double at, double width) =>
        math.exp(-math.pow((f - at) / width, 2).toDouble());
    return bump(0.15, 0.07) +
        0.35 * bump(0.45, 0.1) +
        0.4 * math.sin(2 * math.pi * t / 4500) +
        noise * (_rnd.nextDouble() * 2 - 1);
  }
}

/// A made-up pulse waveform at [hz], (wall-clock ms, value), at heart rate
/// [bpm] (which can change over time). Sample times wobble by [jitterMs].
List<(double, double)> pulseWave({
  required int start,
  required int end,
  required double Function(double t) bpm,
  double hz = 30,
  double noise = 0.05,
  double jitterMs = 3,
  int seed = 1,
}) {
  final gen = PulseWaveGen(noise: noise, seed: seed);
  final jitter = math.Random(seed + 1);
  final out = <(double, double)>[];
  final dt = 1000 / hz;
  for (var t = start.toDouble(); t <= end; t += dt) {
    final v = gen.next(t, bpm(t), dt);
    out.add((t + jitterMs * (jitter.nextDouble() * 2 - 1), v));
  }
  return out;
}
