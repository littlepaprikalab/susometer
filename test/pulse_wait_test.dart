import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/game/scoring_config.dart';

import 'world.dart';

/// The gate before decision 79: a pulse sample counted only if validation
/// was OK the moment it arrived, and stayed current for 3 s.
const oldGate = ScoringConfig(pulseValidationGraceMs: 0, pulseFreshMs: 3000);

/// Party question tapped through like [World.askAndAnswer], but it may come
/// out No clean read: returns the phase after Locking in the reading…, and
/// skips the question if it was No clean read.
GamePhase answerOnce(World w) {
  expect(w.game.phase, GamePhase.ask);
  w.waitForPulse();
  w.elapse(300);
  w.say('Have you ever re-gifted a present?');
  w.elapse(4000);
  w.game.doneAsking();
  w.elapse(1200);
  w.talk(true);
  w.say('No way. Okay, maybe once.');
  w.elapse(5000);
  w.talk(false);
  w.elapse(800);
  w.game.finalAnswer();
  w.until(() => w.game.phase != GamePhase.settle, what: 'settle');
  final after = w.game.phase;
  if (after == GamePhase.redo) {
    w.game.skipQuestion();
    w.elapse(100);
    return after;
  }
  if (w.game.phase == GamePhase.callIt) w.game.reveal();
  w.until(() => w.game.phase == GamePhase.verdict, what: 'countdown');
  if (!w.game.isLastQuestion) {
    w.elapse(700);
    w.game.nextQuestion();
    w.elapse(100);
  }
  return after;
}

