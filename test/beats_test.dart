import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/beats.dart';
import 'package:susometer/game/scoring_config.dart';
import 'package:susometer/game/signal_log.dart';
import 'package:susometer/presage/presage_models.dart';

import 'synthetic.dart';

const cfg = ScoringConfig();

List<(double, double, bool)> ok(List<(double, double)> wave) => [
  for (final (t, v) in wave) (t, v, true),
];

BeatSeries beatsOf(List<(double, double)> wave) => detectBeats(ok(wave), cfg);

void main() {
  group('beat finding (SPEC.md decision 63)', () {
    test('a steady 72 BPM waveform reads 72 BPM, beat by beat', () {
      final b = beatsOf(pulseWave(start: 0, end: 60000, bpm: (_) => 72));
      expect(b.meanBpm(2000, 58000), closeTo(72, 0.5));
      expect(b.coverage(2000, 58000), greaterThan(0.95));
      for (final i in b.accepted) {
        expect(i.bpm, closeTo(72, 4), reason: 'each beat, not just the mean');
      }
    });

    test('works across the heart-rate range and sample rates', () {
      for (final hz in [15.0, 30.0, 60.0]) {
        for (final bpm in [45.0, 70.0, 110.0, 150.0]) {
          final b = beatsOf(
            pulseWave(start: 0, end: 40000, bpm: (_) => bpm, hz: hz),
          );
          expect(
            b.meanBpm(3000, 37000),
            closeTo(bpm, 1.5),
            reason: '$bpm BPM at $hz Hz',
          );
          expect(
            b.coverage(3000, 37000),
            greaterThan(0.9),
            reason: '$bpm BPM at $hz Hz',
          );
        }
      }
    });

    test('a jump in heart rate shows within a couple of beats', () {
      final b = beatsOf(
        pulseWave(start: 0, end: 60000, bpm: (t) => t < 30000 ? 65 : 90),
      );
      expect(b.meanBpm(5000, 28000), closeTo(65, 1));
      expect(b.meanBpm(33000, 55000), closeTo(90, 1));
      // The SDK's 12 s average would still be halfway; beats are there.
      expect(b.bpmAt(32000), closeTo(90, 5));
    });

    test('breathing-driven swings in heart rate are followed', () {
      // Respiratory sinus arrhythmia: ±6 BPM over a 5 s breath.
      double hr(double t) => 75 + 6 * math.sin(2 * math.pi * t / 5000);
      final b = beatsOf(pulseWave(start: 0, end: 60000, bpm: hr));
      expect(b.meanBpm(5000, 55000), closeTo(75, 1));
      expect(b.coverage(5000, 55000), greaterThan(0.9));
      final rates = [for (final i in b.accepted) i.bpm];
      expect(rates.reduce(math.max) - rates.reduce(math.min), greaterThan(8));
    });

    test('heavy noise still gives the right rate', () {
      final b = beatsOf(
        pulseWave(start: 0, end: 60000, bpm: (_) => 80, noise: 0.3, seed: 7),
      );
      expect(b.meanBpm(3000, 57000), closeTo(80, 2));
      expect(b.coverage(3000, 57000), greaterThan(0.8));
    });

    test('samples that arrived with bad validation split the waveform', () {
      final wave = pulseWave(start: 0, end: 40000, bpm: (_) => 70);
      final points = [
        for (final (t, v) in wave) (t, v, t < 18000 || t > 21000),
      ];
      final b = detectBeats(points, cfg);
      for (final i in b.intervals) {
        expect(
          i.endMs <= 18000 || i.startMs >= 21000,
          isTrue,
          reason: 'no interval spans the bad stretch',
        );
      }
      expect(b.coverage(18500, 20500), 0);
      expect(b.meanBpm(3000, 37000), closeTo(70, 1));
    });

    test('a dropped-out beat is marked as an artifact, not 35 BPM', () {
      final wave = pulseWave(start: 0, end: 40000, bpm: (_) => 70);
      // Remove one whole beat (70 BPM: a beat every ~857 ms), leaving only
      // the breathing drift.
      final flat = [
        for (final (t, v) in wave)
          (
            t,
            t > 20000 && t < 20900 ? 0.4 * math.sin(2 * math.pi * t / 4500) : v,
          ),
      ];
      final b = beatsOf(flat);
      final rejected = b.intervals.where((i) => !i.accepted).toList();
      expect(rejected, isNotEmpty);
      for (final i in b.accepted) {
        expect(i.bpm, greaterThan(55));
      }
      expect(b.meanBpm(3000, 37000), closeTo(70, 1.5));
    });

    test('a short or empty waveform finds nothing and never throws', () {
      expect(detectBeats(const [], cfg).intervals, isEmpty);
      expect(
        beatsOf(pulseWave(start: 0, end: 2000, bpm: (_) => 70)).intervals,
        isEmpty,
      );
      final flat = [for (var t = 0.0; t < 20000; t += 33) (t, 0.5, true)];
      expect(detectBeats(flat, cfg).accepted, isEmpty);
      final nan = [for (var t = 0.0; t < 20000; t += 33) (t, double.nan, true)];
      expect(detectBeats(nan, cfg).accepted, isEmpty);
      expect(BeatSeries.empty.meanBpm(0, 1000), isNull);
      expect(BeatSeries.empty.coverage(0, 1000), 0);
    });

    test('smoothed rate is null in gaps and close to the truth elsewhere', () {
      final wave = pulseWave(start: 0, end: 40000, bpm: (_) => 70);
      final points = [
        for (final (t, v) in wave) (t, v, t < 15000 || t > 25000),
      ];
      final b = detectBeats(points, cfg);
      final grid = b.smoothed(5000, 35000, 250, 3000);
      for (final (t, bpm) in grid) {
        if (t > 16500 && t < 23500) {
          expect(bpm, isNull, reason: 'at $t');
        } else if (t < 13000 || t > 27000) {
          expect(bpm, closeTo(70, 2), reason: 'at $t');
        }
      }
    });
  });

  group('waveform clock (SPEC.md decision 63)', () {
    test('an SDK clock far from wall time maps onto the right moments', () {
      final wave = pulseWave(start: 1000, end: 30000, bpm: (_) => 70);
      final log = SignalLog(config: cfg);
      for (final s in synth(
        start: 0,
        end: 30000,
        wave: wave,
        sdkClockOffsetMs: 1700000000000,
      )) {
        log.add(s);
      }
      final mapped = log.traceIn(0, 40000);
      expect(mapped.length, closeTo(wave.length, 10));
      // Mapped times run late by about the delivery delay (150 ms), never early.
      for (var i = 0; i < mapped.length; i += 50) {
        final shift = mapped[i].$1 - wave[i].$1;
        expect(shift, inInclusiveRange(100, 260), reason: 'sample $i');
      }
      final b = detectBeats(mapped, cfg);
      expect(b.meanBpm(5000, 28000), closeTo(70, 1));
    });

    test('an SDK clock that restarts keeps both halves usable', () {
      final first = pulseWave(start: 0, end: 20000, bpm: (_) => 70);
      final second = pulseWave(start: 25000, end: 50000, bpm: (_) => 90);
      final log = SignalLog(config: cfg);
      for (final s in synth(start: 0, end: 20200, wave: first)) {
        log.add(s);
      }
      // The SDK restarts and its clock goes back to near zero.
      for (final s in synth(
        start: 25000,
        end: 50200,
        wave: second,
        sdkClockOffsetMs: 25000,
      )) {
        log.add(s);
      }
      final b = detectBeats(log.traceIn(0, 60000), cfg);
      expect(b.meanBpm(3000, 18000), closeTo(70, 1));
      expect(b.meanBpm(28000, 48000), closeTo(90, 1));
      final mapped = log.traceIn(0, 60000);
      for (var i = 1; i < mapped.length; i++) {
        expect(mapped[i].$1, greaterThanOrEqualTo(mapped[i - 1].$1));
      }
      expect(log.traceIn(20500, 25000), isEmpty);
    });

    PresageSample withTrace(PresageSample s, List<TraceSample> t) =>
        PresageSample(
          tMs: s.tMs,
          status: s.status,
          validation: s.validation,
          traceSamples: t,
        );

    void expectOnTime(SignalLog log, List<(double, double)> wave) {
      expect(log.trace.map((p) => p.clock).toSet(), {0});
      final mapped = log.traceIn(0, 1 << 52);
      expect(mapped.length, closeTo(wave.length, 10));
      for (var i = 0; i < mapped.length; i += 25) {
        final shift = mapped[i].$1 - wave[i].$1;
        expect(shift, inInclusiveRange(100, 260), reason: 'sample $i');
      }
      expect(detectBeats(mapped, cfg).meanBpm(3000, 28000), closeTo(70, 1));
    }

    test('a stall that holds back snapshots doesn\'t shift the mapping', () {
      // The bridge's main thread is busy for 3 s: no snapshots, then one that
      // carries everything since.
      final wave = pulseWave(start: 0, end: 30000, bpm: (_) => 70);
      final samples = synth(start: 0, end: 30000, wave: wave);
      final log = SignalLog(config: cfg);
      final held = <TraceSample>[];
      for (var i = 0; i < samples.length; i++) {
        final s = samples[i];
        if (i >= 100 && i < 130) {
          held.addAll(s.traceSamples);
          continue;
        }
        log.add(i == 130 ? withTrace(s, [...held, ...s.traceSamples]) : s);
      }
      expectOnTime(log, wave);
    });

    test('a first batch that arrives late is corrected, not split off', () {
      // The SDK hands over its first samples 2.5 s late, then catches up.
      final wave = pulseWave(start: 0, end: 30000, bpm: (_) => 70);
      final samples = synth(start: 0, end: 30000, wave: wave);
      final first = samples.indexWhere((s) => s.traceSamples.isNotEmpty);
      final log = SignalLog(config: cfg);
      final held = <TraceSample>[];
      for (var i = 0; i < samples.length; i++) {
        final s = samples[i];
        if (i == first) {
          held.addAll(s.traceSamples);
          log.add(withTrace(s, const []));
        } else if (i > first && i < first + 25) {
          log.add(withTrace(s, const []));
          held.addAll(s.traceSamples);
        } else if (i == first + 25) {
          // The first batch alone, 2.5 s late...
          log.add(withTrace(s, samples[first].traceSamples));
        } else if (i == first + 26) {
          // ...then everything since, on time.
          final rest = held.skip(samples[first].traceSamples.length);
          log.add(
            withTrace(s, [
              ...rest,
              ...samples[first + 25].traceSamples,
              ...s.traceSamples,
            ]),
          );
        } else {
          log.add(s);
        }
      }
      expectOnTime(log, wave);
    });

    test('a bridge that stays late keeps the earlier, shorter delay', () {
      // From 10 s on, every snapshot arrives 3 s later than before.
      final wave = pulseWave(start: 0, end: 30000, bpm: (_) => 70);
      final log = SignalLog(config: cfg);
      for (final s in synth(start: 0, end: 30000, wave: wave)) {
        log.add(
          s.tMs < 10000
              ? s
              : PresageSample(
                  tMs: s.tMs + 3000,
                  status: s.status,
                  validation: s.validation,
                  traceSamples: s.traceSamples,
                ),
        );
      }
      expectOnTime(log, wave);
    });

    test('an SDK clock that jumps ahead starts a new mapping', () {
      final first = pulseWave(start: 0, end: 20000, bpm: (_) => 70);
      final second = pulseWave(start: 25000, end: 50000, bpm: (_) => 90);
      final log = SignalLog(config: cfg);
      for (final s in synth(start: 0, end: 20200, wave: first)) {
        log.add(s);
      }
      for (final s in synth(
        start: 25000,
        end: 50200,
        wave: second,
        sdkClockOffsetMs: -600000,
      )) {
        log.add(s);
      }
      expect(log.trace.map((p) => p.clock).toSet(), {0, 1});
      final b = detectBeats(log.traceIn(0, 60000), cfg);
      expect(b.meanBpm(3000, 18000), closeTo(70, 1));
      expect(b.meanBpm(28000, 48000), closeTo(90, 1));
    });

    test('duplicate and out-of-order samples are dropped', () {
      final log = SignalLog(config: cfg);
      final wave = pulseWave(start: 0, end: 10000, bpm: (_) => 70);
      final samples = synth(start: 0, end: 10000, wave: wave);
      for (final s in samples) {
        log.add(s);
      }
      final n = log.trace.length;
      for (final s in samples.take(20)) {
        log.add(s);
      }
      expect(log.trace.length, n);
    });

    test('the waveform store stays bounded and clears', () {
      final log = SignalLog(config: cfg, maxTracePoints: 1000);
      for (final s in synth(
        start: 0,
        end: 120000,
        wave: pulseWave(start: 0, end: 120000, bpm: (_) => 70),
      )) {
        log.add(s);
      }
      expect(log.trace.length, 1000);
      log.clear();
      expect(log.trace, isEmpty);
      expect(log.traceIn(0, 200000), isEmpty);
    });
  });

  group('fuzz (SPEC.md decision 63)', () {
    test('random waveforms never throw and keep the series sane', () {
      for (var seed = 0; seed < 300; seed++) {
        final rng = math.Random(seed);
        double value() => switch (rng.nextInt(20)) {
          0 => double.nan,
          1 => double.infinity,
          2 => -1e300,
          3 => 1e300,
          _ => rng.nextDouble() * 4 - 2,
        };
        var t = rng.nextDouble() * 1e12;
        final points = <(double, double, bool)>[];
        final n = rng.nextInt(3000);
        for (var i = 0; i < n; i++) {
          t += switch (rng.nextInt(30)) {
            0 => -rng.nextDouble() * 5000,
            1 => rng.nextDouble() * 5000,
            2 => 0,
            _ => 10 + rng.nextDouble() * 50,
          };
          points.add((t, value(), rng.nextInt(15) != 0));
        }
        final b = detectBeats(points, cfg);
        double? prevEnd;
        for (final i in b.intervals) {
          expect(i.endMs, greaterThan(i.startMs), reason: 'seed $seed');
          if (prevEnd != null) {
            expect(i.startMs, greaterThanOrEqualTo(prevEnd - 1e-6));
          }
          prevEnd = i.endMs;
        }
        for (final i in b.accepted) {
          expect(i.ibiMs, inInclusiveRange(cfg.beatMinIbiMs, cfg.beatMaxIbiMs));
        }
        if (points.isEmpty) continue;
        final a = points.first.$1;
        final z = points.last.$1;
        final cov = b.coverage(a, z);
        expect(cov, inInclusiveRange(0, 1), reason: 'seed $seed');
        final mean = b.meanBpm(a, z);
        if (mean != null) expect(mean.isFinite, isTrue, reason: 'seed $seed');
        final r = b.rmssdMs(a, z);
        if (r != null) expect(r.isFinite, isTrue, reason: 'seed $seed');
        for (final (_, v) in b.smoothed(a, a + 20000, 250, 3000)) {
          if (v != null) expect(v.isFinite, isTrue, reason: 'seed $seed');
        }
      }
    });

    test('random waveform snapshots never throw and keep the store sane', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = math.Random(seed);
        final log = SignalLog(config: cfg, maxTracePoints: 2000);
        var wall = 1700000000000;
        var sdk = rng.nextInt(1 << 30) * 1000;
        for (var i = 0; i < 400; i++) {
          wall += switch (rng.nextInt(40)) {
            0 => 3000,
            _ => 100,
          };
          sdk += switch (rng.nextInt(40)) {
            0 => -rng.nextInt(50000000),
            1 => rng.nextInt(50000000),
            _ => 100000,
          };
          final k = rng.nextInt(6);
          final ts = [
            for (var j = 0; j < k; j++)
              rng.nextInt(10) == 0
                  ? sdk - rng.nextInt(5000000)
                  : sdk - j * 33000,
          ];
          final vals = [
            for (var j = 0; j < k; j++)
              rng.nextInt(10) == 0 ? double.nan : rng.nextDouble(),
          ];
          log.add(
            PresageSample.fromMap({
              't': wall,
              'status': rng.nextInt(10) == 0 ? 'stopping' : 'running',
              'validation': {
                'code': rng.nextInt(8) == 0 ? 'EXCESSIVE_MOTION' : 'OK',
                'hint': '',
              },
              'trace': vals,
              if (rng.nextInt(12) != 0)
                'traceTs': rng.nextInt(20) == 0 ? [...ts, 1] : ts,
              'traceConf': [for (final _ in ts) 0.9],
            }),
          );
        }
        expect(log.trace.length, lessThanOrEqualTo(2000), reason: 'seed $seed');
        final all = log.traceIn(-(1 << 52), 1 << 52);
        expect(all.length, log.trace.length, reason: 'seed $seed');
        for (var i = 1; i < all.length; i++) {
          expect(all[i].$1, greaterThanOrEqualTo(all[i - 1].$1));
          expect(all[i].$1.isFinite && all[i].$2.isFinite, isTrue);
        }
        detectBeats(all, cfg);
        log.clear();
        expect(log.traceIn(-(1 << 52), 1 << 52), isEmpty);
      }
    });
  });
}
