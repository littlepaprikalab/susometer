// What a room sees between taps (SPEC.md decision 80): the simulated
// parties in test/party_sim_test.dart found no dead ends, but a walk through
// the real screens as three players did find things a room would trip on.
// Each test here pins one of that decision's changes.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/decks.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/presage/camera_preview.dart';
import 'package:susometer/screens/question_screens.dart';
import 'package:susometer/screens/result_screens.dart';
import 'package:susometer/theme/seam_button.dart';
import 'package:susometer/theme/game_widgets.dart';
import 'package:susometer/theme/tokens.dart';
import 'package:susometer/theme/widgets.dart';

import 'rig.dart';

extension on Rig {
  Future<void> startParty(List<String> names, {int questions = 3}) async {
    presage.storedKey = 'k';
    for (final n in names) {
      await addPlayer(n);
    }
    if (questions != 1) await tap('$questions');
    await tap('Start the show');
    await wait(300);
    if (game.phase == GamePhase.howToPlay) await tap("Got it, let's play");
  }

  /// Consent → the first question's Ask.
  Future<void> toAsk() async {
    await tap('I agree, measure me');
    await until(() => game.phase == GamePhase.ask, what: 'calibration');
    await until(() => !game.waitingForPulse, what: 'the pulse');
  }

  /// Calibrating → waiting on Start the questions, tapping Next by hand
  /// ([Rig.autoTaps] off) so the wait can be looked at.
  Future<void> throughWarmups() async {
    await until(() => game.calibStage == CalibStage.chat, what: 'warm-ups');
    for (var i = 0; i < 3; i++) {
      final warmup = game.currentWarmup!;
      await until(
        () => warmup.latencyS != null && !presage.talking,
        what: 'warm-up ${i + 1} answered',
      );
      await wait(5000);
      await tap('Next');
      await wait(700);
    }
    await until(
      () => game.calibStage == CalibStage.ready,
      what: 'the normal to lock in',
    );
    await wait(700);
  }

  /// Ask → Call it!, with a short spoken answer.
  Future<void> toCallIt() async {
    await until(() => !game.waitingForPulse, what: 'the pulse');
    await wait(500);
    await tap('Done asking');
    await wait(600);
    presage.talk(true);
    await wait(1200);
    presage.talk(false);
    await wait(700);
    await tap('Final answer');
    await until(
      () => game.phase == GamePhase.callIt || game.phase == GamePhase.redo,
      what: 'the reading to lock in',
    );
    expect(game.phase, GamePhase.callIt);
    await waitOutTapGuard(tester);
  }

  Future<void> toVerdict() async {
    await tap('Reveal');
    await until(() => game.phase == GamePhase.verdict, what: 'the countdown');
    await wait(600);
  }

  Future<void> vote(Player voter, Vote vote) async {
    final pick = find.bySemanticsLabel(
      '${voter.name}: ${vote == Vote.sus ? 'Sus' : 'Legit'}',
    );
    await tester.ensureVisible(pick);
    await tester.tap(pick);
    await tester.pump(const Duration(milliseconds: 150));
  }
}

ChunkyButton reveal(WidgetTester tester) =>
    tester.widget<ChunkyButton>(find.widgetWithText(ChunkyButton, 'Reveal'));

/// The part of the Verdict that shows without scrolling.
Rect verdictViewport(WidgetTester tester) =>
    tester.getRect(find.byType(SingleChildScrollView));

