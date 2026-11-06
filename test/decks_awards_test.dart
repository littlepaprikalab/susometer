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
      raw: 0,
      score: score,
      verdict: verdictFor(score, legitBelow: 35, susFrom: 60),
    ),
  );
  r.votes.addAll(votes);
  return r;
}

void main() {
  group('decks (SPEC §11)', () {
    final files = {'warmup': 30, 'mild': 40, 'spicy': 40};
    for (final entry in files.entries) {
      test('${entry.key}.json has about ${entry.value} unique questions', () {
        final raw = File('assets/decks/${entry.key}.json').readAsStringSync();
        final qs = DeckLibrary.parse(raw);
        expect(qs.length, greaterThanOrEqualTo(entry.value));
        expect(qs.toSet().length, qs.length, reason: 'no duplicates');
        for (final q in qs) {
          expect(q.trim(), isNotEmpty);
          expect(q.length, lessThan(90), reason: 'fits the card: $q');
        }
      });
    }

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
