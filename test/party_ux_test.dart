// What a room sees between taps (SPEC.md decision 80): the simulated
// parties in test/party_sim_test.dart found no dead ends, but a walk through
// the real screens as three players did find things a room would trip on.
// Each test here pins one of that decision's changes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/screens/result_screens.dart';
import 'package:susometer/theme/tokens.dart';
import 'package:susometer/theme/widgets.dart';

import 'rig.dart';

extension on Rig {
  Future<void> startParty(List<String> names, {int questions = 3}) async {
    presage.storedKey = 'k';
    for (final n in names) {
      await addPlayer(n);
    }
    if (questions != 5) await tap('$questions');
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
      expect(find.text('Up next: Priya asks').hitTestable(), findsOneWidget);
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
      expect(find.textContaining('Up next'), findsNothing);
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
    expect(find.text("Everyone's in. Reveal!"), findsOneWidget);
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
    expect(stillToCall(const []), "Everyone's in. Reveal!");
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
    expect(find.text('Tap when ready. Alex asks first.'), findsOneWidget);
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
    expect(
      find.text('Tap when ready. The host asks the questions.'),
      findsOneWidget,
    );
    await rig.tap('Start the questions');
    await rig.wait(300);
    await rig.leaveApp(3000);
    expect(rig.game.waitingForPulse, isTrue);
    expect(find.text('Hang on · no question yet'), findsOneWidget);
    await rig.until(() => !rig.game.waitingForPulse, what: 'the pulse');
    await rig.until(() => rig.game.phase == GamePhase.answer);
    await rig.tap('Ready to answer');
    await rig.wait(1500);
    await rig.tap('Final answer');
    await rig.until(() => rig.game.phase == GamePhase.verdict);
    expect(find.textContaining('Up next'), findsNothing);
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
      find.text('Questions per turn · about 9 min in all'),
      findsOneWidget,
    );
    await rig.tap('7');
    expect(
      find.text('Questions per turn · about 12 min in all'),
      findsOneWidget,
    );
    for (final n in ['Priya', 'Jordan', 'Kai', 'Mo', 'Lee', 'Ana']) {
      await rig.addPlayer(n);
    }
    expect(
      find.text('Questions per turn · about 47 min in all'),
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
}