void main() {
  group('a question waits for the pulse (decision 79)', () {
    test('the camera freezes mid-answer: the re-asked question waits, '
        'then scores', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex'], questions: 2);
        w.calibrate();
        expect(
          w.game.waitingForPulse,
          isFalse,
          reason: 'calibration had a pulse: question 1 starts at once',
        );
        w.say('Have you ever lied?');
        w.elapse(500);
        w.game.doneAsking();
        w.talk(true);
        // The preview stalls; the watchdog restarts the camera.
        final starts = w.sdkCalls('start');
        w.cameraFrozen = true;
        w.until(() => w.sdkCalls('start') > starts, what: 'the restart');
        w.cameraFrozen = false;
        w.talk(false);
        w.elapse(300);
        final heldAt = w.now;
        final said = w.host.said.length;
        expect(w.game.phase, GamePhase.ask);
        expect(w.game.waitingForPulse, isTrue);
        expect(w.game.detector, isNull);
        // Nothing but Pause does anything while it waits.
        w.game.doneAsking();
        w.game.finalAnswer();
        w.elapse(5000);
        expect(w.game.phase, GamePhase.ask);
        expect(w.host.said.length, said, reason: 'no ask line while waiting');
        w.waitForPulse();
        final held = w.now - heldAt;
        expect(held, greaterThan(w.pulseWarmupMs - 1000));
        expect(held, lessThan(w.pulseWarmupMs + 1500));
        expect(w.host.said.last, 'Alex, ask your question!');
        expect(w.game.detector, isNotNull);
        // Before decision 79 it started at once, with no pulse for its
        // first 12 s, and was No clean read every time.
        final r = w.askAndAnswer();
        expect(r.scored, isTrue);
        expect(r.index, 0);
        w.dispose();
      });
    });

    test('a screenshot mid-question: the pulse from before the trip '
        "doesn't end the wait", () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex'], questions: 2);
        w.calibrate();
        w.say('Have you ever lied?');
        w.elapse(500);
        w.game.doneAsking();
        w.leaveApp(2000);
        expect(w.game.paused, isFalse, reason: 'a short trip carries on');
        expect(w.game.phase, GamePhase.ask);
        // The last confident pulse is only a few seconds old, but it's from
        // the camera session the trip stopped.
        final last = w.game.log.lastConfidentPulseMs!;
        expect(w.now - last, lessThan(w.game.config.pulseFreshMs));
        expect(w.game.waitingForPulse, isTrue);
        w.waitForPulse();
        expect(w.game.log.lastConfidentPulseMs, greaterThan(last));
        final r = w.askAndAnswer();
        expect(r.scored, isTrue);
        w.dispose();
      });
    });

    test('solo: the card waits unread, its buttons and the room do nothing, '
        'and Skip from Pause moves on', () {
      fakeAsync((async) {
        final w = World(async);
        w.game.setMode(GameMode.solo);
        w.startGame(['Sam'], questions: 3);
        w.calibrate();
        w.waitForPulse();
        // The camera stops sending: restarted, the question waits.
        w.emitting = false;
        w.elapse(6500);
        w.emitting = true;
        w.elapse(500);
        expect(w.game.waitingForPulse, isTrue);
        final card = w.game.questionText;
        final said = w.host.said.length;
        w.game.differentQuestion();
        w.elapse(700);
        w.game.readyToAnswer();
        w.say('so anyway, did you see the game last night');
        w.elapse(700);
        expect(w.game.questionText, card, reason: 'the same card');
        expect(w.game.shownPhase, GamePhase.ask);
        expect(w.host.said.length, said, reason: 'not read while waiting');
        expect(w.game.live.answerText, isEmpty, reason: 'chatter is dropped');
        // Pause, then Skip question.
        w.game.pause();
        expect(w.game.paused, isTrue);
        w.game.skipQuestion();
        w.elapse(100);
        expect(w.game.currentTurn.results.single.skipped, isTrue);
        expect(w.game.questionIndex, 1);
        expect(w.game.phase, GamePhase.ask);
        expect(
          w.game.waitingForPulse,
          isTrue,
          reason: 'the camera is still warming up',
        );
        w.waitForPulse();
        expect(w.host.said.last, contains(w.game.questionText));
        w.dispose();
      });
    });

    test('a wait that drags on says what to do, and ends when the light '
        'comes back', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex'], questions: 2);
        w.calibrate();
        w.askAndAnswer();
        // The room goes dark during the verdict.
        w.code = 'TOO_DARK';
        w.elapse(8000);
        w.game.nextQuestion();
        w.elapse(100);
        expect(w.game.waitingForPulse, isTrue);
        expect(w.game.visibleIssue?.code, 'TOO_DARK', reason: 'E3 stamp');
        expect(w.game.pulseWaitIsLong, isFalse);
        w.elapse(w.game.config.pulseWaitHintAfterMs);
        expect(w.game.pulseWaitIsLong, isTrue);
        expect(w.game.phase, GamePhase.ask, reason: 'still waiting, no timer');
        w.code = 'OK';
        w.until(() => !w.game.waitingForPulse, maxMs: 2500);
        expect(w.game.pulseWaitIsLong, isFalse);
        expect(w.game.detector, isNotNull);
        w.dispose();
      });
    });

    test('Pause during the wait, then Resume: it waits again until the '
        'pulse is back', () {
      fakeAsync((async) {
        final w = World(async);
        w.startGame(['Sam', 'Alex'], questions: 2);
        w.calibrate();
        w.code = 'NO_FACE_FOUND';
        w.askAndAnswerUntilRedo();
        w.game.askAgain();
        w.elapse(100);
        expect(w.game.waitingForPulse, isTrue);
        w.game.pause();
        w.code = 'OK';
        w.elapse(4000);
        expect(w.game.waitingForPulse, isTrue, reason: 'nothing moves paused');
        w.game.resume();
        w.elapse(100);
        // Back with a fresh pulse (the camera ran all along): it starts.
        w.until(() => !w.game.waitingForPulse, maxMs: 1500);
        expect(w.game.detector, isNotNull);
        w.dispose();
      });
    });
  });

  group('the gate allows a passing problem (decision 79)', () {
    /// A real party: the hot seat looks at the room 3 s of every 4 while a
    /// question runs, and the SDK's pulse comes every 2 s.
    int noCleanReads(ScoringConfig config) {
      var n = 0;
      fakeAsync((async) {
        final w = World(async, config: config)..pulseEveryMs = 2000;
        w.startGame(['Sam', 'Alex'], questions: 3);
        w.calibrate();
        w.codeAt = (t) {
          const measuring = {GamePhase.ask, GamePhase.answer, GamePhase.settle};
          if (!measuring.contains(w.game.phase) || w.game.waitingForPulse) {
            return null;
          }
          return t % 4000 < 3000 ? 'FACE_NOT_FORWARD' : null;
        };
        for (var q = 0; q < 3; q++) {
          if (answerOnce(w) == GamePhase.redo) n++;
        }
        w.dispose();
      });
      return n;
    }

    test('looking at the asker most of the time still reads', () {
      expect(noCleanReads(const ScoringConfig()), 0);
    });

    test('the old gate called the same questions No clean read', () {
      expect(noCleanReads(oldGate), greaterThan(0));
    });
  });
}

extension on World {
  /// A party question with the face gone, tapped through to No clean read.
  void askAndAnswerUntilRedo() {
    expect(game.phase, GamePhase.ask);
    elapse(300);
    say('Have you ever read a diary?');
    elapse(500);
    game.doneAsking();
    elapse(3000);
    game.finalAnswer();
    until(() => game.phase != GamePhase.settle, what: 'settle');
    expect(game.phase, GamePhase.redo);
  }
}
