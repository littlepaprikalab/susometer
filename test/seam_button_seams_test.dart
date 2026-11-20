// Reliability pass over the buttons on the seam (SPEC.md decision 91): the
// seams between decision 90's buttons and hints and everything else that can
// happen in a game, at scale, and what they cost. Through the real screens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/debug/proof_panel.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/presage/camera_preview.dart';
import 'package:susometer/screens/question_screens.dart';
import 'package:susometer/theme/expression_stamp.dart';
import 'package:susometer/theme/game_widgets.dart';
import 'package:susometer/theme/seam_button.dart';
import 'package:susometer/theme/tokens.dart';
import 'package:susometer/theme/widgets.dart';
import 'package:susometer/voice/speech_service.dart';

import 'rig.dart';
import 'seam_geometry.dart';

extension on Rig {
  Future<void> startGame(
    List<String> names, {
    int questions = 3,
    bool solo = false,
  }) async {
    presage.storedKey = 'k';
    if (solo) await tap('Solo · host asks');
    for (final n in names) {
      await addPlayer(n);
    }
    // The lobby offers 1, 3 and 5; longer turns are set directly.
    if (const [3, 5].contains(questions)) {
      await tap('$questions');
    } else if (questions != 1) {
      game.setQuestionsPerTurn(questions);
    }
    await tap('Start the show');
    await wait(300);
    if (game.phase == GamePhase.howToPlay) await tap("Got it, let's play");
  }

  /// Through calibration (tapped by [until]) to a question whose pulse is
  /// in, with its button popped in.
  Future<void> toQuestion() async {
    autoTaps = true;
    if (game.phase == GamePhase.consent) await tap('I agree, measure me');
    await until(() => game.shownPhase == GamePhase.ask, what: 'the question');
    await until(() => !game.waitingForPulse, what: 'the pulse');
    await wait(SeamButton.entrance.inMilliseconds + 100);
  }

  /// An answer, out loud.
  Future<void> answerOutLoud() async {
    presage.talk(true);
    await wait(1500);
    presage.talk(false);
    await wait(600);
  }

