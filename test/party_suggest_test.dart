// Party "Suggest one" (SPEC.md decision 81): a deck question for an asker
// with nothing to ask. It's a prompt on the card, not the question: the
// asker still says it out loud, and the game times and records what it hears.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/decks.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/voice/speech_service.dart';

import 'world.dart';

List<String> heat(List<DeckQuestion> deck, int h) => [
  for (final q in deck)
    if (q.heat == h) q.text,
];

void main() {
  final mild = DeckLibrary.fallback.mild;
  final spicy = DeckLibrary.fallback.spicy;

  /// Three players, three questions, calibrated and asking question 1.
  World party(FakeAsync async, {DeckKind deck = DeckKind.mild}) {
    final w = World(async);
    w.game.setDeck(deck);
    w.startGame(['Sam', 'Alex', 'Priya'], questions: 3);
    w.calibrate();
    w.waitForPulse();
    w.elapse(300);
    return w;
  }

  test('Suggest one deals from the lobby deck at the heat solo would use, '
      'and Another one changes it', () {
    fakeAsync((async) {
      final w = party(async);
      final game = w.game;
      expect(game.suggestion, isNull);

      game.suggestQuestion();
      final first = game.suggestion;
      expect(heat(mild, 1), contains(first), reason: 'question 1 opens mild');
      expect(game.phase, GamePhase.ask, reason: 'nothing moves on');

      // A double tap counts once.
      game.suggestQuestion();
      expect(game.suggestion, first);
      w.elapse(700);
      game.suggestQuestion();
      expect(heat(mild, 1), contains(game.suggestion));
      expect(game.suggestion, isNot(first));

      // The turn's last question gets the hottest pile.
      w.askAndAnswer();
      game.nextQuestion();
      w.askAndAnswer();
      game.nextQuestion();
      w.waitForPulse();
      expect(game.isLastQuestion, isTrue);
      game.suggestQuestion();
      expect(heat(mild, 3), contains(game.suggestion));
      w.dispose();
    });
  });

  test('it deals from the Spicy deck when the lobby chose it', () {
    fakeAsync((async) {
      final w = party(async, deck: DeckKind.spicy);
      w.game.suggestQuestion();
      expect(heat(spicy, 1), contains(w.game.suggestion));
      w.dispose();
    });
  });

  test("what the room said while it wondered isn't the question, and the "
      "question's window opens after the tap", () {
    fakeAsync((async) {
      final w = party(async);
      final game = w.game;
      w.say("uh I don't know what to ask");
      w.elapse(2500);
      expect(game.live.askerText, "uh I don't know what to ask");
      expect(game.detector!.tQ0, isNotNull);
      final oldSegment = w.speech.segment;

      final tappedAt = w.now;
      game.suggestQuestion();
      w.elapse(100);
      expect(game.live.askerText, '', reason: 'listening starts over');
      expect(game.detector!.tQ0, isNull);
      // The old segment's last partial arrives late, carrying all of it.
      w.speech.controller.add(
        SpeechText(
          text: "uh I don't know what to ask give us one",
          segment: oldSegment,
          isFinal: true,
          tMs: w.now,
        ),
      );
      w.elapse(100);
      expect(game.live.askerText, '');

      final asked = game.suggestion!;
      final r = w.askAndAnswer(question: asked);
      expect(r.question, asked, reason: 'what was heard, as always');
      expect(r.timing!.tQ0, greaterThan(tappedAt));
      expect(r.scored, isTrue);
      w.dispose();
    });
  });

  test("a slow recognizer: the room's words in the gap don't come back as "
      'the question', () {
    fakeAsync((async) {
      final w = party(async);
      final game = w.game;
      w.say('what should I ask');
      w.elapse(1000);
      w.speech.newSegmentTakesMs = 600;
      game.suggestQuestion();
      // Until the new segment opens, partials still belong to the old one.
      w.elapse(200);
      w.say('what should I ask oh there');
      w.elapse(600);
      expect(game.live.askerText, '');
      w.speech.newSegmentTakesMs = 0;
      final r = w.askAndAnswer(question: 'Did you make your bed this morning?');
      expect(r.question, 'Did you make your bed this morning?');
      w.dispose();
    });
  });

  test("it's a prompt, not a record: asking something else, or nothing "
      'heard, never files the suggestion as the question', () {
    fakeAsync((async) {
      final w = party(async);
      final game = w.game;
      game.suggestQuestion();
      final r = w.askAndAnswer(question: 'Have you ever lied to me?');
      expect(r.question, 'Have you ever lied to me?');

      game.nextQuestion();
      w.waitForPulse();
      game.suggestQuestion();
      w.elapse(1000);
      game.skipQuestion();
      w.elapse(200);
      expect(game.currentTurn.results.last.skipped, isTrue);
      expect(game.currentTurn.results.last.question, 'Question 2');
      w.dispose();
    });
  });

  test('it stays for the same question asked again, and goes with the next '
      'question and the next player', () {
    fakeAsync((async) {
      final w = party(async);
      final game = w.game;
      game.suggestQuestion();
      final first = game.suggestion;
      expect(first, isNotNull);

      // Away long enough that the question starts over.
      w.leaveApp(GameController.autoResumeWithinMs + 5000);
      game.resume();
      w.elapse(1500);
      expect(game.phase, GamePhase.ask);
      expect(game.suggestion, first, reason: 'the same question, restarted');

      w.askAndAnswer();
      expect(game.suggestion, first, reason: 'still this question');
      game.nextQuestion();
      expect(game.suggestion, isNull, reason: 'a new question');

      w.waitForPulse();
      game.suggestQuestion();
      expect(game.suggestion, isNotNull);
      w.askAndAnswer();
      game.endTurn();
      w.elapse(200);
      expect(game.phase, GamePhase.consent);
      expect(game.suggestion, isNull, reason: "the next player's turn");
      w.dispose();
    });
  });

  test('only on a party question being asked: not paused, not while it '
      'waits for the pulse, not once the answer has started', () {
    fakeAsync((async) {
      final w = party(async);
      final game = w.game;

      game.pause();
      game.suggestQuestion();
      expect(game.suggestion, isNull, reason: 'behind the Pause sheet');
      game.resume();
      w.elapse(200);

      // A screenshot: the restarted question waits for the pulse.
      w.leaveApp(3000);
      expect(game.waitingForPulse, isTrue);
      game.suggestQuestion();
      expect(game.suggestion, isNull, reason: 'no question yet');
      w.waitForPulse();

      w.elapse(700);
      game.doneAsking();
      expect(game.phase, GamePhase.answer);
      game.suggestQuestion();
      expect(game.suggestion, isNull, reason: 'the question is over');
      w.dispose();
    });
  });

  test('solo has no suggestions: the host already asks', () {
    fakeAsync((async) {
      final w = World(async);
      w.game.setMode(GameMode.solo);
      w.startGame(['Sam'], questions: 3);
      w.calibrate();
      final dealt = w.game.questionText;
      w.game.suggestQuestion();
      expect(w.game.suggestion, isNull);
      expect(w.game.questionText, dealt);
      w.dispose();
    });
  });

  test('a new game starts without the last one\'s suggestion', () {
    fakeAsync((async) {
      final w = party(async);
      w.game.suggestQuestion();
      expect(w.game.suggestion, isNotNull);
      w.game.playAgain();
      w.elapse(200);
      expect(w.game.phase, GamePhase.lobby);
      expect(w.game.suggestion, isNull);
      w.dispose();
    });
  });
}
