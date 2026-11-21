// The demo film: a solo game and a party game, played through the real
// screens by stand-in people, rendered frame by frame to video. The room
// picture is cut into numbered shots, so real clips of people playing can
// replace the stand-ins later (tool/demo_video/mix.py --clips).
//
// The signals are made up (FilmPresage in film/film.dart), so this is an
// animatic, not proof of the SDK working: the submission's phone footage has
// to come from a real iPhone (docs/DEMO.md).
//
// Render it with tool/demo_video/make.sh. Like the screen gallery, it only
// runs when asked: FILM_OUT set renders it there; FILM_DRY=1 plays the script
// through without rendering (a few seconds a game, for tuning it):
//
//   FILM_DRY=1 flutter test test/demo_film_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/decks.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/screens/question_screens.dart';

import 'film/film.dart';

/// The questions the film uses, one per heat, so every render deals the
/// same cards. All from assets/decks.
const _decks = DeckLibrary(
  warmup: [
    DeckQuestion(
      'Tell me what you had for breakfast today.',
      slot: WarmupSlot.recall,
    ),
    DeckQuestion(
      'Have you ever been caught in the rain? Tell me what happened.',
      slot: WarmupSlot.compare,
    ),
    DeckQuestion('Cats or dogs? Tell me why.', slot: WarmupSlot.light),
  ],
  mild: [
    DeckQuestion("Have you ever laughed at a joke you didn't get?", heat: 1),
    DeckQuestion('Be honest: do you floss every day?', heat: 2),
    DeckQuestion('Have you ever eaten the last cookie and denied it?', heat: 3),
  ],
  spicy: [
    DeckQuestion(
      'Have you ever claimed a joke you heard as your own?',
      heat: 1,
    ),
    DeckQuestion('Have you ever faked being sick to skip a party?', heat: 2),
    DeckQuestion("Have you ever read someone's texts without asking?", heat: 3),
  ],
);

Actor _maya() => Actor(
  'Maya',
  skin: const Color(0xFFE8B58E),
  hair: const Color(0xFF7A3B1E),
  shirt: const Color(0xFF1F6F78),
  hairStyle: 2,
);

List<Actor> _friends() => [
  Actor(
    'Sam',
    skin: const Color(0xFFF2C6A0),
    hair: const Color(0xFF5A3A22),
    shirt: const Color(0xFFD9412B),
  ),
  Actor(
    'Alex',
    skin: const Color(0xFFD9A27A),
    hair: const Color(0xFF2A160C),
    shirt: const Color(0xFF3E8C7A),
    hairStyle: 3,
  ),
];

/// How a stand-in takes a question.
class Take {
  const Take({
    this.bpm = 0,
    this.pauseMs = 600,
    this.mood = Mood.neutral,
    this.blinkEveryMs = 3600,
  });

  /// Calm: nothing moves.
  static const calm = Take(mood: Mood.happy);

  /// A wobble: the pulse up a little, a pause.
  static const uneasy = Take(bpm: 9, pauseMs: 2100, mood: Mood.surprised);

  /// Caught out: pulse up, a long pause, a burst of blinks.
  static const rattled = Take(
    bpm: 22,
    pauseMs: 2900,
    mood: Mood.nervous,
    blinkEveryMs: 800,
  );

  /// How far the heart climbs above the player's normal.
  final double bpm;

  /// The pause before the answer starts.
  final int pauseMs;
  final Mood mood;
  final int blinkEveryMs;
}

extension on Film {
  /// Waits until the host has finished talking.
  Future<void> hostDone() async {
    await run(100);
    await until(() => host.idle);
  }

  /// The question lands: the stand-in's body reacts as in [take].
  void react(Take take, double normal) {
    presage
      ..target = normal + take.bpm
      ..blinkEveryMs = take.blinkEveryMs;
    hotSeat!.mood = take.mood;
  }

  void relax(double normal) {
    presage
      ..target = normal
      ..blinkEveryMs = 3600;
  }

  /// Calibration from "I agree" to the first question, unfilmed except what
  /// the caller films around it. Answers each warm-up and taps Next.
  Future<void> warmups(Actor who, {int from = 0}) async {
    const answers = [
      'Toast. And way too much coffee.',
      'Yes! I got soaked walking home last week.',
      'Dogs. They are always happy to see you.',
    ];
    for (var i = from; i < 3; i++) {
      await until(() => game.currentWarmup != null);
      await hostDone();
      await run(700);
      who.mood = Mood.happy;
      await speak(who, answers[i], heard: false);
      await tap('Next');
    }
    who.mood = Mood.neutral;
    await until(() => game.calibStage == CalibStage.ready);
  }

