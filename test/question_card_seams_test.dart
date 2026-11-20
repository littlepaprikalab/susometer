// Reliability pass over the question card (SPEC.md decision 86): the seams
// between decision 85's card-as-button, the question screens without a host
// bubble, and everything else that can happen in a turn, at scale, and what
// they cost. Through the real screens.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/presage/camera_preview.dart';
import 'package:susometer/screens/question_screens.dart';
import 'package:susometer/theme/game_widgets.dart';
import 'package:susometer/voice/speech_service.dart';

import 'rig.dart';

extension on Rig {
  Future<void> startGame(List<String> names, {int questions = 3}) async {
    presage.storedKey = 'k';
    for (final n in names) {
      await addPlayer(n);
    }
    if (questions != 1) await tap('$questions');
    await tap('Start the show');
    await wait(300);
    if (game.phase == GamePhase.howToPlay) await tap("Got it, let's play");
  }

  /// Solo, at the first question's card, read out and held.
  Future<void> soloToCard({
    Size size = const Size(390, 844),
    int questions = 3,
  }) async {
    await pumpApp(size: size);
    await tap('Solo · host asks');
    await startGame(['Sam'], questions: questions);
    await tap('I agree, measure me');
    await heldCard();
  }

  /// The host has read the question, and the card waits for its tap.
  Future<void> heldCard() async {
    await until(() => game.soloHoldsQuestion, what: 'the host to read');
    await wait(600);
  }

  /// A deliberate tap on the question, the way a player would.
  Future<void> tapCard() async {
    await waitOutTapGuard(tester);
    await tester.tapAt(tester.getCenter(find.text(game.questionText)));
    await tester.pump(const Duration(milliseconds: 60));
  }

  /// An answer and Final answer, through to the Verdict.
  Future<void> answerToVerdict() async {
    presage.talk(true);
    await wait(1500);
    presage.talk(false);
    await wait(600);
    await tap('Final answer');
    await until(() => game.phase == GamePhase.verdict, what: 'the verdict');
    await wait(300);
  }
}

/// Where the drawn button's face is: it moves down onto its shadow while
/// the card is pressed.
double faceTop(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(readyFaceKey)).dy;

/// [text] shows whole: not cut to its first lines, and not clipped to its
/// last.
void expectWhole(WidgetTester tester, String text, String when) {
  final found = find.text(text);
  expect(found, findsOneWidget, reason: '$when: "$text"');
  expect(
    tester.renderObject<RenderParagraph>(found).didExceedMaxLines,
    isFalse,
    reason: '$when: "$text" lost its end',
  );
  expect(
    find.ancestor(of: found, matching: find.byType(ClipRect)),
    findsNothing,
    reason: '$when: "$text" lost its start',
  );
}

