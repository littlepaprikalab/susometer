import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/awards.dart';
import 'package:susometer/game/decks.dart';
import 'package:susometer/game/models.dart';

QuestionResult scored(
  int index,
  int score, {
  Map<String, Vote> votes = const {},
  double raw = 0,
}) {
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
      raw: raw,
      score: score,
      verdict: verdictFor(score, legitBelow: 35, susFrom: 60),
    ),
  );
  r.votes.addAll(votes);
  return r;
}

void main() {
  group('decks (SPEC §11)', () {
    List<DeckQuestion> deck(String name) =>
        DeckLibrary.parse(File('assets/decks/$name.json').readAsStringSync());

    final files = {'warmup': 30, 'mild': 40, 'spicy': 40};
    for (final entry in files.entries) {
      test('${entry.key}.json has about ${entry.value} unique questions', () {
        final qs = [for (final q in deck(entry.key)) q.text];
        expect(qs.length, greaterThanOrEqualTo(entry.value));
        expect(qs.toSet().length, qs.length, reason: 'no duplicates');
        for (final q in qs) {
          expect(q.trim(), isNotEmpty);
          expect(q.length, lessThan(90), reason: 'fits the card: $q');
        }
      });
    }

    test('no question is in two decks', () {
      final seen = <String, String>{};
      for (final name in files.keys) {
        for (final q in deck(name)) {
          expect(seen[q.text], isNull, reason: '"${q.text}" is in both');
          seen[q.text] = name;
        }
      }
    });

    test('every warm-up has a slot, with plenty in each', () {
      final qs = deck('warmup');
      expect(qs.where((q) => q.slot == null), isEmpty);
      for (final slot in WarmupSlot.values) {
        expect(
          qs.where((q) => q.slot == slot).length,
          greaterThanOrEqualTo(10),
          reason: '$slot',
        );
      }
    });

    for (final name in ['mild', 'spicy']) {
      test('$name.json tags every question with a heat, '
          'with plenty at each heat for a player alone', () {
        final raw =
            jsonDecode(File('assets/decks/$name.json').readAsStringSync())
                as Map<String, Object?>;
        for (final q in raw['questions'] as List<Object?>) {
          expect((q as Map<String, Object?>)['heat'], isIn([1, 2, 3]));
        }
        final qs = deck(name);
        for (final heat in [1, 2, 3]) {
          expect(
            qs.where((q) => q.heat == heat && !q.room).length,
            greaterThanOrEqualTo(8),
            reason: 'heat $heat',
          );
        }
        expect(
          qs.where((q) => q.room && q.heat != 3),
          isEmpty,
          reason: 'room questions are finales',
        );
      });
    }

    test('parse: plain strings still load, objects carry their tags', () {
      final qs = DeckLibrary.parse(
        jsonEncode({
          'questions': [
            ' Plain? ',
            {'q': 'Hot?', 'heat': 3, 'room': true},
            {'q': 'Too hot?', 'heat': 9},
            {'q': 'Recall.', 'slot': 'recall'},
            {'q': 'Odd slot.', 'slot': 'nope'},
            {'q': '  '},
            {'heat': 1},
            42,
          ],
        }),
      );
      expect(
        [for (final q in qs) q.text],
        ['Plain?', 'Hot?', 'Too hot?', 'Recall.', 'Odd slot.'],
      );
      expect([for (final q in qs) q.heat], [2, 3, 3, 2, 2]);
      expect([for (final q in qs) q.room], [false, true, false, false, false]);
      expect(
        [for (final q in qs) q.slot],
        [null, null, null, WarmupSlot.recall, null],
      );
    });

    test('heat curve: rises through the turn and ends on 3', () {
      List<int> curve(int n) => [for (var i = 0; i < n; i++) heatFor(i, n)];
      expect(curve(3), [1, 2, 3]);
      expect(curve(5), [1, 1, 2, 2, 3]);
      expect(curve(7), [1, 1, 1, 2, 2, 3, 3]);
      expect(curve(1), [3]);
    });

    test('questions follow the curve, and every player gets the same one', () {
      final deck = [
        for (final heat in [1, 2, 3])
          for (var i = 0; i < 6; i++) DeckQuestion('h$heat-$i', heat: heat),
      ];
      final dealer = QuestionDealer(
        deck,
        othersPresent: false,
        random: Random(3),
      );
      for (var player = 0; player < 3; player++) {
        final heats = [
          for (var i = 0; i < 5; i++)
            int.parse(dealer.next(i, 5).substring(1, 2)),
        ];
        expect(heats, [1, 1, 2, 2, 3], reason: 'player $player');
      }
    });

    test('room questions only when someone else is playing', () {
      final deck = [
        const DeckQuestion('alone', heat: 3),
        const DeckQuestion('room', heat: 3, room: true),
      ];
      final alone = QuestionDealer(deck, othersPresent: false);
      expect({for (var i = 0; i < 20; i++) alone.next(0, 1)}, {'alone'});
      final party = QuestionDealer(deck, othersPresent: true);
      expect(
        {for (var i = 0; i < 20; i++) party.next(0, 1)},
        {'alone', 'room'},
      );
    });

    test('an empty heat falls back to the nearest one, cooler first', () {
      final dealer = QuestionDealer(const [
        DeckQuestion('one', heat: 1),
        DeckQuestion('three', heat: 3),
      ], othersPresent: false);
      expect(dealer.next(0, 3), 'one');
      expect(dealer.next(1, 3), 'three', reason: 'no repeat beats cooler');
      expect(dealer.next(2, 3), 'one', reason: 'no repeat beats hotter');
      final plain = QuestionDealer(const [
        DeckQuestion('a'),
        DeckQuestion('b'),
      ], othersPresent: false);
      expect({plain.next(0, 3), plain.next(2, 3)}, {'a', 'b'});
    });

    test('warm-ups come in slot order: recall, compare, light, again', () {
      final dealer = WarmupDealer([
        for (final slot in WarmupSlot.values)
          for (var i = 0; i < 3; i++)
            DeckQuestion('${slot.name}$i', slot: slot),
      ], random: Random(2));
      final dealt = [for (var n = 0; n < 4; n++) dealer.next(n)];
      expect(dealt[0], startsWith('recall'));
      expect(dealt[1], startsWith('compare'));
      expect(dealt[2], startsWith('light'));
      expect(dealt[3], startsWith('recall'));
      expect(dealer.next(3), allOf(startsWith('recall'), isNot(dealt[3])));
    });

    test('warm-ups without slots still deal', () {
      final dealer = WarmupDealer(const [DeckQuestion('x'), DeckQuestion('y')]);
      expect({dealer.next(0), dealer.next(1)}, {'x', 'y'});
      expect(WarmupDealer(const []).next(0), '');
    });

    test('dealer never repeats within a deck, then reshuffles', () {
      final items = [for (var i = 0; i < 10; i++) 'q$i'];
      final dealer = DeckDealer(items, random: Random(1));
      final first = [for (var i = 0; i < 10; i++) dealer.next()];
      expect(first.toSet().length, 10);
      final next = dealer.next();
      expect(
        next,
        isNot(first.last),
        reason: 'no immediate repeat on reshuffle',
      );
    });

    test('empty deck deals an empty string instead of crashing', () {
      expect(DeckDealer(const []).next(), '');
    });
  });

  group('awards (SPEC §2 screen 6, §5.6)', () {
    final sam = Player(id: 's', name: 'Sam');
    final alex = Player(id: 'a', name: 'Alex');
    final priya = Player(id: 'p', name: 'Priya');
    final jordan = Player(id: 'j', name: 'Jordan');

    List<PlayerTurn> game() {
      final ts = PlayerTurn(sam)
        ..results.addAll([scored(0, 82), scored(1, 60)]);
      final ta = PlayerTurn(alex)
        ..results.addAll([scored(0, 94), scored(1, 22)]);
      final tp = PlayerTurn(priya)
        ..results.addAll([scored(0, 10), scored(1, 26)]);
      final tj = PlayerTurn(jordan)..skipped = true;
      return [ts, ta, tp, tj];
    }

    test('poker face, most sus, biggest spike and ranking', () {
      final a = Awards.compute(game(), mode: GameMode.party);
      expect(a.mostSus!.player, sam);
      expect(a.mostSus!.average, 71);
      expect(a.pokerFace!.player, priya);
      expect(a.biggestSpike!.player, alex);
      expect(a.biggestSpike!.result.score, 94);
      expect(a.ranked.map((r) => r.player.name), ['Sam', 'Alex', 'Priya']);
      expect(a.unscored, [jordan]);
    });

    test('best lie detector: most matches, Hmm… never counts', () {
      final turns = [
        PlayerTurn(sam)
          ..results.addAll([
            scored(0, 82, votes: {'a': Vote.sus, 'p': Vote.legit}),
            scored(1, 20, votes: {'a': Vote.legit, 'p': Vote.legit}),
            scored(2, 50, votes: {'a': Vote.sus, 'p': Vote.sus}),
          ]),
        PlayerTurn(alex)
          ..results.add(scored(0, 70, votes: {'s': Vote.sus, 'p': Vote.sus})),
        PlayerTurn(priya),
      ];
      final a = Awards.compute(turns, mode: GameMode.party);
      // Alex: 2 of 2 (the Hmm… vote is ignored). Priya: 2 of 3. Sam: 1 of 1.
      expect(a.lieDetector!.player, alex);
      expect(a.lieDetector!.matches, 2);
      expect(a.lieDetector!.votes, 2);
    });

    test('ties go to the higher match rate', () {
      final turns = [
        PlayerTurn(sam)
          ..results.addAll([
            scored(0, 80, votes: {'a': Vote.sus, 'p': Vote.sus}),
            scored(1, 10, votes: {'a': Vote.legit, 'p': Vote.legit}),
            scored(2, 90, votes: {'p': Vote.legit}),
          ]),
        PlayerTurn(alex),
        PlayerTurn(priya),
      ];
      final a = Awards.compute(turns, mode: GameMode.party);
      expect(a.lieDetector!.player, alex, reason: '2/2 beats 2/3');
    });

    group('ties are shared, never handed to one player (decision 80)', () {
      test('level at the bottom: both are Best poker face', () {
        final a = Awards.compute([
          PlayerTurn(sam)..results.addAll([scored(0, 0), scored(1, 0)]),
          PlayerTurn(alex)..results.addAll([scored(0, 40), scored(1, 30)]),
          PlayerTurn(priya)..results.addAll([scored(0, 0), scored(1, 0)]),
        ], mode: GameMode.party);
        expect(a.pokerFace!.players, [sam, priya], reason: 'in turn order');
        expect(a.pokerFace!.names, 'Sam & Priya');
        expect(a.mostSus!.players, [alex]);
        expect(a.ranked.map((r) => r.player), [alex, sam, priya]);
        expect([for (var i = 0; i < 3; i++) a.placeOf(i)], [1, 2, 2]);
      });

      test('level at the top: both are Most sus', () {
        final a = Awards.compute([
          PlayerTurn(sam)..results.add(scored(0, 70)),
          PlayerTurn(alex)..results.add(scored(0, 10)),
          PlayerTurn(priya)..results.addAll([scored(0, 60), scored(1, 80)]),
          PlayerTurn(jordan)..results.add(scored(0, 70)),
        ], mode: GameMode.party);
        expect(a.mostSus!.players, [sam, priya, jordan]);
        expect(a.mostSus!.names, 'Sam, Priya & Jordan');
        expect(a.pokerFace!.players, [alex]);
        expect([for (var i = 0; i < 4; i++) a.placeOf(i)], [1, 1, 1, 4]);
      });

      test('everyone level: one shared poker face, nobody most sus, and a '
          'score of 0 is no spike', () {
        final a = Awards.compute([
          PlayerTurn(sam)..results.add(scored(0, 0)),
          PlayerTurn(alex)..results.add(scored(0, 0)),
          PlayerTurn(priya)..results.add(scored(0, 0)),
        ], mode: GameMode.party);
        expect(a.pokerFace!.players, [sam, alex, priya]);
        expect(a.mostSus, isNull);
        expect(a.biggestSpike, isNull);
        expect([for (var i = 0; i < 3; i++) a.placeOf(i)], [1, 1, 1]);
      });

      test('one scored player still gets both cards', () {
        final a = Awards.compute([
          PlayerTurn(sam)..results.add(scored(0, 44)),
          PlayerTurn(alex)..skipped = true,
        ], mode: GameMode.party);
        expect(a.pokerFace!.players, [sam]);
        expect(a.mostSus!.players, [sam]);
      });

      test('lie detectors level on matches and votes share it, in turn '
          'order whoever tapped first', () {
        final turns = [
          PlayerTurn(sam)
            ..results.addAll([
              // Priya taps before Alex both times.
              scored(0, 80, votes: {'p': Vote.sus, 'a': Vote.sus}),
              scored(1, 10, votes: {'p': Vote.legit, 'a': Vote.legit}),
            ]),
          PlayerTurn(alex),
          PlayerTurn(priya),
        ];
        final a = Awards.compute(turns, mode: GameMode.party);
        expect(a.lieDetector!.players, [alex, priya]);
        expect(a.lieDetector!.names, 'Alex & Priya');
        expect(a.lieDetector!.matches, 2);
        expect(a.lieDetector!.votes, 2);
      });

      test('a spike level on the score goes to the one higher before '
          'rounding', () {
        final a = Awards.compute([
          PlayerTurn(sam)..results.add(scored(0, 62, raw: 0.548)),
          PlayerTurn(alex)..results.add(scored(0, 62, raw: 0.553)),
        ], mode: GameMode.party);
        expect(a.biggestSpike!.player, alex);
      });

      test('names read as a list', () {
        expect(joinNames(const []), '');
        expect(joinNames(const ['Sam']), 'Sam');
        expect(joinNames(const ['Sam', 'Alex']), 'Sam & Alex');
        expect(joinNames(const ['Sam', 'Alex', 'Priya']), 'Sam, Alex & Priya');
      });
    });

    test('solo mode has no Best lie detector', () {
      expect(Awards.compute(game(), mode: GameMode.solo).lieDetector, isNull);
    });

    test('nobody scored: no awards, no crash', () {
      final a = Awards.compute([
        PlayerTurn(sam)..skipped = true,
      ], mode: GameMode.party);
      expect(a.ranked, isEmpty);
      expect(a.pokerFace, isNull);
      expect(a.mostSus, isNull);
      expect(a.biggestSpike, isNull);
      expect(a.unscored, [sam]);
    });
  });
}