  /// One whole question, start to verdict, the way a quick round goes.
  /// [votes]: Sus (true) or Legit for each voter, in screen order.
  Future<void> question(
    Take take,
    double normal, {
    String ask = 'Okay, my turn. Have you ever told a white lie this week?',
    String answer = 'Maybe one. A small one.',
    List<bool> votes = const [],
  }) async {
    await until(() => !game.waitingForPulse);
    if (game.mode == GameMode.party) {
      await hostDone();
      final asker = actor(game.currentAsker!.name);
      await speak(asker, ask);
      react(take, normal);
      await tap('Done asking');
    } else {
      await until(() => game.soloHoldsQuestion);
      react(take, normal);
      await tap(readyCardLabel);
    }
    await run(take.pauseMs);
    await speak(hotSeat!, answer);
    await tap('Final answer');
    relax(normal);
    await until(
      () => game.phase == GamePhase.callIt || game.phase == GamePhase.countdown,
    );
    hotSeat!.mood = Mood.neutral;
    if (game.phase == GamePhase.callIt) {
      for (var i = 0; i < votes.length; i++) {
        await tap(votes[i] ? 'Sus' : 'Legit', at: i, after: 100);
      }
      await tap('Reveal');
    }
    await until(() => game.phase == GamePhase.verdict);
    report();
    await run(600);
  }

  void report() {
    final r = game.currentResult;
    final b = r?.breakdown;
    debug(
      '${game.currentPlayer.name} Q${game.questionIndex + 1}: '
      '${r?.score} ${r?.verdict?.name} '
      '(pulse ${b?.zPulse.toStringAsFixed(2)} ${b?.pulseMethod.name}, '
      'blink ${b?.zBlink.toStringAsFixed(2)}, '
      'expr ${b?.zExpr.toStringAsFixed(2)}, '
      'pause ${b?.zHesitation.toStringAsFixed(2)})',
    );
  }
}

/// Only when asked for (see the top of this file).
final _skip = Film.outDir == null && Platform.environment['FILM_DRY'] == null;

/// A real recording opens the film (make.sh --real): the order is real,
/// party, solo, so the opening title is the real part's, the party is part
/// 2, the solo part 3, and the closing card ends the solo game. Without one:
/// solo (part 1), then party (part 2).
final _withReal = Platform.environment['FILM_WITH_REAL'] == '1';

const _closingCard = TitleCard('Sus-o-meter', [
  'It reads stress, not truth.',
  'Built with the Presage SmartSpectra SDK.',
]);

