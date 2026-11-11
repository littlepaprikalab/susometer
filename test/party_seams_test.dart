// Reliability pass over the party changes (SPEC.md decision 83): the seams
// between Suggest one, the vote, the awards and Play again and everything
// else that can happen in a turn, at scale, and what they cost.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/awards.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/voice/speech_service.dart';

import 'world.dart';

World party(FakeAsync async, {int questions = 3}) {
  final w = World(async);
  w.startGame(['Sam', 'Alex', 'Priya'], questions: questions);
  w.calibrate();
  w.waitForPulse();
  w.elapse(300);
  return w;
}

void main() {
  group('a slip onto Suggest one', () {
    test('after the question was asked: Done asking still has the question, '
        'timed from when it was asked', () {
      fakeAsync((async) {
        final w = party(async);
        final game = w.game;
        w.say('Have you ever lied');
        w.elapse(600);
        w.say('Have you ever lied to me?');
        final asked = w.now;
        w.elapse(1200);
        final oldSegment = w.speech.segment;

        // Reaching for Done asking, the thumb lands on Suggest one.
        game.suggestQuestion();
        expect(game.suggestion, isNotNull);
        w.elapse(300);
        // The recognizer's last word on the question arrives after the slip.
        final lastWords = w.now;
        w.speech.controller.add(
          SpeechText(
            text: 'Have you ever lied to me, Sam?',
            segment: oldSegment,
            isFinal: true,
            tMs: w.now,
          ),
        );
        w.elapse(700);
        game.doneAsking();
        expect(game.phase, GamePhase.answer);
        expect(game.live.askerText, 'Have you ever lied to me, Sam?');
        expect(game.detector!.tQ0, lessThan(asked));
        expect(
          game.detector!.tQ1,
          lastWords,
          reason: 'the question ended with its last words, not at the tap',
        );
        expect(game.detector!.tQ1, lessThan(w.now));

        w.elapse(900);
        w.talk(true);
        w.elapse(300);
        w.say('Never.');
        w.elapse(1500);
        w.talk(false);
        w.elapse(600);
        game.finalAnswer();
        w.until(() => game.phase != GamePhase.settle);
        final r = game.currentResult!;
        expect(r.question, 'Have you ever lied to me, Sam?');
        expect(r.answer, 'Never.');
        expect(r.scored, isTrue);
        expect(r.timing!.tQ0, lessThan(asked));
        w.dispose();
      });
    });

    test('with the player already answering: the answer is still the '
        'answer', () {
      fakeAsync((async) {
        final w = party(async);
        final game = w.game;
        w.say('Have you ever lied to me?');
        w.elapse(1500);
        // Sam answers before tapping anything.
        w.talk(true);
        w.elapse(700);
        w.say('No way');
        w.elapse(1200);
        w.talk(false);
        w.elapse(700);
        expect(game.live.askerText, 'Have you ever lied to me?');
        // ...then slips, then taps Done asking and Final answer.
        game.suggestQuestion();
        w.elapse(800);
        game.doneAsking();
        expect(game.phase, GamePhase.answer);
        expect(game.live.askerText, 'Have you ever lied to me?');
        expect(game.live.answerText, 'No way');
        w.elapse(700);
        game.finalAnswer();
        w.until(() => game.phase != GamePhase.settle);
        final r = game.currentResult!;
        expect(r.question, 'Have you ever lied to me?');
        expect(r.answer, 'No way');
        expect(r.timing!.tA0, isNotNull);
        w.dispose();
      });
    });

    test('then Skip question: the skipped question is the one asked', () {
      fakeAsync((async) {
        final w = party(async);
        final game = w.game;
        w.say('Have you ever lied to me?');
        w.elapse(1500);
        game.suggestQuestion();
        w.elapse(800);
        game.pause();
        game.skipQuestion();
        w.elapse(300);
        final skipped = game.currentTurn.results.single;
        expect(skipped.skipped, isTrue);
        expect(skipped.question, 'Have you ever lied to me?');
        w.dispose();
      });
    });
  });

  test('Pause during a slow restart, then Skip question: the next question '
      'still has its ticker', () {
    // Found by the fuzzer once Suggest one shifted its seeds; the gap was
    // there before. Resume after a trip restarts the camera and the mic; a
    // Pause tapped while the mic is still starting makes that restart give up
    // before the ticker. Resume from that Pause started one. Skip question
    // didn't, so the next question sat there for good: nothing closed its
    // window, and the watchdog was off.
    fakeAsync((async) {
      final w = party(async);
      final game = w.game;
      w.goAway();
      w.elapse(GameController.autoResumeWithinMs + 5000);
      w.comeBack();
      w.elapse(300);
      expect(game.paused, isTrue);
      expect(game.cameraStopped, isTrue);

      w.speech.startTakesMs = 800;
      game.resume();
      w.elapse(200);
      game.pause();
      w.elapse(1500);
      w.speech.startTakesMs = 0;
      expect(game.paused, isTrue);
      expect(game.tickerRunning, isFalse, reason: 'the restart gave up');

      game.skipQuestion();
      w.elapse(300);
      expect(game.phase, GamePhase.ask);
      expect(game.questionIndex, 1);
      expect(game.paused, isFalse);
      expect(game.tickerRunning, isTrue);
      // And it plays through to a verdict.
      final r = w.askAndAnswer();
      expect(r.scored, isTrue);
      w.dispose();
    });
  });

  group('Suggest one across the seams', () {
    test('Another one after a slip still takes the question back; after a '
        'read-out it takes back the read-out', () {
      fakeAsync((async) {
        final w = party(async);
        final game = w.game;
        w.say('Have you ever lied to me?');
        w.elapse(1500);
        game.suggestQuestion();
        w.elapse(800);
        game.suggestQuestion();
        w.elapse(800);
        game.suggestQuestion();
        w.elapse(400);
        game.doneAsking();
        expect(game.live.askerText, 'Have you ever lied to me?');
        w.elapse(500);
        game.finalAnswer();
        w.until(() => game.phase != GamePhase.settle);
        expect(game.currentResult!.question, 'Have you ever lied to me?');
        if (game.phase == GamePhase.callIt) game.reveal();
        w.until(() => game.phase == GamePhase.verdict);

        // Next question: the room dithers, gets one, the asker reads it,
        // and then a slip onto Another one.
        game.nextQuestion();
        w.waitForPulse();
        w.elapse(300);
        w.say("I don't know");
        w.elapse(1200);
        game.suggestQuestion();
        w.elapse(500);
        final read = game.suggestion!;
        w.say(read);
        w.elapse(1500);
        game.suggestQuestion();
        expect(game.suggestion, isNot(read));
        w.elapse(500);
        game.doneAsking();
        expect(game.live.askerText, read, reason: 'not the dithering');
        w.dispose();
      });
    });

    test('No clean read, then Ask it again: the card is still there and the '
        'question scores', () {
      fakeAsync((async) {
        final w = party(async);
        final game = w.game;
        game.suggestQuestion();
        final card = game.suggestion;
        w.say(card!);
        w.elapse(1500);
        game.doneAsking();
        // Sam leaves the frame for the whole answer.
        w.code = 'NO_FACE_FOUND';
        w.elapse(3000);
        game.finalAnswer();
        w.until(() => game.phase != GamePhase.settle);
        expect(game.phase, GamePhase.redo);
        w.code = 'OK';
        w.elapse(700);
        game.askAgain();
        expect(game.suggestion, card);
        final r = w.askAndAnswer(question: card);
        expect(r.question, card);
        expect(r.scored, isTrue);
        w.dispose();
      });
    });

    test('a screenshot, then E5 and Try again: the card stays through both '
        'and nothing heard before them comes back', () {
      fakeAsync((async) {
        final w = party(async);
        final game = w.game;
        w.say('what do I ask');
        w.elapse(1000);
        game.suggestQuestion();
        final card = game.suggestion;
        w.elapse(500);
        w.leaveApp(3000);
        expect(game.waitingForPulse, isTrue);
        expect(game.suggestion, card);
        // The camera goes quiet for good: three restarts, then E5.
        w.emitting = false;
        w.until(
          () => game.phase == GamePhase.sdkOffline,
          maxMs: 60000,
          what: 'E5',
        );
        w.emitting = true;
        w.elapse(700);
        game.retrySdk();
        w.elapse(300);
        expect(game.phase, GamePhase.ask);
        expect(game.suggestion, card);
        w.waitForPulse();
        w.elapse(300);
        // Nothing asked since: Done asking has no "what do I ask" to take
        // back, because the question started over twice.
        game.doneAsking();
        expect(game.live.askerText, '');
        w.dispose();
      });
    });

    test('the recognizer gives up after the tap: the game plays on without '
        'transcripts', () {
      fakeAsync((async) {
        final w = party(async);
        final game = w.game;
        w.say('what do I ask');
        w.elapse(1000);
        game.suggestQuestion();
        w.elapse(300);
        w.speech.controller.add(
          const SpeechError('RECOGNIZER_FAILING', 'cancelled', 0),
        );
        w.elapse(300);
        expect(game.micEnabled, isFalse);
        expect(game.suggestion, isNotNull);
        game.suggestQuestion();
        w.elapse(700);
        game.doneAsking();
        expect(game.phase, GamePhase.answer);
        w.elapse(1500);
        game.finalAnswer();
        w.until(() => game.phase != GamePhase.settle);
        expect(game.currentResult!.scored, isTrue);
        w.dispose();
      });
    });
  });

  group('scale and cost', () {
    test('8 players × 7 questions, three suggestions on every one: the '
        'decks never run dry, repeat back to back or slow the game', () {
      fakeAsync((async) {
        final w = World(async);
        const names = [
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
        final game = w.game;
        var dealt = 0;
        final sw = Stopwatch();
        for (var p = 0; p < names.length; p++) {
          w.calibrate();
          for (var q = 0; q < 7; q++) {
            w.waitForPulse();
            w.elapse(300);
            w.say('um');
            String? last;
            for (var i = 0; i < 3; i++) {
              w.elapse(700);
              sw.start();
              game.suggestQuestion();
              sw.stop();
              final card = game.suggestion!;
              expect(card, isNotEmpty);
              expect(card, isNot(last), reason: 'the same card twice running');
              last = card;
              dealt++;
            }
            final r = w.askAndAnswer(question: last!);
            expect(r.question, last, reason: 'turn $p question $q');
            expect(r.scored, isTrue);
            game.nextQuestion();
            w.elapse(100);
          }
        }
        expect(game.phase, GamePhase.leaderboard);
        expect(dealt, 168);
        expect(game.awards!.ranked.length, 8);
        // Measured (JIT, cloud container): about 22 µs a tap.
        final us = sw.elapsedMicroseconds / dealt;
        expect(us, lessThan(1000), reason: '$us µs a suggestion');
        w.dispose();
      });
    });

    test('a suggested question left for 20 minutes costs the same per tick, '
        'with the question it replaced still kept aside', () {
      fakeAsync((async) {
        final w = World(async);
        w.heart = (_) => 72;
        w.startGame(['Sam', 'Alex'], questions: 2);
        w.calibrate();
        w.askAndAnswer(); // warms up the JIT
        w.game.nextQuestion();
        w.waitForPulse();
        w.elapse(300);
        w.say('Have you ever lied?');
        w.elapse(1000);
        w.game.suggestQuestion();
        double usPerTick(int ms) {
          final sw = Stopwatch()..start();
          w.elapse(ms);
          return sw.elapsedMicroseconds / (ms / 100);
        }

        final early = usPerTick(10000);
        w.elapse(20 * 60000);
        final late = usPerTick(10000);
        expect(w.game.phase, GamePhase.ask);
        // Measured (JIT, cloud container): 30–65 µs a tick, early and late.
        expect(late, lessThan(2000), reason: '$late µs a tick ($early early)');
        // Nothing was heard in those 20 minutes: the question is still the
        // one asked before the tap.
        w.game.doneAsking();
        expect(w.game.live.askerText, 'Have you ever lied?');
        w.dispose();
      });
    });

    test('awards for 8 players, 7 questions and 7 votes each, with ties at '
        'both ends, in well under a frame', () {
      final players = [
        for (var i = 0; i < 8; i++) Player(id: 'p$i', name: 'P$i'),
      ];
      QuestionResult result(int index, int score, int turn) {
        final r = QuestionResult(
          index: index,
          question: 'Q$index',
          answer: '',
          timing: null,
          breakdown: ScoreBreakdown(
            zPulse: 0,
            zBlink: 0,
            zExpr: 0,
            zHesitation: 0,
            raw: score / 100,
            score: score,
            verdict: verdictFor(score, legitBelow: 35, susFrom: 60),
          ),
        );
        for (var v = 0; v < 8; v++) {
          if (v != turn) r.votes['p$v'] = v.isEven ? Vote.legit : Vote.sus;
        }
        return r;
      }

      // P0–P2 all zeros, P5–P7 all 80, the two in between at 40.
      final turns = [
        for (var t = 0; t < 8; t++)
          PlayerTurn(players[t])
            ..results.addAll([
              for (var q = 0; q < 7; q++)
                result(q, t < 3 ? 0 : (t < 5 ? 40 : 80), t),
            ]),
      ];
      final sw = Stopwatch()..start();
      late Awards awards;
      for (var i = 0; i < 200; i++) {
        awards = Awards.compute(turns, mode: GameMode.party);
      }
      final us = sw.elapsedMicroseconds / 200;
      expect(awards.pokerFace!.names, 'P0, P1 & P2');
      expect(awards.mostSus!.names, 'P5, P6 & P7');
      expect(
        [for (var i = 0; i < 8; i++) awards.placeOf(i)],
        [
          1, 1, 1, 4, 4, 6, 6, 6, //
        ],
      );
      expect(awards.lieDetector!.players.length, greaterThan(1));
      // Measured (JIT, cloud container): 60–85 µs.
      expect(us, lessThan(2000), reason: '$us µs');
    });
  });
}
