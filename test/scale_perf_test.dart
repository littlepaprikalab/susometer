import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
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
          w.askAndAnswer(
            question: 'Question $q for ${names[p]}?',
            answerPulse: 70.0 + (q * 4) % 25,
            votesSus: voters.where((id) => id.hashCode.isEven).toList(),
          );
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

    test('the controller handles a live 10 Hz stream without slowing down', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex']);
        w.calibrate();
        w.game.doneAsking();
        w.elapse(100);
        expect(w.game.phase, GamePhase.answer);
        // Push 3000 extra snapshots straight through the answer-phase path,
        // which recomputes live pulse and blink cards on every snapshot.
        final sw = Stopwatch()..start();
        for (var i = 0; i < 3000; i++) {
          w.presage.controller.add(
            PresageSample.fromMap({
              't': w.now + i,
              'status': 'running',
              'pulse': 72.0,
              'pulseConf': 0.9,
              'pulseAt': w.now + i * 100,
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
}
