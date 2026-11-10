import 'models.dart';

/// Names for a card: "Sam", "Sam & Alex", "Sam, Alex & Priya".
String joinNames(Iterable<String> names) {
  final list = names.toList();
  if (list.length <= 1) return list.join();
  return '${list.sublist(0, list.length - 1).join(', ')} & ${list.last}';
}

class PlayerAverage {
  const PlayerAverage(this.player, this.average, this.count);

  final Player player;
  final double average;
  final int count;
}

/// Best poker face or Most sus: everyone on that average, in turn order. A
/// tie is shared, never handed to whoever happened to play first or last
/// (SPEC.md decision 80).
class AverageAward {
  const AverageAward(this.players, this.average);

  final List<Player> players;
  final double average;

  Player get player => players.first;
  String get names => joinNames(players.map((p) => p.name));
}

class LieDetectorAward {
  const LieDetectorAward(
    this.player,
    this.matches,
    this.votes, {
    this.tiedWith = const [],
  });

  final Player player;
  final int matches;
  final int votes;

  /// Voters with the same matches from the same number of votes: they share
  /// the award.
  final List<Player> tiedWith;

  double get rate => votes == 0 ? 0 : matches / votes;
  List<Player> get players => [player, ...tiedWith];
  String get names => joinNames(players.map((p) => p.name));
}

class BiggestSpike {
  const BiggestSpike(this.player, this.result);

  final Player player;
  final QuestionResult result;
}

/// Leaderboard awards (SPEC.md §2 screen 6, §5.6).
class Awards {
  const Awards({
    required this.ranked,
    this.pokerFace,
    this.mostSus,
    this.lieDetector,
    this.biggestSpike,
    this.unscored = const [],
  });

  /// Players with at least one scored question, most sus first.
  final List<PlayerAverage> ranked;
  final AverageAward? pokerFace;

  /// Null when two or more players all have the same average: nobody stood
  /// out, and they share Best poker face.
  final AverageAward? mostSus;
  final LieDetectorAward? lieDetector;

  /// Null when no answer scored above 0: nothing spiked.
  final BiggestSpike? biggestSpike;

  /// Players who skipped or got no clean reads.
  final List<Player> unscored;

  /// The place of `ranked[index]`, from 1. Equal averages share a place, so
  /// the list doesn't rank a tie either.
  int placeOf(int index) {
    var first = index;
    while (first > 0 && ranked[first - 1].average == ranked[index].average) {
      first--;
    }
    return first + 1;
  }

  static Awards compute(List<PlayerTurn> turns, {required GameMode mode}) {
    final ranked = <PlayerAverage>[];
    final unscored = <Player>[];
    BiggestSpike? spike;
    for (final turn in turns) {
      final avg = turn.averageScore;
      if (avg == null) {
        unscored.add(turn.player);
      } else {
        ranked.add(PlayerAverage(turn.player, avg, turn.scored.length));
      }
      for (final r in turn.scored) {
        if (r.score! <= 0) continue;
        if (spike == null || _spikier(r, spike.result)) {
          spike = BiggestSpike(turn.player, r);
        }
      }
    }
    // By average, most sus first; equal averages keep their turn order.
    final order = [for (var i = 0; i < ranked.length; i++) i]
      ..sort((a, b) {
        final c = ranked[b].average.compareTo(ranked[a].average);
        return c != 0 ? c : a.compareTo(b);
      });
    final sorted = [for (final i in order) ranked[i]];

    AverageAward? on(double average) => AverageAward([
      for (final r in ranked)
        if (r.average == average) r.player,
    ], average);
    final top = sorted.isEmpty ? null : sorted.first.average;
    final bottom = sorted.isEmpty ? null : sorted.last.average;
    final allTied = sorted.length > 1 && top == bottom;
    return Awards(
      ranked: sorted,
      mostSus: top == null || allTied ? null : on(top),
      pokerFace: bottom == null ? null : on(bottom),
      biggestSpike: spike,
      lieDetector: mode == GameMode.party ? _lieDetector(turns) : null,
      unscored: unscored,
    );
  }

  /// The higher score; between two questions on the same score, the one that
  /// was higher before rounding. Still level, the earlier one keeps it.
  static bool _spikier(QuestionResult a, QuestionResult b) {
    if (a.score! != b.score!) return a.score! > b.score!;
    return (a.breakdown?.raw ?? 0) > (b.breakdown?.raw ?? 0);
  }

  /// Most votes that matched the meter; ties go to the higher match rate,
  /// and voters level on both share it. Hmm… verdicts don't count either
  /// way (SPEC.md §5.6).
  static LieDetectorAward? _lieDetector(List<PlayerTurn> turns) {
    final matches = <String, int>{};
    final votes = <String, int>{};
    for (final turn in turns) {
      for (final r in turn.scored) {
        final verdict = r.verdict!;
        if (verdict == Verdict.hmm) continue;
        r.votes.forEach((voterId, vote) {
          votes[voterId] = (votes[voterId] ?? 0) + 1;
          final hit =
              (vote == Vote.sus && verdict == Verdict.sus) ||
              (vote == Vote.legit && verdict == Verdict.legit);
          if (hit) matches[voterId] = (matches[voterId] ?? 0) + 1;
        });
      }
    }
    // In turn order, so a shared award lists its winners the way the lobby
    // listed them, not in the order they happened to tap.
    final best = <LieDetectorAward>[];
    for (final turn in turns) {
      final id = turn.player.id;
      final cast = votes[id];
      if (cast == null) continue;
      final award = LieDetectorAward(turn.player, matches[id] ?? 0, cast);
      if (award.matches == 0) continue;
      final lead = best.isEmpty ? null : best.first;
      if (lead == null ||
          award.matches > lead.matches ||
          (award.matches == lead.matches && award.votes < lead.votes)) {
        best
          ..clear()
          ..add(award);
      } else if (award.matches == lead.matches && award.votes == lead.votes) {
        best.add(award);
      }
    }
    if (best.isEmpty) return null;
    return LieDetectorAward(
      best.first.player,
      best.first.matches,
      best.first.votes,
      tiedWith: [for (final a in best.skip(1)) a.player],
    );
  }
}
