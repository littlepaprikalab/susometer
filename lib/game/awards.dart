import 'models.dart';

class PlayerAverage {
  const PlayerAverage(this.player, this.average, this.count);

  final Player player;
  final double average;
  final int count;
}

class LieDetectorAward {
  const LieDetectorAward(this.player, this.matches, this.votes);

  final Player player;
  final int matches;
  final int votes;

  double get rate => votes == 0 ? 0 : matches / votes;
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
  final PlayerAverage? pokerFace;
  final PlayerAverage? mostSus;
  final LieDetectorAward? lieDetector;
  final BiggestSpike? biggestSpike;

  /// Players who skipped or got no clean reads.
  final List<Player> unscored;

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
        if (spike == null || r.score! > spike.result.score!) {
          spike = BiggestSpike(turn.player, r);
        }
      }
    }
    ranked.sort((a, b) => b.average.compareTo(a.average));
    return Awards(
      ranked: ranked,
      mostSus: ranked.isEmpty ? null : ranked.first,
      pokerFace: ranked.isEmpty ? null : ranked.last,
      biggestSpike: spike,
      lieDetector: mode == GameMode.party ? _lieDetector(turns) : null,
      unscored: unscored,
    );
  }

  /// Most votes that matched the meter; ties go to the higher match rate.
  /// Hmm… verdicts don't count either way (SPEC.md §5.6).
  static LieDetectorAward? _lieDetector(List<PlayerTurn> turns) {
    final players = {for (final t in turns) t.player.id: t.player};
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
    LieDetectorAward? best;
    for (final entry in votes.entries) {
      final player = players[entry.key];
      if (player == null) continue;
      final award = LieDetectorAward(
        player,
        matches[entry.key] ?? 0,
        entry.value,
      );
      if (award.matches == 0) continue;
      if (best == null ||
          award.matches > best.matches ||
          (award.matches == best.matches && award.rate > best.rate)) {
        best = award;
      }
    }
    return best;
  }
}