void main() {
  testWidgets('demo film: a solo game', skip: _skip, (tester) async {
    final film = Film(tester, 'solo');
    await film.start();
    final game = film.game;
    final maya = _maya();
    const normal = 68.0;
    film
      ..cast = [maya]
      ..presage.storedKey = 'pk_demo_film';
    film.presage.settle(normal);
    game
      ..setDecks(_decks)
      ..hasSeenHowToPlay = true;

    if (!_withReal) {
      await film.showCard(
        const TitleCard('Sus-o-meter', [
          'The party game that reads your pulse.',
          'Not your mind.',
        ]),
        2600,
      );
    }
    await film.showCard(
      TitleCard('Solo', const [
        'One player. The host asks the questions.',
      ], kicker: _withReal ? 'PART 3' : 'PART 1'),
      1800,
    );

    // Lobby.
    film
      ..chapter = 'SOLO GAME'
      ..step = 'Set up'
      ..note =
          'Maya plays alone: the phone’s host reads questions from the '
          'deck, and the camera reads her pulse, blinks and face.'
      ..cut('01', 'Maya picks up the phone and sets up a solo game');
    await film.run(900);
    await film.tap('Solo · host asks');
    await film.typeName('Maya');
    await film.tap('3');
    await film.speak(
      maya,
      'Okay. Let’s see if this thing can read me.',
      heard: false,
    );
    await film.tap('Start the show');

    // Consent.
    film
      ..step = 'Consent'
      ..note =
          'The player being measured agrees first. Video never leaves '
          'the phone; “Skip my turn” is always there.';
    await film.run(2400);
    await film.tap('I agree, measure me');

    // Calibrate: sit still.
    film
      ..step = 'Calibrate · sit still'
      ..note =
          'Maya sits still until the camera has her pulse (up to 20 '
          'seconds): it learns her own normal, so a naturally fast heart '
          'doesn’t count against her.'
      ..cut('02', 'Maya sits still and looks at the phone');
    await film.run(6000);
    // The sit-still ends once the camera has the pulse (SPEC.md decision
    // 92): skip ahead to a few seconds before that, then film the end.
    await film.fast(
      () => film.until(
        () =>
            game.calibStage != CalibStage.quiet ||
            film.now - game.quietStartMs! >= 10000,
      ),
    );
    await film.until(() => game.calibStage != CalibStage.quiet);

    // Calibrate: chat.
    film
      ..step = 'Calibrate · chat a bit'
      ..note =
          'Three easy warm-ups, answered out loud: this is how Maya '
          'blinks, looks and sounds when nothing is at stake.'
      ..cut('03', 'Maya answers an easy warm-up out loud, relaxed');
    await film.until(() => game.currentWarmup != null);
    await film.hostDone();
    await film.run(600);
    maya.mood = Mood.happy;
    await film.speak(maya, 'Toast. And way too much coffee.', heard: false);
    await film.tap('Next', after: -1);
    await film.fast(
      () => film.warmups(maya, from: 1),
      label: 'two warm-ups later',
    );
    film
      ..step = 'Calibrate · locked in'
      ..cut('04', 'Maya hears her normal is locked in and taps Start');
    await film.hostDone();
    await film.run(900);
    await film.tap('Start the questions', after: -1);

    // Question 1: calm.
    film
      ..step = 'Question 1 of 3'
      ..note =
          'The host reads a question from the deck. It stays up until '
          'Maya taps the card, then she answers out loud.'
      ..cut('05', 'Maya listens to the host’s question, then taps the card');
    await film.until(() => game.soloHoldsQuestion);
    await film.run(700);
    await film.tap(readyCardLabel);
    film.cut('06', 'Maya answers straight away, laughing');
    film.react(Take.calm, normal);
    await film.run(500);
    await film.speak(maya, 'Oh, all the time. I just nod and laugh along.');
    await film.run(300);
    await film.tap('Final answer');
    film.step = 'Locking in the reading';
    if (film.hasMono) {
      film.note =
          'Proof Panel (in Settings): the raw SmartSpectra stream '
          'behind the game. Pulse and confidence, blinks, talking, '
          'expressions.';
      film.services.settings.proofPanel = true;
      await film.run(4500);
      film.services.settings.proofPanel = false;
    } else {
      await film.run(1500);
    }
    await film.fast(() => film.until(() => game.phase == GamePhase.countdown));
    film
      ..step = 'The verdict'
      ..note =
          'Everything is compared with Maya’s own warm-ups: her pulse, '
          'her blinks, her face and how long she took to start answering.'
      ..cut('07', 'Maya watches the countdown, then grins at “Legit”');
    await film.until(() => game.phase == GamePhase.verdict);
    film.report();
    maya.mood = Mood.laugh;
    await film.run(1800);
    await film.speak(maya, 'Ha! Told you.', heard: false);
    await film.run(1500);
    maya.mood = Mood.neutral;

    // Question 2, unfilmed.
    await film.fast(() async {
      await film.tap('Next question');
      await film.question(
        Take.uneasy,
        normal,
        answer: 'Um. Most days. Some days.',
      );
      await film.tap('Next question');
    }, label: 'question 2 later');

    // Question 3: the hot one.
    film
      ..step = 'Question 3 of 3 · the hottest one'
      ..note =
          'Questions get hotter through the turn. This one lands: her '
          'pulse climbs, she blinks more, and she takes a while to answer.'
      ..cut('08', 'Maya hears the question and freezes');
    await film.until(() => game.soloHoldsQuestion);
    film.react(Take.rattled, normal);
    maya.mood = Mood.surprised;
    await film.run(1500);
    await film.tap(readyCardLabel);
    film.cut('09', 'Maya stalls, then stammers a denial');
    await film.run(1300);
    maya.mood = Mood.nervous;
    await film.run(1500);
    await film.speak(maya, 'Um… no? No. That was definitely not me.');
    await film.run(400);
    await film.tap('Final answer');
    film.relax(normal);
    film.step = 'Locking in the reading';
    await film.run(1500);
    await film.fast(() => film.until(() => game.phase == GamePhase.countdown));
    film
      ..step = 'The verdict'
      ..note =
          'It reads stress, not truth: a racing pulse means “nervous”, '
          'never “guilty”. For fun only.'
      ..cut('10', 'Maya winces at the buzzer, then owns up');
    await film.until(() => game.phase == GamePhase.verdict);
    film.report();
    await film.run(2400);
    maya.mood = Mood.laugh;
    await film.speak(maya, 'Okay, fine. It was me.', heard: false);
    await film.run(1200);
    await film.tap('See the winners');
    film
      ..step = 'Results'
      ..note =
          'Scores, awards and a replay of every question. Nothing is '
          'saved: it’s all wiped when a new game starts.'
      ..cut('11', 'Maya looks over her results');
    await film.run(4800);

    expect(game.phase, GamePhase.leaderboard);
    if (_withReal) await film.showCard(_closingCard, 3000);
    await film.finish();
  });

  testWidgets('demo film: a party game', skip: _skip, (tester) async {
    final film = Film(tester, 'party');
    await film.start();
    final game = film.game;
    final cast = _friends();
    final [sam, alex] = cast;
    const normals = {'Sam': 71.0, 'Alex': 77.0};
    film
      ..cast = cast
      ..presage.storedKey = 'pk_demo_film';
    film.presage.settle(normals['Sam']!);
    game.setDecks(_decks);

    await film.showCard(
      const TitleCard('Party', [
        'Two players, one phone. One answers, the other asks.',
        'Then they call it: Legit or Sus?',
      ], kicker: 'PART 2'),
      2200,
    );

    // Lobby.
    film
      ..chapter = 'PARTY GAME'
      ..step = 'Set up'
      ..note =
          'Two to eight players pass one phone around. Here it’s two: '
          'one sits in the hot seat, the other asks.'
      ..cut('01', 'Two friends at a table; one types in both names');
    await film.run(600);
    for (final a in cast) {
      await film.typeName(a.name);
    }
    await film.speak(alex, 'You go first, Sam.', heard: false, linger: 200);
    await film.tap('3');
    await film.tap('Start the show');
    film
      ..step = 'How to play'
      ..note =
          'Ask out loud, answer out loud, call it, then the meter '
          'shows its hand.';
    await film.run(1600);
    await film.tap("Got it, let's play");

    // Consent.
    film
      ..step = 'Consent'
      ..note =
          'The phone goes to the hot seat. Each player agrees to be '
          'measured, every game.'
      ..cut('02', 'Alex hands the phone to Sam, who reads and agrees');
    await film.run(1600);
    await film.tap('I agree, measure me');

    // Calibrate, mostly unfilmed (the solo game showed it).
    film
      ..step = 'Calibrate'
      ..note =
          'Sam sits still, then chats through three warm-ups, so the '
          'app knows Sam’s normal before the real questions.'
      ..cut('03', 'Sam sits still, facing the phone on the table');
    await film.run(4400);
    await film.fast(
      () => film.warmups(sam),
      label: 'a minute of warm-ups later',
    );
    film
      ..step = 'Calibrate · locked in'
      ..cut('04', 'Sam hears the normal is locked in and taps Start');
    await film.hostDone();
    await film.run(700);
    await film.tap('Start the questions', after: -1);

    // Question 1: Alex asks, Sam is calm, Alex calls it wrong.
    film
      ..step = 'Question 1 · Alex asks'
      ..note =
          'The host names who asks. The question shows up on screen as '
          'it’s spoken; speech is recognized on the phone only.'
      ..cut('05', 'Alex asks Sam a question out loud');
    await film.hostDone();
    await film.run(300);
    await film.speak(alex, 'Sam. Have you ever re-gifted a present?');
    await film.tap('Done asking');
    film
      ..step = 'Question 1 · Sam answers'
      ..cut('06', 'Sam answers straight away, relaxed');
    film.react(Take.calm, normals['Sam']!);
    await film.run(500);
    await film.speak(sam, 'Never. I keep every single thing I get.');
    await film.run(300);
    await film.tap('Final answer');
    await film.run(1300);
    await film.fast(() => film.until(() => game.phase == GamePhase.callIt));
    sam.mood = Mood.neutral;
    film
      ..step = 'Call it!'
      ..note =
          'Before the reveal, the other player votes Legit or Sus. '
          'Guessing what the meter says earns Best lie detector.'
      ..cut('07', 'Sam holds the phone out; Alex squints and taps Sus');
    await film.hostDone();
    await film.speak(alex, 'Mm. Too smooth.', heard: false, linger: 300);
    await film.tap('Sus');
    alex.paddleSus = true;
    await film.run(700);
    await film.tap('Reveal');
    film
      ..step = 'The verdict'
      ..note =
          'Drumroll, 3-2-1, then the score, how the room called it, '
          'and what moved: pulse, blinks and the pause.'
      ..cut('08', 'Both lean in for the countdown; Alex groans');
    await film.until(() => game.phase == GamePhase.verdict);
    film.report();
    alex.mood = Mood.surprised;
    sam.mood = Mood.laugh;
    await film.run(1700);
    await film.speak(alex, 'No way!', heard: false);
    await film.run(1100);
    for (final a in cast) {
      a
        ..mood = Mood.neutral
        ..paddleSus = null;
    }

    // Question 2: the hot one.
    await film.tap('Next question', after: -1);
    film
      ..step = 'Question 2 · Alex asks'
      ..note =
          'With two players, the other one asks every question. Stuck? '
          '“Suggest one” puts a deck question on the card to read out.'
      ..cut('09', 'Alex leans in and asks the awkward one');
    await film.until(() => !game.waitingForPulse);
    await film.hostDone();
    await film.run(300);
    alex.mood = Mood.happy;
    await film.speak(
      alex,
      'Have you ever eaten the last cookie and denied it?',
    );
    film.react(Take.rattled, normals['Sam']!);
    sam.mood = Mood.surprised;
    await film.run(500);
    await film.tap('Done asking');
    film
      ..step = 'Question 2 · Sam answers'
      ..note =
          'Sam’s pulse climbs above Sam’s own normal, the blinks come '
          'faster, and the answer takes a while to start.'
      ..cut('10', 'Sam freezes, then stammers a denial');
    await film.run(1200);
    sam.mood = Mood.nervous;
    await film.run(1500);
    await film.speak(sam, 'Uh… what? No. Who even counts cookies?');
    await film.run(400);
    await film.tap('Final answer');
    film.relax(normals['Sam']!);
    await film.run(1200);
    await film.fast(() => film.until(() => game.phase == GamePhase.callIt));
    alex.mood = Mood.neutral;
    film
      ..step = 'Call it!'
      ..note =
          'Reveal never waits for a vote, and a tap on your pick takes '
          'it back.'
      ..cut('11', 'Alex votes Sus without hesitating');
    await film.hostDone();
    await film.speak(alex, 'Sus. So sus.', heard: false, linger: 200);
    await film.tap('Sus');
    alex.paddleSus = true;
    await film.run(500);
    await film.tap('Reveal');
    film
      ..step = 'The verdict'
      ..note =
          'It reads stress, not truth. A racing pulse means “nervous”, '
          'never “guilty”.'
      ..cut('12', 'Alex cheers at the buzzer; Sam gives in');
    await film.until(() => game.phase == GamePhase.verdict);
    film.report();
    await film.run(900);
    alex.mood = Mood.laugh;
    await film.run(1500);
    sam.mood = Mood.laugh;
    await film.speak(sam, 'Okay! It was one cookie!', heard: false);
    await film.run(1000);
    for (final a in cast) {
      a
        ..mood = Mood.neutral
        ..paddleSus = null;
    }

    // Sam's last question, unfilmed.
    await film.fast(() async {
      await film.tap('Next question');
      await film.question(Take.uneasy, normals['Sam']!, votes: [true]);
      await film.tap('Next contestant');
      await film.until(() => game.phase == GamePhase.consent);
    }, label: 'question 3 later');

    // They swap: Alex in the hot seat, Sam asks.
    film
      ..step = 'Swap'
      ..note =
          'Then they swap. The phone goes to Alex, who agrees to be '
          'measured, and now Sam asks the questions.'
      ..cut('13', 'Sam hands the phone to Alex; they swap seats');
    film.presage.settle(normals['Alex']!);
    await film.run(900);
    await film.speak(sam, 'Your turn. Payback.', heard: false, linger: 300);
    await film.tap('I agree, measure me');
    await film.run(4100);
    await film.fast(() async {
      await film.warmups(alex);
      await film.hostDone();
      await film.tap('Start the questions');
      const takes = [Take.calm, Take.uneasy, Take.calm];
      for (var q = 0; q < 3; q++) {
        await film.question(takes[q], normals['Alex']!, votes: [q == 1]);
        if (q < 2) await film.tap('Next question');
      }
      await film.tap('See the winners');
    }, label: 'Alex’s turn later');

    // Leaderboard and replay.
    film
      ..step = 'And the winners are…'
      ..note =
          'Best poker face, Most sus, Best lie detector and Biggest '
          'spike. A tie is shared.'
      ..cut('14', 'Both lean over the phone for the awards');
    for (final a in cast) {
      a.mood = Mood.happy;
    }
    await film.run(1500);
    sam.mood = Mood.laugh;
    await film.speak(alex, 'Most sus: Sam. Obviously.', heard: false);
    await film.run(1800);
    await film.tap('Watch the replay');
    film
      ..step = 'The replay'
      ..note =
          'Every question again, with its pulse line. Nothing is '
          'saved: “Wipe everything” clears names, scores and transcripts.';
    await film.run(3200);
    expect(game.phase, GamePhase.replay);

    if (!_withReal) await film.showCard(_closingCard, 3000);
    await film.finish();
  });
}
