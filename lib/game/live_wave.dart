import '../presage/presage_models.dart';

/// The last few seconds of the pulse waveform, for the live card on
/// Calibrate (SPEC.md decision 88).
///
/// Samples are placed by the SDK's own timestamps, not by count, so the card
/// always shows [windowMs] of real time: a dropped frame or a late batch
/// doesn't squeeze or stretch the beats, and a stretch with no samples shows
/// as a gap. Only differences between timestamps are used, so the SDK clock
/// needs no mapping to wall-clock time.
class LiveWave {
  LiveWave({this.windowMs = 8000});

  /// How much waveform the card shows: about 9 beats at 65 BPM.
  final int windowMs;

  /// The SDK clock going back by more than this is a restart, and the old
  /// samples go. The same size as [ScoringConfig.traceClockJumpMs].
  static const restartBackMs = 2000;

  /// Never hold more than this many samples, whatever the timestamps say
  /// (about 33 s at 30 Hz).
  static const maxPoints = 1000;

  final List<(double, double)> _points = [];

  /// (SDK time ms, value), oldest first: the last [windowMs] and the one
  /// sample just before it, so the line can enter at the left edge.
  List<(double, double)> get points => _points;

  /// Adds one snapshot's samples. Repeats are dropped.
  void add(List<TraceSample> samples) {
    if (samples.isEmpty) return;
    final sorted = [...samples]..sort((a, b) => a.tsUs.compareTo(b.tsUs));
    for (final s in sorted) {
      final t = s.tsUs / 1000;
      if (_points.isNotEmpty) {
        final last = _points.last.$1;
        if (t <= last) {
          if (last - t <= restartBackMs) continue;
          _points.clear();
        }
      }
      _points.add((t, s.value));
    }
    final from = _points.last.$1 - windowMs;
    var cut = _points.length > maxPoints ? _points.length - maxPoints : 0;
    while (cut + 1 < _points.length && _points[cut + 1].$1 <= from) {
      cut++;
    }
    if (cut > 0) _points.removeRange(0, cut);
  }

  void clear() => _points.clear();
}
