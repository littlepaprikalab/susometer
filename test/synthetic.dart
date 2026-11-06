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
}) {
  final out = <PresageSample>[];
  int? pulseAt;
  double? pulseValue;
  double? pulseConf;
  var prev = start - frameMs;
  var talking = false;
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
