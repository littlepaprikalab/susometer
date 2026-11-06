import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/expression_tag.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/game/scoring.dart';
import 'package:susometer/game/scoring_config.dart';
import 'package:susometer/game/signal_log.dart';
import 'package:susometer/presage/presage_models.dart';

import 'synthetic.dart';
import 'world.dart';

void main() {
  test('scale: 8 players × 7 questions, everyone votes, game completes', () {
    fakeAsync((async) {
      final w = World(async);
      final names = [
        'Sam',
        'Alex',
        'Priya',
        'Jordan',
        'Kai',
        'Mo',
        'Lee',
        'Ana',
      ];
      w.startGame(names, questions: 7);
      var maxFrames = 0;
      for (var p = 0; p < names.length; p++) {
        expect(w.game.phase, GamePhase.consent);
        expect(w.game.currentPlayer.name, names[p]);
        w.calibrate();
        expect(
          w.game.log.frames.length,
          lessThan(2000),
          reason: 'log restarts every turn',
        );
        for (var q = 0; q < 7; q++) {
          final voters = w.game.voters.map((v) => v.id).toList();
          expect(voters.length, 7);
          // Every third answer reacts on two signals (a pulse alone can't
          // reach Sus), so some verdicts are Sus and votes can match.
          final stressed = q % 3 == 2;
          if (stressed) w.expr = const {'neutral': 0.3, 'surprise': 0.6};
          w.askAndAnswer(
            question: 'Question $q for ${names[p]}?',
            answerPulse: stressed ? 92 : 70.0 + (q * 4) % 25,
            votesSus: voters.where((id) => id.hashCode.isEven).toList(),
          );
          w.expr = const {'neutral': 0.8, 'surprise': 0.05};
          maxFrames = maxFrames < w.game.log.frames.length
              ? w.game.log.frames.length
              : maxFrames;
          w.game.nextQuestion();
          w.elapse(100);
        }
      }
      expect(w.game.phase, GamePhase.leaderboard);
      final awards = w.game.awards!;
      expect(awards.ranked.length, 8);
      expect(
        w.game.turns.map((t) => t.results.length).reduce((a, b) => a + b),
        56,
      );
      expect(awards.lieDetector, isNotNull);
      expect(
        maxFrames,
        lessThan(SignalLog().maxFrames),
        reason: 'one turn stays far below the cap',
      );
      expect(w.running, isFalse, reason: 'camera stopped after the last turn');
      expect(
        w.presage.calls.where((c) => c == 'start').length,
        names.length,
        reason: 'one camera session per player: no watchdog restarts',
      );
      w.dispose();
    });
  });

  test(
    'solo deck reshuffles when 8 players use more questions than it has',
    () {
      fakeAsync((async) {
        final w = World(async);
        w.game.setMode(GameMode.solo);
        w.startGame(['Sam'], questions: 7);
        w.calibrate();
        final seen = <String>[];
        for (var q = 0; q < 7; q++) {
          w.until(() => w.game.phase == GamePhase.answer);
          seen.add(w.game.questionText);
          w.game.finalAnswer();
          w.until(
            () =>
                w.game.phase == GamePhase.verdict ||
                w.game.phase == GamePhase.redo,
          );
          if (w.game.phase == GamePhase.redo) {
            w.game.skipQuestion();
          } else {
            w.game.nextQuestion();
          }
          w.elapse(100);
        }
        for (var i = 1; i < seen.length; i++) {
          expect(
            seen[i],
            isNot(seen[i - 1]),
            reason: 'never the same question twice in a row',
          );
        }
        w.dispose();
      });
    },
  );

  test('solo scale: 8 players × 7 questions; the hold never leaks', () {
    fakeAsync((async) {
      final w = World(async);
      w.game.setMode(GameMode.solo);
      final names = [for (var i = 1; i <= 8; i++) 'Player $i'];
      w.startGame(names, questions: 7);
      for (var p = 0; p < names.length; p++) {
        expect(w.game.phase, GamePhase.consent);
        w.calibrate();
        for (var q = 0; q < 7; q++) {
          final at = '${names[p]} Q${q + 1}';
          w.until(() => w.game.phase == GamePhase.answer, what: at);
          expect(w.game.soloHoldsQuestion, isTrue, reason: '$at starts held');
          final tQ1 = w.game.detector!.tQ1;
          w.elapse(1000);
          // Every way out of the hold: the button, the camera, the mic.
          switch ((p * 7 + q) % 3) {
            case 0:
              w.game.readyToAnswer();
              w.talk(true);
            case 1:
              w.talk(true);
            case 2:
              w.say('No way');
              w.talk(true);
          }
          w.elapse(300);
          expect(w.game.soloHoldsQuestion, isFalse, reason: at);
          expect(w.game.shownPhase, GamePhase.answer, reason: at);
          expect(w.game.detector!.tQ1, tQ1, reason: '$at timing unchanged');
          w.elapse(1500);
          w.talk(false);
          w.elapse(800);
          w.game.finalAnswer();
          w.until(
            () =>
                w.game.phase == GamePhase.verdict ||
                w.game.phase == GamePhase.redo,
            what: '$at verdict',
          );
          expect(w.game.soloHoldsQuestion, isFalse);
          expect(w.game.shownPhase, w.game.phase);
          if (w.game.phase == GamePhase.redo) {
            w.game.skipQuestion();
          } else {
            w.game.nextQuestion();
          }
          w.elapse(100);
        }
      }
      expect(w.game.phase, GamePhase.leaderboard);
      expect(
        w.game.turns.map((t) => t.results.length).reduce((a, b) => a + b),
        56,
      );
      expect(w.running, isFalse, reason: 'camera stopped after the last turn');
      expect(
        w.presage.calls.where((c) => c == 'start').length,
        names.length,
        reason: 'one camera session per player: no watchdog restarts',
      );
      w.dispose();
    });
  });

  group('performance', () {
    test('a 10-minute stream at 10 Hz ingests and scores quickly', () {
      final samples = synth(
        start: 0,
        end: 600000,
        pulse: (t) => 70 + (t % 7000) / 1000,
        blinks: every(0, 600000, 18),
        talk: [
          for (var t = 5000; t < 600000; t += 9000) ...[
            (t, true),
            (t + 3000, false),
          ],
        ],
      );
      final log = SignalLog();
      final sw = Stopwatch()..start();
      samples.forEach(log.add);
      final ingestMs = sw.elapsedMilliseconds;
      const scoring = Scoring(ScoringConfig());
      final base = scoring.baseline(
        log,
        start: 0,
        quietEnd: 20000,
        end: 40000,
        warmupLatenciesS: const [1],
      )!;
      sw.reset();
      for (var q = 0; q < 50; q++) {
        final t0 = 60000 + q * 10000;
        scoring.features(
          log,
          QuestionTiming(
            tQ0: t0,
            tQ1: t0 + 3000,
            tA0: t0 + 4000,
            tA1: t0 + 8000,
            hesitationFromMs: t0 + 3000,
          ),
          base,
        );
      }
      final scoreMs = sw.elapsedMilliseconds;
      // ~6000 snapshots: well under 1 ms each, and 50 scored windows in < 1 s.
      expect(ingestMs, lessThan(1500), reason: 'ingest took $ingestMs ms');
      expect(scoreMs, lessThan(1500), reason: 'scoring took $scoreMs ms');
    });

    test('heartbeat scoring costs the same at the end of the longest turn', () {
      // 35 minutes of 30 Hz waveform fills the store (60,000 samples).
      const end = 2100000;
      final log = SignalLog();
      final sw = Stopwatch()..start();
      for (final s in synth(
        start: 0,
        end: end,
        pulse: (_) => 72,
        wave: pulseWave(start: 0, end: end, bpm: (_) => 72),
      )) {
        log.add(s);
      }
      final ingestMs = sw.elapsedMilliseconds;
      expect(log.trace.length, log.maxTracePoints);
      const scoring = Scoring(ScoringConfig());
      const c = ScoringConfig();
      double perQuestionMs(int tQ0) {
        final t = QuestionTiming(
          tQ0: tQ0,
          tQ1: tQ0 + 3000,
          tA0: tQ0 + 4000,
          tA1: tQ0 + 9000,
          hesitationFromMs: tQ0 + 3000,
        );
        final w = Stopwatch()..start();
        for (var i = 0; i < 10; i++) {
          final beats = scoring.beats(
            log,
            tQ0 - c.beatLookbackMs,
            t.windowEnd(c.minWindowAfterQuestionMs),
          );
          expect(scoring.pulseShape(log, beats, t), isNotNull);
        }
        return w.elapsedMicroseconds / 10 / 1000;
      }

      final early = perQuestionMs(end - 1900000);
      final late = perQuestionMs(end - 40000);
      // ~20,000 snapshots with waveform; one question's beats in a few ms
      // (JIT), wherever it falls in the turn.
      expect(ingestMs, lessThan(3000), reason: 'ingest took $ingestMs ms');
      expect(late, lessThan(25), reason: 'a question took $late ms');
      expect(late, lessThan(early * 3 + 5), reason: 'early $early, late $late');
    });

    test('the controller handles a live 10 Hz stream without slowing down', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        w.game.doneAsking();
        w.elapse(100);
        expect(w.game.phase, GamePhase.answer);
        // Push 3000 extra snapshots straight through the answer-phase path,
        // which recomputes live pulse and blink cards and the expression
        // tag on every snapshot.
        final sw = Stopwatch()..start();
        for (var i = 0; i < 3000; i++) {
          w.presage.controller.add(
            PresageSample.fromMap({
              't': w.now + i,
              'status': 'running',
              'pulse': 72.0,
              'pulseConf': 0.9,
              'pulseAt': w.now + i * 100,
              'expr': {
                'neutral': 0.5 + (i % 7) / 20,
                'surprise': 0.4 - (i % 5) / 20,
                'happy': 0.05,
                'unknown9': 0.9,
              },
              'exprAt': w.now + i,
              'frameAt': w.now + i,
              'validation': {'code': 'OK', 'hint': ''},
            }),
          );
        }
        async.flushMicrotasks();
        expect(
          sw.elapsedMilliseconds,
          lessThan(3000),
          reason: 'took ${sw.elapsedMilliseconds} ms',
        );
        w.dispose();
      });
    });
  });

  test('10 Hz with the waveform and the Proof Panel on stays fast', () {
    fakeAsync((async) {
      final w = World(async);
      w.settings.proofPanel = true;
      w.heart = (_) => 72;
      w.startGame(['Sam', 'Alex']);
      w.calibrate();
      w.game.doneAsking();
      w.elapse(100);
      expect(w.game.phase, GamePhase.answer);
      // 5 minutes of snapshots straight through the answer-phase path, each
      // with ~3 waveform samples; the beat readout runs once a second.
      final gen = PulseWaveGen();
      final t0 = w.now;
      var readouts = 0;
      var lastReadout = w.game.live.beatsAtMs;
      final sw = Stopwatch()..start();
      for (var i = 0; i < 3000; i++) {
        final t = t0 + i * 100;
        final ts = [for (var k = 0; k < 3; k++) t - 150 - 100 + k * 33.3];
        w.presage.controller.add(
          PresageSample.fromMap({
            't': t,
            'status': 'running',
            'pulse': 72.0,
            'pulseConf': 0.9,
            'pulseAt': t - t % 1000,
            'validation': {'code': 'OK', 'hint': ''},
            'trace': [for (final x in ts) gen.next(x, 72, 33.3)],
            'traceTs': [for (final x in ts) (x * 1000).round()],
            'traceConf': [0.9, 0.9, 0.9],
          }),
        );
        async.flushMicrotasks();
        if (w.game.live.beatsAtMs != lastReadout) {
          readouts++;
          lastReadout = w.game.live.beatsAtMs;
        }
      }
      expect(readouts, closeTo(300, 5));
      expect(w.game.live.beatBpm, closeTo(72, 2));
      expect(
        sw.elapsedMilliseconds,
        lessThan(4000),
        reason: 'took ${sw.elapsedMilliseconds} ms',
      );
      w.dispose();
    });
  });

  test('scale with heartbeats: 4 players × 7 questions, scored by beats', () {
    fakeAsync((async) {
      final w = World(async);
      var hot = 70.0;
      w.heart = (_) =>
          w.game.phase == GamePhase.answer || w.game.phase == GamePhase.settle
          ? hot
          : 70;
      final names = ['Sam', 'Alex', 'Priya', 'Jordan'];
      w.startGame(names, questions: 7);
      for (var p = 0; p < names.length; p++) {
        w.calibrate();
        for (var q = 0; q < 7; q++) {
          hot = q == 4 ? 95 : 70;
          final r = w.askAndAnswer(question: 'Question $q for ${names[p]}?');
          final b = r.breakdown!;
          expect(
            b.pulseMethod,
            PulseMethod.beats,
            reason: '${names[p]} Q$q: ${b.pulseNote}',
          );
          if (q == 4) {
            expect(b.zPulse, greaterThan(0.6), reason: '${names[p]} Q$q');
          } else {
            expect(b.zPulse, lessThan(0.25), reason: '${names[p]} Q$q');
          }
          expect(
            w.game.log.trace.length,
            lessThan(20000),
            reason: 'the waveform restarts every turn',
          );
          w.game.nextQuestion();
          w.elapse(100);
        }
      }
      expect(w.game.phase, GamePhase.leaderboard);
      w.dispose();
    });
  });

  test('the expression tagger: constant time, no growth', () {
    final t = ExpressionTagger();
    final frames = [
      for (var i = 0; i < 64; i++)
        {
          'neutral': 0.4 + (i % 9) / 30,
          'surprise': 0.3 + (i % 7) / 25,
          'happy': 0.1,
          'fear': 0.05,
          'unspecified': 0.2,
        },
    ];
    // A 10-minute turn at 10 Hz is 6000 snapshots; this is 100 of them.
    const n = 600000;
    final sw = Stopwatch()..start();
    var changes = 0;
    for (var i = 0; i < n; i++) {
      if (t.add(i * 100, frames[i % 64], faceOk: true, exprAtMs: i * 100)) {
        changes++;
      }
    }
    final us = sw.elapsedMicroseconds / n;
    expect(us, lessThan(5), reason: '${us.toStringAsFixed(2)} µs per snapshot');
    expect(changes, lessThan(10), reason: 'steady input, steady tag');
  });
}