void main() {
  group('taps that arrive from the screen before', () {
    testWidgets('a double tap on Next question neither skips the next card '
        'nor answers it', (tester) async {
      // Different question now fills the row where Next question was, and
      // the card is a button the whole width of the screen.
      final rig = Rig(tester);
      await rig.soloToCard();
      await rig.tapCard();
      await rig.answerToVerdict();
      final next = tester.getCenter(find.text('Next question'));
      await waitOutTapGuard(tester);
      await tester.tapAt(next);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 60));
      expect(rig.game.questionIndex, 1);
      final dealt = rig.game.questionText;
      // The second touch of the double tap, and a stray one on the card.
      await tester.tapAt(next);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(195, 200));
      await tester.pump(const Duration(milliseconds: 50));
      expect(rig.game.questionText, dealt, reason: 'the card was skipped');
      expect(rig.game.shownPhase, GamePhase.ask, reason: 'answered blind');
      await rig.heldCard();
      expect(rig.game.questionText, dealt);
      expect(find.text(readyCardLabel), findsOneWidget);
      // Deliberate taps still work, on both.
      await rig.tap('Different question');
      expect(rig.game.questionText, isNot(dealt));
      await rig.heldCard();
      await rig.tapCard();
      expect(rig.game.soloHoldsQuestion, isFalse);
      expect(tester.takeException(), isNull);
      await rig.finish();
    });

    testWidgets('a double tap on the card lands on nothing: the answer '
        'stays open', (tester) async {
      // Ready to answer used to sit where Final answer appears.
      final rig = Rig(tester);
      await rig.soloToCard();
      final at = tester.getCenter(find.text(rig.game.questionText));
      await waitOutTapGuard(tester);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 100));
      expect(rig.game.phase, GamePhase.answer);
      expect(find.text('Final answer'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await rig.finish();
    });
  });

  group('the press', () {
    testWidgets('the drawn button goes down under a finger anywhere on the '
        'card, and a finger that slides off takes nothing with it', (
      tester,
    ) async {
      final rig = Rig(tester);
      await rig.soloToCard();
      final q = rig.game.questionText;
      final up = faceTop(tester);
      await waitOutTapGuard(tester);
      // On the question, not on the drawn button.
      final finger = await tester.startGesture(tester.getCenter(find.text(q)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(faceTop(tester), greaterThan(up + 3), reason: 'not pressed');
      expect(rig.game.soloHoldsQuestion, isTrue, reason: 'acts on release');
      // The deck moves on under the finger: the press stays with the card.
      rig.game.differentQuestion();
      await tester.pump(const Duration(milliseconds: 100));
      expect(rig.game.questionText, isNot(q));
      expect(faceTop(tester), greaterThan(up + 3));
      // Slides off, down over the camera.
      await finger.moveBy(const Offset(0, 320));
      await finger.up();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(faceTop(tester), closeTo(up, 0.01), reason: 'stuck down');
      expect(rig.game.shownPhase, GamePhase.ask, reason: 'a slide answered');
      // The next card starts up, whatever the last one was doing.
      await rig.heldCard();
      final held = await tester.startGesture(
        tester.getCenter(find.text(rig.game.questionText)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await held.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(rig.game.soloHoldsQuestion, isFalse);
      await rig.answerToVerdict();
      await rig.tap('Next question');
      await rig.heldCard();
      expect(faceTop(tester), closeTo(up, 0.01), reason: 'born pressed');
      expect(tester.takeException(), isNull);
      await rig.finish();
    });
  });

  group('the card through a turn', () {
    testWidgets('tapped while the host is still reading: the host stops and '
        'the answer opens', (tester) async {
      final rig = Rig(tester);
      await rig.soloToCard();
      await rig.tapCard();
      await rig.answerToVerdict();
      // The next question's line stays in the air.
      rig.host.hold = true;
      await rig.tap('Next question');
      await rig.until(
        () => rig.game.phase == GamePhase.ask && !rig.game.waitingForPulse,
        what: 'question 2',
      );
      await rig.wait(300);
      expect(rig.game.phase, GamePhase.ask, reason: 'still reading');
      expect(find.text(readyCardLabel), findsOneWidget);
      final q = rig.game.questionText;
      final calls = rig.host.calls.length;
      await rig.tapCard();
      expect(rig.host.calls.sublist(calls), contains('stop'));
      expect(rig.game.phase, GamePhase.answer);
      expect(rig.game.soloHoldsQuestion, isFalse);
      expect(find.text('Q: “$q”'), findsOneWidget);
      rig.host.hold = false;
      expect(tester.takeException(), isNull);
      await rig.finish();
    });

    testWidgets('behind Pause nothing reaches it, and Resume brings the '
        'card back, not pressed', (tester) async {
      final rig = Rig(tester);
      await rig.soloToCard();
      final q = rig.game.questionText;
      final at = tester.getCenter(find.text(q));
      final up = faceTop(tester);
      await waitOutTapGuard(tester);
      await tester.tap(find.bySemanticsLabel('Pause the game'));
      await rig.wait(300);
      expect(rig.game.paused, isTrue);
      // VoiceOver finds only the sheet.
      final handle = tester.ensureSemantics();
      expect(find.semantics.byLabel(q), findsNothing);
      handle.dispose();
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 100));
      rig.game.readyToAnswer(); // VoiceOver, were it to get through
      await tester.pump(const Duration(milliseconds: 100));
      expect(rig.game.shownPhase, GamePhase.ask, reason: 'answered paused');
      await rig.tap('Resume');
      // Resume asks the question again from the top.
      await rig.heldCard();
      expect(rig.game.questionText, q);
      expect(faceTop(tester), closeTo(up, 0.01));
      await rig.tapCard();
      expect(find.text('Q: “$q”'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await rig.finish();
    });

    testWidgets('a trip out of the app while the card waits: no button '
        'during the wait for the pulse, then the same card', (tester) async {
      final rig = Rig(tester);
      await rig.soloToCard();
      final q = rig.game.questionText;
      final at = tester.getCenter(find.text(q));
      final camera = tester.getRect(find.byType(CameraPreview));
      // A screenshot's preview: the camera restarts with no pulse.
      await rig.leaveApp(2000);
      expect(rig.game.waitingForPulse, isTrue);
      expect(find.byKey(readyFaceKey), findsNothing);
      expect(find.byType(HostBubble), findsNothing);
      expect(tester.getRect(find.byType(CameraPreview)), camera);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 100));
      expect(rig.game.waitingForPulse, isTrue);
      await rig.until(() => !rig.game.waitingForPulse, what: 'the pulse');
      await rig.heldCard();
      expect(rig.game.questionText, q, reason: 'a different card');
      expect(tester.getRect(find.byType(CameraPreview)), camera);
      await rig.tapCard();
      expect(find.text('Q: “$q”'), findsOneWidget);
      expect(tester.getRect(find.byType(CameraPreview)), camera);
      expect(tester.takeException(), isNull);
      await rig.finish();
    });

    testWidgets('VoiceOver: the card is one button, and activating it '
        'opens the answer', (tester) async {
      final rig = Rig(tester);
      await rig.soloToCard();
      final q = rig.game.questionText;
      final handle = tester.ensureSemantics();
      final card = find.semantics.byLabel(q);
      expect(card, findsOne);
      await waitOutTapGuard(tester);
      tester.semantics.tap(card);
      await tester.pump(const Duration(milliseconds: 60));
      handle.dispose();
      expect(rig.game.soloHoldsQuestion, isFalse);
      expect(find.text('Q: “$q”'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await rig.finish();
    });

    testWidgets('No clean read, then Ask it again: the same card comes '
        'back and answers', (tester) async {
      final rig = Rig(tester);
      await rig.soloToCard();
      final q = rig.game.questionText;
      final camera = tester.getRect(find.byType(CameraPreview));
      // The player leaves the frame, from the card through the answer.
      rig.presage.code = 'NO_FACE_FOUND';
      await rig.wait(2500);
      expect(rig.game.visibleIssue, isNotNull, reason: 'E3 stamp');
      await rig.tapCard();
      await rig.wait(6000);
      await rig.tap('Final answer');
      await rig.until(() => rig.game.phase == GamePhase.redo, what: 'E4');
      rig.presage.code = 'OK';
      await rig.tap('Ask it again');
      await rig.heldCard();
      expect(rig.game.questionText, q);
      expect(find.text(readyCardLabel), findsOneWidget);
      expect(tester.getRect(find.byType(CameraPreview)), camera);
      // A camera problem while the card waits leaves it a button.
      rig.presage.code = 'EXCESSIVE_MOTION';
      await rig.wait(2500);
      expect(find.text('Hold still'), findsOneWidget, reason: 'E3 stamp');
      await rig.tapCard();
      expect(rig.game.soloHoldsQuestion, isFalse);
      expect(find.text('Q: “$q”'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await rig.finish();
    });

    testWidgets('the Proof Panel leaves the card to the finger on the '
        'smaller phone', (tester) async {
      final rig = Rig(tester);
      await rig.soloToCard(size: const Size(375, 667));
      rig.services.settings.proofPanel = true;
      await rig.wait(500);
      await waitOutTapGuard(tester);
      // On the drawn button, the card's lowest part.
      await tester.tap(find.byKey(readyFaceKey));
      await tester.pump(const Duration(milliseconds: 60));
      expect(rig.game.soloHoldsQuestion, isFalse);
      expect(tester.takeException(), isNull);
      await rig.finish();
    });

    testWidgets('nothing asks for an answer once it is locking in', (
      tester,
    ) async {
      // The bubble said "Sam, your answer?" through Settle too.
      final rig = Rig(tester);
      await rig.soloToCard();
      await rig.tapCard();
      expect(find.text('Sam, your answer?'), findsOneWidget);
      // A silent answer.
      await rig.wait(1500);
      await rig.tap('Final answer');
      await rig.wait(200);
      expect(rig.game.phase, GamePhase.settle);
      expect(find.text('Sam, your answer?'), findsNothing);
      expect(find.text('…'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await rig.finish();
    });
  });

  group('without the mic', () {
    testWidgets('the cards carry the lines, whole, with the longest names on '
        'the smaller phone at the largest text', (tester) async {
      const seat = 'Christopher-Alexandr';
      const asker = 'Maximilian-Sebastian';
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = Rig(tester);
      await rig.pumpApp(size: const Size(375, 667));
      rig.game.hasSeenHowToPlay = true;
      rig.speech.permissions = const SpeechPermissions(
        mic: 'denied',
        speech: 'authorized',
        onDevice: true,
      );
      await rig.startGame([seat, asker]);
      await rig.tap('Play without voice');
      await rig.wait(200);
      await rig.tap('I agree, measure me');
      await rig.until(
        () => rig.game.phase == GamePhase.ask && !rig.game.waitingForPulse,
        what: 'question 1',
      );
      await rig.wait(300);
      expect(rig.game.micEnabled, isFalse);
      expect(find.byType(HostBubble), findsNothing);
      expectWhole(
        tester,
        '$asker, ask your question, then tap Done asking.',
        'no mic',
      );
      await rig.tap('Done asking');
      expectWhole(tester, '$seat, answer out loud.', 'no mic');
      expect(tester.takeException(), isNull);
      await rig.finish();
    });
  });

  group('scale', () {
    for (final screen in const [Size(390, 844), Size(375, 667)]) {
      testWidgets('the longest names: the ask line and the answer prompt '
          'show whole (${screen.width.round()}×${screen.height.round()}, '
          'text ×1.3)', (tester) async {
        // Twenty characters, the most the lobby takes.
        const seat = 'Christopher-Alexandr';
        const asker = 'Maximilian-Sebastian';
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final rig = Rig(tester);
        await rig.pumpApp(size: screen);
        await rig.startGame([seat, asker]);
        expect(rig.game.turns.map((t) => t.player.name), [seat, asker]);
        await rig.tap('I agree, measure me');
        await rig.until(
          () => rig.game.phase == GamePhase.ask && !rig.game.waitingForPulse,
          what: 'question 1',
        );
        await rig.wait(300);
        expectWhole(tester, '$asker, ask your question!', 'ask');
        final camera = tester.getRect(find.byType(CameraPreview));
        await rig.tap('Done asking');
        expectWhole(tester, '$seat, your answer?', 'answer');
        expect(tester.getRect(find.byType(CameraPreview)), camera);
        expect(tester.takeException(), isNull);
        await rig.finish();
      });
    }

    testWidgets('a 5-question solo game, two Different questions on each: '
        'every card answers as itself', (tester) async {
      final rig = Rig(tester);
      await rig.soloToCard(questions: 5);
      final up = faceTop(tester);
      final camera = tester.getRect(find.byType(CameraPreview));
      final answered = <String>[];
      for (var q = 0; q < 5; q++) {
        await rig.heldCard();
        for (var i = 0; i < 2; i++) {
          final before = rig.game.questionText;
          await rig.tap('Different question');
          await rig.wait(700);
          expect(rig.game.questionText, isNot(before));
        }
        await rig.heldCard();
        expect(rig.game.questionIndex, q, reason: 'a card ran on');
        expect(faceTop(tester), closeTo(up, 0.01));
        expect(tester.getRect(find.byType(CameraPreview)), camera);
        final text = rig.game.questionText;
        answered.add(text);
        await rig.tapCard();
        expect(find.text('Q: “$text”'), findsOneWidget);
        expect(tester.getRect(find.byType(CameraPreview)), camera);
        await rig.answerToVerdict();
        await rig.tap(q == 4 ? 'See the winners' : 'Next question');
      }
      expect(rig.game.turns.single.results.map((r) => r.question), answered);
      expect(
        rig.game.turns.single.results.every((r) => r.scored),
        isTrue,
        reason: 'a question went unscored',
      );
      expect(tester.takeException(), isNull);
      await rig.finish();
    });
  });

  group('cost', () {
    testWidgets('the card draws at about the cost of the answer card', (
      tester,
    ) async {
      // It measures its question to pick a size on every rebuild, with a
      // size more to try, and draws a turned button.
      final rig = Rig(tester);
      await rig.soloToCard();

      Future<double> msPerFrame() async {
        final sw = Stopwatch()..start();
        for (var i = 0; i < 100; i++) {
          rig.say(List.filled(1 + i % 12, 'maybe').join(' '));
          rig.speech.controller.add(
            SpeechLevel(0.2 + 0.1 * (i % 7), rig.presage.now),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        sw.stop();
        return sw.elapsedMicroseconds / 100000;
      }

      await msPerFrame(); // warm up
      final card = await msPerFrame();
      await rig.tapCard();
      await rig.wait(300);
      final answer = await msPerFrame();
      // ignore: avoid_print
      print(
        'Solo frame: ${card.toStringAsFixed(2)} ms on the question card, '
        '${answer.toStringAsFixed(2)} ms on the answer card (debug)',
      );
      expect(card, lessThan(answer * 2 + 2), reason: '$card vs $answer');
      expect(tester.takeException(), isNull);
      await rig.finish();
    });
  });
}