void main() {
  for (final (screen, scale) in const [
    (Size(390, 844), 1.0),
    (Size(390, 844), 1.3),
    (Size(375, 667), 1.0),
    (Size(375, 667), 1.3),
  ]) {
    final at = '${screen.width.round()}×${screen.height.round()}, text ×$scale';
    // The smallest phone at the largest text has room for the heading and
    // the first call; the cut-off second one says there's more.
    final tight = screen.height < 700 && scale > 1;

    testWidgets("the room's calls are on the Verdict without scrolling, "
        'with who asks next ($at)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = Rig(tester);
      await rig.pumpApp(size: screen);
      await rig.startParty(['Sam', 'Alex', 'Priya']);
      await rig.toAsk();
      await rig.toCallIt();
      final voters = rig.game.voters;
      await rig.vote(voters[0], Vote.legit);
      await rig.vote(voters[1], Vote.sus);
      await rig.toVerdict();

      final view = verdictViewport(tester);
      for (final call in [
        'How the room called it',
        'Alex: Legit · matched',
        if (!tight) 'Priya: Sus',
      ]) {
        final chip = tester.getRect(find.text(call));
        expect(
          chip.top >= view.top && chip.bottom <= view.bottom,
          isTrue,
          reason: '"$call" at $chip is outside the Verdict as it opens ($view)',
        );
        expect(find.text(call).hitTestable(), findsOneWidget);
      }
      // The score still comes first.
      expect(
        tester.getRect(find.text('How the room called it')).top,
        greaterThan(tester.getRect(find.text('THE SUS-O-METER SAYS')).bottom),
      );

      // Priya asks question 2: the room hears it here, a question early.
      expect(rig.game.nextAsker!.name, 'Priya');
      // On Next question itself (decision 90).
      expect(find.text('Priya asks next').hitTestable(), findsOneWidget);
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Next question')).hint,
        'Priya asks next',
      );
      semantics.dispose();
      await rig.tap('Next question');
      await rig.wait(300);
      expect(find.text('Priya, ask your question!'), findsOneWidget);

      // The turn's last question has nobody up next.
      await rig.toCallIt();
      await rig.toVerdict();
      await rig.tap('Next question');
      await rig.wait(300);
      await rig.toCallIt();
      await rig.toVerdict();
      expect(find.text('Next contestant'), findsOneWidget);
      expect(find.textContaining('asks next'), findsNothing);
      expect(tester.takeException(), isNull);
      await rig.finish();
    });

    testWidgets('seven voters: the calls start above the fold and the rest '
        'scroll ($at)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = Rig(tester);
      await rig.pumpApp(size: screen);
      await rig.startParty([
        'Sam',
        'Christopher-Alexand',
        'Priya',
        'Jordan',
        'Kai',
        'Mo',
        'Lee',
        'Ana',
      ]);
      await rig.toAsk();
      await rig.toCallIt();
      for (final v in rig.game.voters) {
        rig.game.castVote(v.id, Vote.legit);
      }
      await rig.wait(200);
      await rig.toVerdict();
      final view = verdictViewport(tester);
      final title = tester.getRect(find.text('How the room called it'));
      expect(
        title.top >= view.top && title.bottom <= view.bottom,
        isTrue,
        reason: 'the heading at $title shows as the Verdict opens ($view)',
      );
      // Every call can be scrolled to.
      for (final v in rig.game.voters) {
        final chip = find.text('${v.name}: Legit · matched');
        await tester.ensureVisible(chip);
        await tester.pump();
        expect(chip.hitTestable(), findsOneWidget, reason: v.name);
      }
      expect(tester.takeException(), isNull);
      await rig.finish();
    });
  }

  testWidgets('a Hmm… says it matches nobody, so no call reads as a miss', (
    tester,
  ) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex']);
    await rig.toAsk();
    // 12 BPM over Sam's normal through the whole question: a Hmm….
    rig.presage.pulse = 82;
    await rig.toCallIt();
    await rig.vote(rig.game.voters.single, Vote.sus);
    await rig.toVerdict();
    expect(rig.game.currentResult!.verdict, Verdict.hmm);
    expect(
      find.text('How the room called it · Hmm… matches nobody'),
      findsOneWidget,
    );
    expect(find.text('Alex: Sus'), findsOneWidget);
    expect(find.textContaining('· matched'), findsNothing);
    await rig.finish();
  });

  testWidgets('Call it! says who Reveal would cut off, and Reveal only goes '
      'solid once everyone is in', (tester) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex', 'Priya']);
    await rig.toAsk();
    await rig.toCallIt();
    final alex = rig.game.voters[0];
    final priya = rig.game.voters[1];

    expect(find.text('Still to call it: Alex & Priya'), findsOneWidget);
    expect(reveal(tester).color, SusColors.cream);

    await rig.vote(alex, Vote.legit);
    expect(find.text('Still to call it: Priya'), findsOneWidget);
    expect(reveal(tester).color, SusColors.cream);

    await rig.vote(priya, Vote.sus);
    expect(find.text("Everyone's in"), findsOneWidget);
    expect(reveal(tester).color, SusColors.teal);

    // Taking a pick back puts the name back.
    await rig.wait(700);
    await rig.vote(priya, Vote.sus);
    expect(find.text('Still to call it: Priya'), findsOneWidget);
    expect(reveal(tester).color, SusColors.cream);

    // It never blocks: someone may be sitting this one out.
    await rig.tap('Reveal');
    expect(rig.game.phase, GamePhase.countdown);
    expect(rig.game.currentResult!.votes.keys, [alex.id]);
    await rig.finish();
  });

  test('the line above Reveal stays one line with seven voters', () {
    expect(stillToCall(const []), "Everyone's in");
    expect(stillToCall(const ['Alex']), 'Still to call it: Alex');
    expect(
      stillToCall(const ['Alex', 'Priya']),
      'Still to call it: Alex & Priya',
    );
    expect(
      stillToCall(const ['Alex', 'Priya', 'Jordan']),
      'Still to call it: Alex and 2 more',
    );
    expect(
      stillToCall(const ['Alex', 'Priya', 'Jordan', 'Kai', 'Mo', 'Lee', 'Ana']),
      'Still to call it: Alex and 6 more',
    );
  });

  testWidgets('Start the questions says who asks first; a wait for the pulse '
      'says who asks next', (tester) async {
    final rig = Rig(tester)..autoTaps = false;
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex', 'Priya']);
    await rig.tap('I agree, measure me');
    await rig.throughWarmups();
    expect(find.text('Tap when ready · Alex asks first'), findsOneWidget);
    await rig.tap('Start the questions');
    await rig.wait(300);
    expect(find.text('Alex, ask your question!'), findsOneWidget);

    // A screenshot restarts the camera, so the question waits for the pulse.
    await rig.leaveApp(3000);
    expect(rig.game.waitingForPulse, isTrue);
    expect(find.text('Hang on · Alex asks next'), findsOneWidget);
    await rig.until(() => !rig.game.waitingForPulse, what: 'the pulse');
    expect(find.text('Alex, ask your question!'), findsOneWidget);
    await rig.finish();
  });

  testWidgets('solo: nobody is named as asking', (tester) async {
    final rig = Rig(tester)..autoTaps = false;
    await rig.pumpApp();
    await rig.tap('Solo · host asks');
    rig.presage.storedKey = 'k';
    await rig.addPlayer('Sam');
    await rig.tap('3');
    await rig.tap('Start the show');
    await rig.wait(300);
    await rig.tap("Got it, let's play");
    await rig.tap('I agree, measure me');
    await rig.throughWarmups();
    expect(find.text('Tap when ready · the host asks'), findsOneWidget);
    await rig.tap('Start the questions');
    await rig.wait(300);
    await rig.leaveApp(3000);
    expect(rig.game.waitingForPulse, isTrue);
    expect(find.text('Hang on · no question yet'), findsOneWidget);
    await rig.until(() => !rig.game.waitingForPulse, what: 'the pulse');
    await rig.until(() => rig.game.phase == GamePhase.answer);
    await rig.tap(readyCardLabel);
    await rig.wait(1500);
    await rig.tap('Final answer');
    await rig.until(() => rig.game.phase == GamePhase.verdict);
    expect(find.textContaining('asks next'), findsNothing);
    await rig.finish();
  });

  testWidgets('the lobby says how long the game will take once it can start', (
    tester,
  ) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    expect(find.text('Questions per turn'), findsOneWidget);
    await rig.addPlayer('Sam');
    expect(find.text('Questions per turn'), findsOneWidget);
    await rig.addPlayer('Alex');
    expect(
      find.text('Questions per turn · about 4 min in all'),
      findsOneWidget,
    );
    await rig.tap('5');
    expect(
      find.text('Questions per turn · about 9 min in all'),
      findsOneWidget,
    );
    for (final n in ['Priya', 'Jordan', 'Kai', 'Mo', 'Lee', 'Ana']) {
      await rig.addPlayer(n);
    }
    expect(
      find.text('Questions per turn · about 37 min in all'),
      findsOneWidget,
    );
    await rig.finish();
  });

  testWidgets('a level game shares the win on the leaderboard and the share '
      'card', (tester) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex', 'Priya'], questions: 3);
    for (var p = 0; p < 3; p++) {
      await rig.toAsk();
      // One calm answer each, then on to the next contestant.
      await rig.toCallIt();
      for (final v in rig.game.voters) {
        rig.game.castVote(v.id, Vote.legit);
      }
      await rig.toVerdict();
      expect(rig.game.currentResult!.score, 0);
      await rig.tap('End turn');
      await rig.wait(500);
    }
    expect(find.text('And the winners are…'), findsOneWidget);
    final awards = rig.game.awards!;
    expect(awards.pokerFace!.names, 'Sam, Alex & Priya');
    expect(awards.lieDetector!.names, 'Sam, Alex & Priya');
    // On screen, and once more on the off-screen share card.
    expect(find.text('Sam, Alex & Priya'), findsNWidgets(4));
    expect(find.text('Most sus'), findsNothing);
    expect(find.textContaining('BIGGEST SPIKE'), findsNothing);
    expect(find.text('Biggest spike'), findsNothing);
    // Nobody is placed second or third among equals.
    expect(find.text('1'), findsNWidgets(3));
    expect(find.text('1.'), findsNWidgets(3));
    expect(find.text('2'), findsNothing);
    expect(tester.takeException(), isNull);
    await rig.finish();
  });

  // --- Suggest one (SPEC.md decision 81) -----------------------------------

  testWidgets('Suggest one puts a deck question on the asker card and keeps '
      'it there while the asker reads it out', (tester) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex', 'Priya']);
    await rig.toAsk();
    await rig.wait(500);
    // The host's line is the card's own text until there are words
    // (SPEC.md decision 85).
    expect(find.text('Alex, ask your question!'), findsOneWidget);
    expect(find.text('Suggest one'), findsOneWidget);
    final camera = tester.getRect(find.byType(CameraPreview));

    await rig.tap('Suggest one');
    final first = rig.game.suggestion!;
    expect(find.text(first), findsOneWidget);
    expect(find.text('Try this one'), findsOneWidget);
    expect(find.text('Read it out, or ask your own.'), findsOneWidget);
    expect(find.text('Alex, ask your question!'), findsNothing);
    expect(find.text('Suggest one'), findsNothing);
    expect(
      tester.getRect(find.byType(CameraPreview)),
      camera,
      reason: 'the camera stays put: the player is being measured',
    );
    expect(rig.game.phase, GamePhase.ask);

    // Not that one: another.
    await rig.wait(700);
    await rig.tap('Another one');
    final second = rig.game.suggestion!;
    expect(second, isNot(first));
    expect(find.text(second), findsOneWidget);
    expect(find.text(first), findsNothing);

    // Alex reads it out. The card keeps the question, with what the mic
    // hears along the bottom.
    rig.say(second.substring(0, 12));
    await rig.wait(300);
    expect(find.text(second), findsOneWidget);
    expect(find.text('Heard: '), findsOneWidget);
    expect(find.text(second.substring(0, 12)), findsOneWidget);
    rig.say(second);
    await rig.wait(300);
    expect(find.text(second), findsNWidgets(2), reason: 'the card and Heard');

    final handle = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();

    await rig.tap('Done asking');
    expect(find.text('Q: “$second”'), findsOneWidget);
    expect(find.text('Try this one'), findsNothing);
    await rig.finish();
  });

  for (final (screen, scale) in const [
    (Size(390, 844), 1.0),
    (Size(390, 844), 1.3),
    (Size(375, 667), 1.0),
    (Size(375, 667), 1.3),
  ]) {
    testWidgets('Suggest one sits on the asker card, far from Done asking '
        '(${screen.width.round()}×${screen.height.round()}, text ×$scale)', (
      tester,
    ) async {
      // Beside Done asking, a thumb reaching for one could land on the
      // other (SPEC.md decision 84).
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = Rig(tester);
      await rig.pumpApp(size: screen);
      await rig.startParty(['Sam', 'Alex', 'Priya']);
      await rig.toAsk();
      await rig.wait(500);

      /// How much of its own size [text] is drawn at (1 when not shrunk).
      double drawnScale(String text) {
        final box = tester.renderObject<RenderBox>(find.text(text));
        final left = box.localToGlobal(Offset.zero).dx;
        final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
        return (right - left) / box.size.width;
      }

      for (final (label, action) in [
        ('Asker · listening', 'Suggest one'),
        ('Try this one', 'Another one'),
      ]) {
        final handle = tester.ensureSemantics();
        final button = tester.getRect(find.bySemanticsLabel(action));
        handle.dispose();
        final done = tester.getRect(find.byType(SeamButton));
        final pause = tester.getRect(find.bySemanticsLabel('Pause the game'));
        expect(button.height, greaterThanOrEqualTo(44), reason: action);
        expect(button.width, greaterThanOrEqualTo(44), reason: action);
        // Done asking now hangs across the card's bottom edge (decision
        // 90): the card's words lie between the two, about 150 pt, where
        // the slips came from the two side by side.
        expect(
          done.top - button.bottom,
          greaterThan(130),
          reason: '$action at $button is too near Done asking at $done',
        );
        // Pause hangs across the card's other corner, at the bottom left.
        final apart = Offset(
          math.max(
            0,
            math.max(pause.left - button.right, button.left - pause.right),
          ),
          math.max(0, pause.top - button.bottom),
        ).distance;
        expect(apart, greaterThan(150), reason: 'Pause at $pause');
        // The label keeps all its words, near enough full size to read.
        expect(find.text(label), findsOneWidget);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(label))
              .didExceedMaxLines,
          isFalse,
        );
        expect(drawnScale(label), greaterThan(0.85), reason: label);
        expect(tester.takeException(), isNull);
        if (action == 'Suggest one') {
          await rig.tap('Suggest one');
          expect(rig.game.suggestion, isNotNull);
        }
      }
      final handle = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
      await rig.finish();
    });
  }

  for (final (screen, scale) in const [
    (Size(390, 844), 1.0),
    (Size(375, 667), 1.3),
  ]) {
    testWidgets('every deck question fits the asker card whole '
        '(${screen.width.round()}×${screen.height.round()}, text ×$scale)', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      // Every card at heat 1, so question 1 deals the whole deck.
      DeckLibrary read(String name) => DeckLibrary(
        warmup: DeckLibrary.fallback.warmup,
        mild: [
          for (final q in DeckLibrary.parse(
            File('assets/decks/$name.json').readAsStringSync(),
          ))
            DeckQuestion(q.text, heat: 1),
        ],
        spicy: const [],
      );
      for (final name in ['mild', 'spicy']) {
        final deck = read(name);
        final rig = Rig(tester);
        await rig.pumpApp(size: screen);
        rig.game.setDecks(deck);
        await rig.startParty(['Sam', 'Alex', 'Priya']);
        await rig.toAsk();
        final seen = <String>{};
        // The dealer goes through the pile before repeating.
        for (var i = 0; i < deck.mild.length; i++) {
          await rig.wait(700);
          rig.game.suggestQuestion();
          await tester.pump(const Duration(milliseconds: 100));
          final q = rig.game.suggestion!;
          if (!seen.add(q)) continue;
          final text = find.text(q);
          expect(text, findsOneWidget);
          expect(
            tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
            isFalse,
            reason: '"$q" is cut off',
          );
          final card = tester.getRect(text);
          expect(
            tester.getRect(find.byType(CameraPreview)).top,
            greaterThan(card.bottom),
            reason: '"$q" runs into the camera',
          );
        }
        expect(seen.length, deck.mild.length, reason: 'the whole $name deck');
        expect(tester.takeException(), isNull);
        await rig.finish();
      }
    });
  }

  testWidgets("the lobby's deck is for suggestions in a party, and solo has "
      'no Suggest one', (tester) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    expect(find.text('Question deck · for suggestions'), findsOneWidget);
    await rig.tap('Solo · host asks');
    expect(find.text('Question deck'), findsOneWidget);
    rig.presage.storedKey = 'k';
    await rig.addPlayer('Sam');
    await rig.tap('3');
    await rig.tap('Start the show');
    await rig.wait(300);
    expect(find.textContaining('Stuck? Tap Suggest one.'), findsOneWidget);
    await rig.tap("Got it, let's play");
    await rig.tap('I agree, measure me');
    await rig.until(() => rig.game.phase == GamePhase.answer);
    await rig.wait(500);
    expect(find.text('Different question'), findsOneWidget);
    expect(find.text('Suggest one'), findsNothing);
    await rig.finish();
  });

  // --- Play again asks first (SPEC.md decision 82) --------------------------

  /// Two players, one question each, on the leaderboard.
  Future<Rig> played(WidgetTester tester) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex']);
    for (var p = 0; p < 2; p++) {
      await rig.toAsk();
      await rig.toCallIt();
      await rig.toVerdict();
      await rig.tap('End turn');
      await rig.wait(500);
    }
    expect(rig.game.phase, GamePhase.leaderboard);
    return rig;
  }

  testWidgets('Play again asks before it wipes the scores, from the '
      'leaderboard and from the replay', (tester) async {
    final rig = await played(tester);
    await rig.tap('Play again');
    expect(find.text('Play again?'), findsOneWidget);
    expect(rig.game.phase, GamePhase.leaderboard);
    expect(rig.game.turns, isNotEmpty, reason: 'nothing wiped yet');

    final handle = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    // VoiceOver finds only the sheet, not the buttons behind it.
    await waitOutTapGuard(tester);
    expect(find.semantics.byLabel('Keep the scores'), findsOne);
    expect(
      find.semantics.byLabel('Watch the replay'),
      findsNothing,
      reason: 'VoiceOver could reach the leaderboard behind the sheet',
    );
    handle.dispose();

    await rig.tap('Keep the scores');
    expect(find.text('Play again?'), findsNothing);
    expect(find.text('And the winners are…'), findsOneWidget);
    expect(rig.game.awards, isNotNull);

    // A tap outside the sheet keeps them too.
    await rig.tap('Play again');
    await waitOutTapGuard(tester);
    await tester.tapAt(const Offset(195, 120));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Play again?'), findsNothing);
    expect(rig.game.phase, GamePhase.leaderboard);

    // The replay's Play again asks the same.
    await rig.tap('Watch the replay');
    await rig.wait(300);
    await rig.tap('Play again');
    expect(find.text('Play again?'), findsOneWidget);
    expect(rig.game.phase, GamePhase.replay);
    await rig.tap('Wipe and play again');
    await rig.wait(300);
    expect(rig.game.phase, GamePhase.lobby);
    expect(rig.game.turns, isEmpty);
    expect(find.text('Play again?'), findsNothing);
    expect(find.text('Sam'), findsOneWidget, reason: 'contestants stay');
    expect(find.text('Alex'), findsOneWidget);
    await rig.finish();
  });

  testWidgets('a double tap on Play again never wipes: the sheet comes up '
      'under the finger and ignores its second tap', (tester) async {
    final rig = await played(tester);
    for (final screen in ['leaderboard', 'replay']) {
      if (screen == 'replay') {
        await rig.tap('Watch the replay');
        await rig.wait(600);
      }
      await waitOutTapGuard(tester);
      final at = tester.getCenter(find.text('Play again'));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 80));
      // And a third, for a nervous thumb.
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('Play again?'), findsOneWidget, reason: screen);
      expect(rig.game.turns, isNotEmpty, reason: '$screen: still there');
      await rig.tap('Keep the scores');
      expect(find.text('Play again?'), findsNothing);
    }
    await rig.finish();
  });

  testWidgets('with nothing played there is nothing to ask about', (
    tester,
  ) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex']);
    await rig.tap('Skip my turn');
    await rig.wait(700);
    await rig.tap('Skip my turn');
    await rig.wait(300);
    expect(rig.game.phase, GamePhase.leaderboard);
    await rig.tap('Play again');
    await rig.wait(300);
    expect(find.text('Play again?'), findsNothing);
    expect(rig.game.phase, GamePhase.lobby);
    await rig.finish();
  });

  // --- Reliability pass (SPEC.md decision 83) --------------------------------

  testWidgets('the Play again sheet: nothing behind it takes a tap while it '
      'comes up, it survives a trip out of the app, and it never comes back '
      "with another game's scores", (tester) async {
    final rig = await played(tester);
    await waitOutTapGuard(tester);
    // A tap on Play again, then one straight after on Share results.
    final share = tester.getCenter(find.text('Share results'));
    await tester.tapAt(tester.getCenter(find.text('Play again')));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(share);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await rig.wait(200);
    expect(rig.device.shares, 0, reason: 'the tap fell through the sheet');
    expect(find.text('Play again?'), findsOneWidget);

    // The same on the Replay, where Wipe everything sits behind the sheet's
    // own buttons and acts at once.
    await rig.tap('Keep the scores');
    await rig.tap('Watch the replay');
    await rig.wait(600);
    await waitOutTapGuard(tester);
    final wipe = tester.getCenter(find.text('Wipe everything'));
    await tester.tapAt(tester.getCenter(find.text('Play again')));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(wipe);
    await tester.pump(const Duration(milliseconds: 80));
    await rig.wait(300);
    expect(rig.game.phase, GamePhase.replay, reason: 'wiped behind the sheet');
    expect(rig.game.turns, isNotEmpty);
    expect(rig.game.players, isNotEmpty);
    expect(find.text('Play again?'), findsOneWidget);
    await rig.tap('Keep the scores');
    await tester.tap(find.byTooltip('Back to scores'));
    await rig.wait(300);
    await rig.tap('Play again');
    expect(find.text('Play again?'), findsOneWidget);

    // Out of the app and back: still asking, nothing wiped.
    await rig.leaveApp(20000);
    expect(find.text('Play again?'), findsOneWidget);
    expect(rig.game.phase, GamePhase.leaderboard);
    expect(rig.game.awards, isNotNull);

    // The game is wiped some other way while the sheet is up (Settings'
    // Wipe all game data does this): the question goes with the scores.
    await rig.game.playAgain();
    await rig.wait(300);
    expect(rig.game.phase, GamePhase.lobby);
    expect(find.text('Play again?'), findsNothing);
    await rig.tap('Start the show');
    await rig.wait(300);
    for (var p = 0; p < 2; p++) {
      await rig.toAsk();
      await rig.toCallIt();
      await rig.toVerdict();
      await rig.tap('End turn');
      await rig.wait(500);
    }
    expect(rig.game.phase, GamePhase.leaderboard);
    expect(
      find.text('Play again?'),
      findsNothing,
      reason: "the last game's question came back",
    );
    await rig.finish();
  });

  for (final (screen, scale) in const [
    (Size(390, 844), 1.0),
    (Size(375, 667), 1.3),
  ]) {
    testWidgets('four long names sharing an award stay readable '
        '(${screen.width.round()}×${screen.height.round()}, text ×$scale)', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = Rig(tester);
      await rig.pumpApp(size: screen);
      const names = [
        'Christopher-Alexand',
        'Maximilian-Sebastia',
        'Anastasia-Elizabeth',
        'Bartholomew-Ferdina',
        'Zed',
      ];
      await rig.startParty(names);
      for (var p = 0; p < names.length; p++) {
        await rig.toAsk();
        // Zed's pulse runs 12 over normal: a Hmm… against four zeros.
        if (p == 4) rig.presage.pulse = 82;
        await rig.toCallIt();
        for (final v in rig.game.voters) {
          rig.game.castVote(v.id, Vote.legit);
        }
        await rig.wait(700);
        await rig.toVerdict();
        await rig.tap('End turn');
        await rig.wait(500);
      }
      expect(rig.game.phase, GamePhase.leaderboard);
      final awards = rig.game.awards!;
      expect(awards.pokerFace!.players.length, 4);
      expect(awards.mostSus!.names, 'Zed');
      final shared = find.text(awards.pokerFace!.names).hitTestable();
      expect(shared, findsOneWidget);
      // Wrapped at its own size, not shrunk onto one line.
      expect(
        find.ancestor(of: shared, matching: find.byType(FittedBox)),
        findsNothing,
      );
      final paragraph = tester.renderObject<RenderParagraph>(shared);
      expect(paragraph.text.style!.fontSize, 17);
      expect(paragraph.didExceedMaxLines, isFalse);
      // The two award cards are a pair: the same height, side by side.
      final cards = find.ancestor(
        of: find.text('Most sus'),
        matching: find.byType(IntrinsicHeight),
      );
      final row = tester.getRect(cards);
      final sus = tester.getRect(find.text('Zed').hitTestable().first);
      expect(row.contains(sus.center), isTrue);
      expect(tester.takeException(), isNull);
      // The share card takes the same names without overflowing.
      await rig.tap('Share results');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await rig.wait(200);
      expect(rig.device.shares, 1);
      expect(tester.takeException(), isNull);
      await rig.finish();
    });
  }

  // --- The question card is the button; no host bubble (decision 85) --------

  for (final (screen, scale) in const [
    (Size(390, 844), 1.0),
    (Size(390, 844), 1.3),
    (Size(375, 667), 1.0),
    (Size(375, 667), 1.3),
  ]) {
    testWidgets('solo: the question card is the way on to the answer '
        '(${screen.width.round()}×${screen.height.round()}, text ×$scale)', (
      tester,
    ) async {
      // The buttons under the camera were half a screen from the question
      // the player was reading, so they answered before finding them.
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = Rig(tester);
      await rig.pumpApp(size: screen);
      await rig.tap('Solo · host asks');
      await rig.startParty(['Sam']);
      await rig.tap('I agree, measure me');
      await rig.until(
        () => rig.game.phase == GamePhase.answer,
        what: 'the host to read the question',
      );
      await rig.wait(600);
      expect(rig.game.soloHoldsQuestion, isTrue);
      final q = rig.game.questionText;

      // The card says it; no button or bubble does.
      expect(find.text('Ready to answer'), findsNothing);
      expect(find.byType(HostBubble), findsNothing);
      final face = find.text(readyCardLabel);
      expect(face, findsOneWidget);
      final faceBox = tester.renderObject<RenderParagraph>(face);
      expect(faceBox.didExceedMaxLines, isFalse);
      final left = faceBox.localToGlobal(Offset.zero).dx;
      final right = faceBox.localToGlobal(Offset(faceBox.size.width, 0)).dx;
      expect(
        (right - left) / faceBox.size.width,
        greaterThan(0.85),
        reason: 'the button keeps its words near full size',
      );

      // One button, the size of the card, read out as the question.
      final handle = tester.ensureSemantics();
      final button = find.bySemanticsLabel(q);
      expect(button, findsOneWidget);
      expect(
        tester.getSemantics(button),
        isSemantics(isButton: true, hasTapAction: true),
      );
      final card = tester.getRect(button);
      final text = tester.getRect(find.text(q));
      expect(card.height, greaterThan(200));
      expect(card.contains(text.center), isTrue);
      expect(card.contains(tester.getCenter(face)), isTrue);
      expect(
        tester.renderObject<RenderParagraph>(find.text(q)).didExceedMaxLines,
        isFalse,
      );
      expect(tester.getRect(face).top, greaterThan(text.bottom));
      // The drawn button is askew on purpose, like a stamp, and stays
      // inside the card, shadow and all.
      final drawn = tester.renderObject<RenderBox>(find.byKey(readyFaceKey));
      final shadow = SusShape.shadowOffset.dy;
      final corners = [
        drawn.localToGlobal(Offset.zero),
        drawn.localToGlobal(Offset(drawn.size.width, 0)),
        drawn.localToGlobal(Offset(0, drawn.size.height + shadow)),
        drawn.localToGlobal(
          Offset(drawn.size.width, drawn.size.height + shadow),
        ),
      ];
      expect(
        (corners[0].dy - corners[1].dy).abs(),
        greaterThan(6),
        reason: 'the button is level',
      );
      final inside = card.deflate(SusShape.borderWidth);
      for (final c in corners) {
        expect(inside.contains(c), isTrue, reason: 'the button leaves $card');
      }

      // Different question is on the card's top row (decision 90), the
      // question between it and the drawn button, as Suggest one is on the
      // asker's card (decision 84).
      final different = tester.getRect(
        find.bySemanticsLabel('Different question'),
      );
      expect(card.contains(different.center), isTrue);
      expect(different.bottom, lessThanOrEqualTo(text.top + 1));
      expect(tester.getRect(face).top - different.bottom, greaterThan(100));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();

      // Talking doesn't move it on (decision 76); a tap on the question
      // does, and the camera stays where it was.
      final camera = tester.getRect(find.byType(CameraPreview));
      rig.presage.talk(true);
      await rig.wait(1200);
      expect(rig.game.soloHoldsQuestion, isTrue);
      rig.presage.talk(false);
      await waitOutTapGuard(tester);
      await tester.tapAt(text.center);
      await tester.pump(const Duration(milliseconds: 60));
      expect(rig.game.soloHoldsQuestion, isFalse);
      expect(find.text('Q: “$q”'), findsOneWidget);
      expect(find.text(readyCardLabel), findsNothing);
      expect(find.text('Final answer'), findsOneWidget);
      expect(find.byType(HostBubble), findsNothing);
      expect(tester.getRect(find.byType(CameraPreview)), camera);
      expect(tester.takeException(), isNull);
      await rig.finish();
    });
  }

  for (final (screen, scale) in const [
    (Size(390, 844), 1.0),
    (Size(375, 667), 1.3),
  ]) {
    testWidgets('every deck question fits the solo card whole, above its '
        'button (${screen.width.round()}×${screen.height.round()}, '
        'text ×$scale)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      // Every card at heat 1, so question 1 deals the whole deck.
      DeckLibrary read(String name) => DeckLibrary(
        warmup: DeckLibrary.fallback.warmup,
        mild: [
          for (final q in DeckLibrary.parse(
            File('assets/decks/$name.json').readAsStringSync(),
          ))
            DeckQuestion(q.text, heat: 1),
        ],
        spicy: const [],
      );
      for (final name in ['mild', 'spicy']) {
        final deck = read(name);
        final rig = Rig(tester);
        await rig.pumpApp(size: screen);
        rig.game.setDecks(deck);
        await rig.tap('Solo · host asks');
        await rig.startParty(['Sam']);
        await rig.tap('I agree, measure me');
        await rig.until(
          () => rig.game.soloHoldsQuestion,
          what: 'the host to read question 1',
        );
        final seen = <String>{};
        // The dealer goes through the pile before repeating.
        for (var i = 0; i < deck.mild.length; i++) {
          await rig.wait(700);
          final q = rig.game.questionText;
          if (seen.add(q)) {
            final text = find.text(q);
            expect(text, findsOneWidget);
            expect(
              tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
              isFalse,
              reason: '"$q" is cut off',
            );
            expect(
              tester.getRect(find.text(readyCardLabel)).top,
              greaterThan(tester.getRect(text).bottom),
              reason: '"$q" runs into the button',
            );
          }
          rig.game.differentQuestion();
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(seen.length, deck.mild.length, reason: 'the whole $name deck');
        expect(tester.takeException(), isNull);
        await rig.finish();
      }
    });
  }

  testWidgets('party: the card says what the host bubble said, and the '
      'camera stays put', (tester) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex']);
    await rig.toAsk();
    await rig.wait(300);
    expect(find.byType(HostBubble), findsNothing);
    // Who asks, until there are words.
    expect(find.text('Alex, ask your question!'), findsOneWidget);
    final camera = tester.getRect(find.byType(CameraPreview));
    rig.say('Have you ever told a fib?');
    await rig.wait(300);
    expect(find.text('Alex, ask your question!'), findsNothing);
    expect(find.text('Have you ever told a fib?'), findsOneWidget);
    await rig.tap('Done asking');
    expect(find.byType(HostBubble), findsNothing);
    expect(find.text('Sam, your answer?'), findsOneWidget);
    expect(tester.getRect(find.byType(CameraPreview)), camera);
    rig.say('Never.');
    await rig.wait(300);
    expect(find.text('Sam, your answer?'), findsNothing);
    await rig.tap('Final answer');
    await rig.wait(100);
    expect(rig.game.phase, GamePhase.settle);
    expect(find.byType(HostBubble), findsNothing);
    expect(tester.getRect(find.byType(CameraPreview)), camera);
    expect(tester.takeException(), isNull);
    await rig.finish();
  });
}
