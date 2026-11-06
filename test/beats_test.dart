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

    test('a stalled snapshot doesn\'t shift the mapping', () {
      final wave = pulseWave(start: 0, end: 30000, bpm: (_) => 70);
      final log = SignalLog(config: cfg);
      final samples = synth(start: 0, end: 30000, wave: wave);
      for (var i = 0; i < samples.length; i++) {
        final s = samples[i];
        // Snapshots 100–130 reach Dart 3 s late (the app was busy).
        log.add(
          i >= 100 && i <= 130
              ? PresageSample(
                  tMs: s.tMs + 3000,
                  status: s.status,
                  validation: s.validation,
                  traceSamples: s.traceSamples,
                )
              : s,
        );
      }
      expect(log.trace.map((p) => p.clock).toSet(), {0});
      final mapped = log.traceIn(0, 40000);
      for (var i = 0; i < mapped.length; i += 25) {
        final shift = mapped[i].$1 - wave[i].$1;
        expect(shift, inInclusiveRange(100, 260), reason: 'sample $i');
      }
      expect(detectBeats(mapped, cfg).meanBpm(3000, 28000), closeTo(70, 1));
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
}