  /// A second touch where the first one was, 120 ms later: a quick double
  /// tap.
  Future<void> tapTwice(Offset at) async {
    await waitOutTapGuard(tester);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Rect seamButton(WidgetTester tester) => tester.getRect(find.byType(SeamButton));
Rect pauseButton(WidgetTester tester) => tester.getRect(leadingButton());
Rect cameraRect(WidgetTester tester) =>
    tester.getRect(find.byType(CameraWindow));

/// How much of its own size [finder]'s text is drawn at (1 when not
/// shrunk).
double drawnScale(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  final left = box.localToGlobal(Offset.zero).dx;
  final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
  return (right - left) / box.size.width;
}

/// The text of [options] that's on screen (a hint or a shorter form).
Finder shown(List<String> options) {
  for (final o in options) {
    final f = find.text(o);
    if (f.evaluate().isNotEmpty) return f;
  }
  fail('none of $options on screen');
}

void main() {
  group('seams', () {
    testWidgets('double taps along the seam move on once', (tester) async {
      final rig = Rig(tester);
      await rig.pumpApp();
      await rig.startGame(['Sam', 'Alex']);
      await rig.tap('I agree, measure me');
      rig.autoTaps = false;
      // Each warm-up waits for Next; the last one's double tap can't also
      // start the questions, though Start lands where Next was.
      await rig.until(() {
        final w = rig.game.currentWarmup;
        if (w != null && w.latencyS != null && !rig.presage.talking) {
          rig.game.nextWarmup();
        }
        return rig.game.calibStage == CalibStage.ready;
      }, what: 'the normal to lock in');
      await tester.pump();
      final start = tester.getCenter(find.byType(SeamButton));
      await tester.tapAt(start);
      await tester.pump(const Duration(milliseconds: 60));
      expect(rig.game.phase, GamePhase.calibrate, reason: 'a tap too early');
      await rig.wait(700);
      await rig.tapTwice(tester.getCenter(find.byType(SeamButton)));
      expect(rig.game.shownPhase, GamePhase.ask);

      // Done asking, then Final answer in the same place: one tap each.
      await rig.toQuestion();
      final done = seamButton(tester);
      await rig.tapTwice(done.center);
      expect(rig.game.phase, GamePhase.answer);
      await rig.wait(SeamButton.entrance.inMilliseconds + 100);
      expect(find.text('Final answer'), findsOneWidget);
      expect(seamButton(tester).right, done.right);
      await rig.answerOutLoud();
      // Final answer, then the locking-in status where it was: one ending.
      await rig.tapTwice(seamButton(tester).center);
      expect(rig.game.phase, GamePhase.settle);
      expect(find.text('Locking in the reading…'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await rig.finish();
    });

    testWidgets('Pause: nothing on the seam can be reached behind the '
        'sheet, and it comes back where it was', (tester) async {
      final rig = Rig(tester);
      await rig.pumpApp();
      await rig.startGame(['Sam', 'Alex']);
      await rig.toQuestion();
      final done = seamButton(tester);
      final pause = pauseButton(tester);
      final camera = cameraRect(tester);
      final handle = tester.ensureSemantics();
      expect(find.semantics.byLabel('Done asking'), findsOne);
      await waitOutTapGuard(tester);
      await tester.tapAt(pause.center);
      await rig.wait(300);
      expect(rig.game.paused, isTrue);
      // By touch or by VoiceOver.
      await tester.tapAt(done.center);
      await rig.wait(100);
      expect(rig.game.phase, GamePhase.ask);
      expect(find.semantics.byLabel('Done asking'), findsNothing);
      expect(find.semantics.byLabel('Pause the game'), findsNothing);
      handle.dispose();
      await rig.tap('Resume');
      await rig.until(() => !rig.game.waitingForPulse, what: 'the pulse');
      await rig.wait(SeamButton.entrance.inMilliseconds + 100);
      expect(seamButton(tester), done);
      expect(pauseButton(tester), pause);
      expect(cameraRect(tester), camera);
      await rig.tap('Done asking');
      expect(rig.game.phase, GamePhase.answer);
      await rig.finish();
    });

    testWidgets('a trip out of the app: the wait for the pulse takes the '
        "seam's right, then Done asking comes back in place", (tester) async {
      final rig = Rig(tester);
      await rig.pumpApp();
      await rig.startGame(['Sam', 'Alex']);
      await rig.toQuestion();
      final done = seamButton(tester);
      final pause = pauseButton(tester);
      final camera = cameraRect(tester);
      await rig.leaveApp(3000);
      expect(rig.game.waitingForPulse, isTrue);
      expect(find.byType(SeamButton), findsNothing);
      final status = tester.getRect(find.text('Finding the pulse…'));
      expect(status.right, lessThanOrEqualTo(done.right));
      expect(status.center.dy, moreOrLessEquals(done.center.dy, epsilon: 20));
      expect(pauseButton(tester), pause);
      expect(cameraRect(tester), camera);
      await rig.until(() => !rig.game.waitingForPulse, what: 'the pulse');
      await rig.wait(SeamButton.entrance.inMilliseconds + 100);
      expect(seamButton(tester), done);
      expect(find.text('Sam: tap here, then answer'), findsOneWidget);
      await rig.finish();
    });

    testWidgets('a camera problem asking and answering: its stamp and fix '
        'stay clear of the seam; No clean read, then Ask it again', (
      tester,
    ) async {
      final rig = Rig(tester);
      await rig.pumpApp();
      await rig.startGame(['Sam', 'Alex']);
      await rig.toQuestion();
      final done = seamButton(tester);
      void expectClear(String where) {
        final stamp = find.byType(IssueStamp);
        expect(stamp, findsOneWidget, reason: where);
        final box = boundsOf(corners(tester.renderObject(stamp)));
        for (final shape in [buttonShape(tester), leadingShape(tester)]) {
          expect(overlaps(shape, box), isFalse, reason: '$where: $box');
        }
        expect(tester.takeException(), isNull);
      }

      rig.presage.code = 'TOO_DARK';
      await rig.wait(2500);
      expectClear('asking');
      await rig.tap('Done asking');
      await rig.wait(SeamButton.entrance.inMilliseconds + 100);
      expectClear('answering');
      await rig.tap('Final answer');
      await rig.until(() => rig.game.phase == GamePhase.redo, what: 'redo');
      rig.presage.code = 'OK';
      await rig.tap('Ask it again');
      await rig.until(() => !rig.game.waitingForPulse, what: 'the pulse');
      await rig.wait(SeamButton.entrance.inMilliseconds + 100);
      expect(rig.game.phase, GamePhase.ask);
      expect(seamButton(tester), done);
      await rig.finish();
    });

    testWidgets('the Proof Panel stays under the seam on Calibrate and the '
        'question screens, and follows it between them (375×667, text '
        '×1.3)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = Rig(tester);
      await rig.pumpApp(size: const Size(375, 667));
      await rig.startGame(['Sam', 'Alex']);
      rig.services.settings.proofPanel = true;
      await rig.tap('I agree, measure me');
      rig.autoTaps = false;

      void expectBelow(String where) {
        final panel = tester.getRect(
          find
              .descendant(
                of: find.byType(ProofPanel),
                matching: find.byType(Container),
              )
              .first,
        );
        final floor = seamButtonFloor.value;
        expect(floor, isNotNull, reason: where);
        expect(
          floor,
          moreOrLessEquals(
            cameraRect(tester).top + SeamLayout.cameraReach,
            epsilon: 0.5,
          ),
          reason: where,
        );
        expect(panel.top, greaterThanOrEqualTo(floor!), reason: where);
        for (final f in [find.byType(SeamButton), leadingButton()]) {
          if (f.evaluate().isEmpty) continue;
          expect(tester.getRect(f).bottom, lessThanOrEqualTo(panel.top));
        }
        expect(tester.takeException(), isNull, reason: where);
      }

      await rig.until(() => rig.game.currentWarmup != null, what: 'warm-up');
      await rig.wait(SeamButton.entrance.inMilliseconds + 100);
      expectBelow('a warm-up');
      await rig.until(() {
        final w = rig.game.currentWarmup;
        if (w != null && w.latencyS != null && !rig.presage.talking) {
          rig.game.nextWarmup();
        }
        return rig.game.calibStage == CalibStage.ready;
      }, what: 'the normal');
      await rig.wait(700);
      expectBelow('Start the questions');
      await rig.tap('Start the questions');
      await rig.toQuestion();
      expectBelow('Done asking');
      rig.game.doneAsking();
      await rig.wait(SeamButton.entrance.inMilliseconds + 100);
      expectBelow('Final answer');
      await rig.answerOutLoud();
      await rig.tap('Final answer');
      await rig.until(() => rig.game.phase == GamePhase.callIt);
      await rig.wait(300);
      // Off the measuring screens, the seam reports nothing.
      expect(seamButtonFloor.value, isNull);
      await rig.finish();
    });

    testWidgets('the next contestant gets Next where the last one had it', (
      tester,
    ) async {
      final rig = Rig(tester);
      await rig.pumpApp();
      await rig.startGame(['Sam', 'Alex'], questions: 1);
      await rig.tap('I agree, measure me');
      rig.autoTaps = false;
      await rig.until(() => rig.game.currentWarmup != null, what: 'warm-up');
      await rig.wait(SeamButton.entrance.inMilliseconds + 100);
      final next = seamButton(tester);
      await rig.toQuestion();
      await rig.tap('Done asking');
      await rig.answerOutLoud();
      await rig.tap('Final answer');
      await rig.until(() => rig.game.phase == GamePhase.callIt);
      rig.game.reveal();
      await rig.until(() => rig.game.phase == GamePhase.verdict);
      await rig.tap('Next contestant');
      await rig.wait(300);
      await rig.tap('I agree, measure me');
      rig.autoTaps = false;
      await rig.until(() => rig.game.currentWarmup != null, what: 'warm-up');
      expect(rig.game.currentPlayer.name, 'Alex');
      await rig.wait(SeamButton.entrance.inMilliseconds + 100);
      expect(seamButton(tester), next);
      expect(find.text('Tap here when done speaking'), findsOneWidget);
      await rig.finish();
    });

    testWidgets('without voice: the notice is a chip on the camera, clear '
        'of the seam and the live cards', (tester) async {
      final rig = Rig(tester);
      await rig.pumpApp();
      rig.speech.permissions = const SpeechPermissions(
        mic: 'denied',
        speech: 'authorized',
        onDevice: true,
      );
      await rig.startGame(['Sam', 'Alex']);
      await rig.tap('Play without voice');
      await rig.wait(300);
      if (rig.game.phase == GamePhase.howToPlay) {
        await rig.tap("Got it, let's play");
      }
      await rig.toQuestion();
      final notice = find.text('Playing without voice: no transcripts.');
      expect(notice, findsOneWidget);
      final chip = tester.getRect(notice);
      final camera = cameraRect(tester);
      expect(camera.contains(chip.center), isTrue);
      expect(chip.top, greaterThan(camera.top + SeamLayout.cameraReach));
      final cards = tester.getRect(find.byType(LiveStatCard).first);
      expect(chip.bottom, lessThanOrEqualTo(cards.top));
      expect(find.text('Sam: tap here, then answer'), findsOneWidget);
      await rig.tap('Done asking');
      expect(rig.game.phase, GamePhase.answer);
      await rig.finish();
    });

    for (final (screen, scale) in const [
      (Size(320, 568), 1.3),
      (Size(375, 667), 1.3),
      (Size(390, 844), 1.0),
    ]) {
      testWidgets('solo: a double tap on Different question deals one '
          'card, and Pause stays clear of the drawn button '
          '(${screen.width.round()}×${screen.height.round()}, text ×$scale)', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final rig = Rig(tester);
        await rig.pumpApp(size: screen);
        await rig.startGame(['Christopher-Alexandr'], solo: true);
        await rig.toQuestion();
        await rig.until(() => rig.game.soloHoldsQuestion, what: 'the hold');
        final drawn = tester.renderObject<RenderBox>(find.byKey(readyFaceKey));
        final lowest =
            boundsOf(corners(drawn)).bottom + SusShape.shadowOffset.dy;
        expect(pauseButton(tester).top - lowest, greaterThanOrEqualTo(3));
        final q = rig.game.questionText;
        final pill = tester.getCenter(
          find.bySemanticsLabel('Different question'),
        );
        await rig.tapTwice(pill);
        final once = rig.game.questionText;
        expect(once, isNot(q));
        await rig.wait(300);
        expect(rig.game.questionText, once);
        expect(rig.game.soloHoldsQuestion, isTrue);
        expect(tester.takeException(), isNull);
        await rig.finish();
      });
    }
  });

  group('scale', () {
    const seat = 'Christopher-Alexandr';
    const second = 'Bartholomew-Jameson';
    for (final screen in const [
      Size(320, 568),
      Size(375, 667),
      Size(390, 844),
    ]) {
      testWidgets('20-character names, 8 players, the largest text: every '
          'label whole, every hint readable '
          '(${screen.width.round()}×${screen.height.round()})', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final rig = Rig(tester);
        await rig.pumpApp(size: screen);
        await rig.startGame([
          seat,
          second,
          'Priya',
          'Jordan',
          'Kai',
          'Mo',
          'Lee',
          'Ana',
        ]);

        void expectReadable(String label, List<String> hints, {String? at}) {
          final where = at ?? label;
          expect(
            drawnScale(tester, find.text(label).first),
            greaterThanOrEqualTo(label == 'Next question' ? 0.85 : 0.99),
            reason: '$where: the label',
          );
          expect(
            drawnScale(tester, shown(hints).first),
            greaterThanOrEqualTo(0.75),
            reason: '$where: the hint',
          );
          expect(tester.takeException(), isNull, reason: where);
        }

        await rig.tap('I agree, measure me');
        rig.autoTaps = false;
        await rig.until(() => rig.game.currentWarmup != null, what: 'warm-up');
        await rig.wait(SeamButton.entrance.inMilliseconds + 100);
        expectReadable('Next', [
          'Tap here when done speaking',
          'Tap when done speaking',
        ]);
        await rig.until(() {
          final w = rig.game.currentWarmup;
          if (w != null && w.latencyS != null && !rig.presage.talking) {
            rig.game.nextWarmup();
          }
          return rig.game.calibStage == CalibStage.ready;
        }, what: 'the normal');
        await rig.wait(700);
        expectReadable('Start the questions', [
          'Tap when ready · $second asks first',
          '$second asks first',
          'Tap when ready',
        ]);
        await rig.tap('Start the questions');
        await rig.toQuestion();
        expectReadable('Done asking', [
          '$seat: tap here, then answer',
          'Tap here, then answer',
        ]);
        await rig.tap('Done asking');
        await rig.wait(SeamButton.entrance.inMilliseconds + 100);
        expectReadable('Final answer', [
          "Tap here when you're done",
          "Tap when you're done",
        ]);
        await rig.wait(21000);
        expectReadable('Final answer', [
          'No answer? Tap anyway, or Pause to skip',
          'No answer? Tap anyway',
        ], at: 'no answer');
        await rig.tap('Final answer');
        await rig.until(() => rig.game.phase == GamePhase.callIt);
        await rig.wait(300);
        expectReadable('Reveal', [
          'Still to call it: $second and 6 more',
          'Still to call it: 7',
        ]);
        rig.game.reveal();
        await rig.until(() => rig.game.phase == GamePhase.verdict);
        await rig.wait(300);
        expectReadable('Next question', [
          '${rig.game.nextAsker!.name} asks next',
        ]);
        await rig.finish();
      });
    }

    testWidgets('a 7-question turn: each question, Pause, the buttons and '
        'the camera where they were', (tester) async {
      final rig = Rig(tester);
      await rig.pumpApp();
      await rig.startGame(['Sam', 'Alex'], questions: 7);
      Rect? done, pause, camera;
      for (var q = 0; q < 7; q++) {
        await rig.toQuestion();
        expect(rig.game.questionIndex, q);
        done ??= seamButton(tester);
        pause ??= pauseButton(tester);
        camera ??= cameraRect(tester);
        expect(seamButton(tester), done, reason: 'Done asking, Q${q + 1}');
        expect(pauseButton(tester), pause, reason: 'Pause, Q${q + 1}');
        expect(cameraRect(tester), camera, reason: 'camera, Q${q + 1}');
        rig.say('Have you ever told a lie number ${q + 1}?');
        await rig.wait(400);
        await rig.tap('Done asking');
        await rig.wait(SeamButton.entrance.inMilliseconds + 100);
        expect(seamButton(tester).right, done.right);
        await rig.answerOutLoud();
        await rig.tap('Final answer');
        await rig.until(() => rig.game.phase == GamePhase.callIt);
        rig.game.reveal();
        await rig.until(() => rig.game.phase == GamePhase.verdict);
        await rig.wait(300);
        if (q < 6) await rig.tap('Next question');
      }
      expect(rig.game.currentTurn.results.length, 7);
      expect(tester.takeException(), isNull);
      await rig.finish();
    });

    testWidgets('a 7-question solo game with Different question on every '
        'card: each swapped once, answered as itself', (tester) async {
      final rig = Rig(tester);
      await rig.pumpApp();
      await rig.startGame(['Sam'], questions: 7, solo: true);
      Rect? pause, camera;
      for (var q = 0; q < 7; q++) {
        await rig.toQuestion();
        await rig.until(() => rig.game.soloHoldsQuestion, what: 'the hold');
        pause ??= pauseButton(tester);
        camera ??= cameraRect(tester);
        expect(pauseButton(tester), pause, reason: 'Pause, Q${q + 1}');
        expect(cameraRect(tester), camera, reason: 'camera, Q${q + 1}');
        final dealt = rig.game.questionText;
        await rig.tap('Different question');
        await rig.until(() => rig.game.soloHoldsQuestion, what: 'the hold');
        final asked = rig.game.questionText;
        expect(asked, isNot(dealt));
        await waitOutTapGuard(tester);
        await tester.tapAt(tester.getCenter(find.text(asked)));
        await tester.pump(const Duration(milliseconds: 60));
        await rig.wait(SeamButton.entrance.inMilliseconds + 100);
        expect(find.text('Final answer'), findsOneWidget);
        expect(pauseButton(tester), pause);
        await rig.answerOutLoud();
        await rig.tap('Final answer');
        await rig.until(() => rig.game.phase == GamePhase.verdict);
        expect(rig.game.currentResult!.question, asked);
        await rig.wait(300);
        if (q < 6) await rig.tap('Next question');
      }
      expect(rig.game.currentTurn.results.length, 7);
      expect(tester.takeException(), isNull);
      await rig.finish();
    });
  });

  group('cost', () {
    testWidgets('a hint is measured once for its words, not on every tick', (
      tester,
    ) async {
      // The question screens rebuild ten times a second; ButtonHint measures
      // its words to pick a form, so it keeps what it measured until the
      // words or the text size change.
      final rig = Rig(tester);
      await rig.pumpApp();
      await rig.startGame(['Christopher-Alexandr', 'Alex']);
      await rig.toQuestion();
      final before = ButtonHint.debugMeasured;
      for (var i = 0; i < 50; i++) {
        rig.say(List.filled(1 + i % 12, 'maybe').join(' '));
        rig.speech.controller.add(
          SpeechLevel(0.2 + 0.1 * (i % 7), rig.presage.now),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(ButtonHint.debugMeasured - before, 0, reason: '50 ticks on Ask');
      // New words: measured once more.
      rig.game.doneAsking();
      await rig.wait(SeamButton.entrance.inMilliseconds + 100);
      final answering = ButtonHint.debugMeasured;
      expect(answering - before, 2, reason: "Final answer's two forms");
      await rig.wait(5000);
      expect(ButtonHint.debugMeasured, answering);
      await rig.finish();
    });

    testWidgets('the question screens draw one frame per tick with their '
        'buttons up, at a cost recorded here', (tester) async {
      final rig = Rig(tester);
      await rig.pumpApp();
      await rig.startGame(['Christopher-Alexandr', 'Alex']);
      await rig.toQuestion();

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
      final ask = await msPerFrame();
      rig.game.doneAsking();
      await rig.wait(SeamButton.entrance.inMilliseconds + 100);
      final answer = await msPerFrame();
      // ignore: avoid_print
      print(
        'Seam frame: ${ask.toStringAsFixed(2)} ms on Ask, '
        '${answer.toStringAsFixed(2)} ms on Answer (debug)',
      );
      expect(ask, lessThan(answer * 2 + 2), reason: '$ask vs $answer');
      expect(tester.takeException(), isNull);
      await rig.finish();
    });
  });
}
