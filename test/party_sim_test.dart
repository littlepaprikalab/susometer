// Whole parties of made-up people (test/party_sim.dart) play through the
// real GameController, and the room's experience has to clear a bar: every
// game ends, no tap does nothing, a glance away never forces a question to
// be asked again, everyone gets to ask as often as everyone else, and the
// time spent on screens with nothing to tap stays a small share
// (SPEC.md decision 80).
//
// To see the tables the bars come from:
//
//   PARTY_SIM_REPORT=1 flutter test test/party_sim_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/game/scoring_config.dart';

import 'party_sim.dart';

final verbose = Platform.environment['PARTY_SIM_REPORT'] != null;

int sum(Iterable<int> x) => x.fold(0, (a, b) => a + b);
int median(Iterable<int> x) {
  final sorted = x.toList()..sort();
  return sorted[sorted.length ~/ 2];
}

String secs(int ms) => (ms / 1000).toStringAsFixed(1);
String mins(int ms) =>
    '${ms ~/ 60000}m${((ms % 60000) / 1000).round().toString().padLeft(2, '0')}s';

/// What a batch of games adds up to.
class Batch {
  Batch(this.reports);

  final List<PartyReport> reports;

  late final questions = [for (final r in reports) ...r.questions];
  late final played = questions.where((q) => !q.skipped).toList();
  late final time = () {
    final all = <String, int>{};
    for (final r in reports) {
      r.time.forEach((k, v) => all[k] = (all[k] ?? 0) + v);
    }
    return all;
  }();
  late final totalMs = sum(time.values);
  late final waitShare = sum(reports.map((r) => r.waitMs)) / totalMs;
  late final reAsked = questions.where((q) => q.asksNeeded > 1).length;
  late final pulseWaits = questions.where((q) => q.pulseWaitMs > 0).toList();
  late final longestPulseWaitMs = questions
      .map((q) => q.pulseWaitMs)
      .fold(0, (a, b) => a > b ? a : b);
  late final deadTaps = [for (final r in reports) ...r.deadTaps];
  late final medianGameMs = median(reports.map((r) => r.totalMs));

  String table(String title) {
    final shares = time.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final verdicts = <Verdict?, int>{};
    for (final q in played) {
      verdicts[q.verdict] = (verdicts[q.verdict] ?? 0) + 1;
    }
    return '''
--- $title (${reports.length} games) ---
game length: median ${mins(medianGameMs)}, ${mins(reports.map((r) => r.totalMs).reduce((a, b) => a < b ? a : b))} to ${mins(reports.map((r) => r.totalMs).reduce((a, b) => a > b ? a : b))}
time by screen: ${shares.where((e) => e.value / totalMs >= 0.005).map((e) => '${e.key} ${(100 * e.value / totalMs).round()}%').join(', ')}
nothing to tap (sit-still, lock-in, pulse wait, countdown): ${(100 * waitShare).round()}%
a turn before its first question: ${secs(sum(reports.map((r) => r.calibrationMs)) ~/ sum(reports.map((r) => r.calibrations)))} s
a question, ask to verdict: ${secs(sum(played.map((q) => q.totalMs)) ~/ played.length)} s (lock-in ${secs(sum(played.map((q) => q.settleMs)) ~/ played.length)} s, Call it! ${secs(sum(played.map((q) => q.callItMs)) ~/ played.length)} s)
questions: ${questions.length}, asked again $reAsked, skipped ${questions.length - played.length}
waited for the pulse: ${pulseWaits.length} (${(100 * pulseWaits.length / questions.length).round()}%), ${pulseWaits.isEmpty ? '-' : secs(sum(pulseWaits.map((q) => q.pulseWaitMs)) ~/ pulseWaits.length)} s on average, ${secs(longestPulseWaitMs)} s at most
verdicts: ${verdicts.entries.map((e) => '${e.key?.label} ${e.value}').join(', ')}; scored exactly 0: ${played.where((q) => q.score == 0).length}
votes: ${sum(questions.map((q) => q.votesCast))} in, ${sum(questions.map((q) => q.votesLost))} cut off by Reveal
taps: ${sum(reports.map((r) => r.taps))}, did nothing: ${deadTaps.length} $deadTaps
''';
  }
}

Batch games(
  int players,
  int questions,
  int count, {
  int pulseRecoveryMs = 3000,
  bool hostVoice = true,
  List<(String, Persona)> Function(int seed)? people,
}) => Batch([
  for (var seed = 1; seed <= count; seed++)
    playParty(
      people: people?.call(seed) ?? party(players, seed),
      questions: questions,
      seed: seed,
      pulseRecoveryMs: pulseRecoveryMs,
      hostVoice: hostVoice,
    ),
]);

void main() {
  // (players, questions per turn, games)
  const rooms = [(2, 3, 8), (3, 5, 8), (4, 5, 8), (6, 3, 6), (8, 7, 3)];

  for (final (players, questions, count) in rooms) {
    test('a room of $players, $questions questions each: the game flows', () {
      final b = games(players, questions, count);
      // ignore: avoid_print
      if (verbose) print(b.table('$players players × $questions questions'));

      for (final r in b.reports) {
        expect(r.finished, isTrue, reason: 'every game reaches the winners');
        expect(
          r.questions.length,
          players * questions,
          reason: 'every question is asked',
        );
        expect(r.asked, {
          for (final name in partyNames.take(players)) name: questions,
        }, reason: 'everyone asks as often as everyone else, never themselves');
        expect(r.awards!.ranked.length, players);
      }
      expect(b.deadTaps, isEmpty, reason: 'a deliberate tap always lands');
      expect(
        b.reAsked / b.questions.length,
        lessThanOrEqualTo(0.02),
        reason: 'a glance at the asker or a laugh never costs the question',
      );
      expect(
        b.waitShare,
        lessThan(0.3),
        reason: 'screens with nothing to tap stay under a third of the game',
      );
      expect(
        b.longestPulseWaitMs,
        lessThan(const ScoringConfig().pulseWaitHintAfterMs),
        reason: 'a wait for the pulse ends before its "still no pulse" hint',
      );

      // The lobby's estimate is on the generous side of the simulated room,
      // never short of it.
      final estimate =
          GameController.turnSetupS + questions * GameController.questionS;
      final estimateMs = players * estimate * 1000;
      expect(estimateMs, greaterThanOrEqualTo(b.medianGameMs));
      expect(estimateMs, lessThan(b.medianGameMs * 1.4));
    });
  }

  test('a slow camera: the pulse takes 10 s to come back after Call it!', () {
    // The hot seat holds the phone out for the vote, so the camera loses the
    // face on every question. How long the SDK then needs is device-only;
    // at 10 s most questions wait, and the game still flows.
    final b = games(4, 5, 6, pulseRecoveryMs: 10000);
    // ignore: avoid_print
    if (verbose) print(b.table('4 × 5, pulse back 10 s after the face'));
    for (final r in b.reports) {
      expect(r.finished, isTrue);
    }
    expect(b.deadTaps, isEmpty);
    expect(b.reAsked, 0, reason: 'the wait is what stops No clean read');
    expect(b.pulseWaits.length / b.questions.length, greaterThan(0.5));
    expect(b.longestPulseWaitMs, lessThan(15000));
    expect(b.waitShare, lessThan(0.4));
  });

  test('host voice off: the same room plays through on captions alone', () {
    final b = games(4, 3, 4, hostVoice: false);
    // ignore: avoid_print
    if (verbose) print(b.table('4 × 3, host voice off'));
    for (final r in b.reports) {
      expect(r.finished, isTrue);
      expect(r.questions.length, 12);
    }
    expect(b.deadTaps, isEmpty);
  });

  test('half the room sits the hot seat out: they still ask and vote', () {
    const shy = Persona('shy', skipsTurn: 1);
    final b = games(
      4,
      3,
      4,
      people: (seed) => [
        ('Sam', Persona.steady),
        ('Alex', shy),
        ('Priya', Persona.all[seed % Persona.all.length]),
        ('Jordan', shy),
      ],
    );
    for (final r in b.reports) {
      expect(r.finished, isTrue);
      expect(r.turnsSkipped, 2);
      expect(r.questions.length, 6);
      expect(
        r.asked.keys,
        containsAll(['Alex', 'Jordan']),
        reason: 'skipping the hot seat is not leaving the room',
      );
      expect(
        r.awards!.ranked.map((a) => a.player.name),
        unorderedEquals(['Sam', 'Priya']),
      );
      expect(r.awards!.unscored.map((p) => p.name), ['Alex', 'Jordan']);
    }
    expect(b.deadTaps, isEmpty);
  });

  test('askers with nothing to ask: Suggest one keeps the room moving, and '
      "the room's dithering never ends up in the question", () {
    final b = games(
      4,
      3,
      6,
      people: (seed) => [
        ('Sam', Persona.all[seed % Persona.all.length]),
        ('Alex', Persona.blank),
        ('Priya', Persona.steady),
        ('Jordan', Persona.blank),
      ],
    );
    // ignore: avoid_print
    if (verbose) print(b.table('4 × 3, two askers with nothing to ask'));
    final suggested = b.questions.where((q) => q.suggestions > 0).toList();
    expect(
      suggested.length,
      greaterThan(10),
      reason: 'the batch asks for some',
    );
    for (final r in b.reports) {
      expect(r.finished, isTrue);
      expect(r.questions.length, 12);
      for (final t in r.turns) {
        for (final q in t.results) {
          expect(q.scored, isTrue, reason: 'a suggested question still scores');
          expect(q.question, isNot(contains("don't know")));
          expect(q.question, startsWith('Have you ever'));
        }
      }
    }
    expect(b.deadTaps, isEmpty, reason: 'Suggest one always deals one');
    expect(b.reAsked, 0);
  });

  test('awards never hand a tie to one player', () {
    // Many answers score exactly 0, so level averages turn up in real
    // rooms, most often with three questions each. Whoever is level shares.
    var shared = 0;
    for (final (players, questions) in [(2, 3), (6, 3)]) {
      for (final r in games(players, questions, 12).reports) {
        final awards = r.awards!;
        final ranked = awards.ranked;
        final low = ranked.last.average;
        final high = ranked.first.average;
        final lowest = [
          for (final t in r.turns)
            if (t.averageScore == low) t.player.name,
        ];
        expect(awards.pokerFace!.players.map((p) => p.name), lowest);
        if (lowest.length > 1) shared++;
        if (low == high) {
          expect(
            awards.mostSus,
            isNull,
            reason: 'all level: nobody is most sus',
          );
        } else {
          expect(awards.mostSus!.players.map((p) => p.name), [
            for (final t in r.turns)
              if (t.averageScore == high) t.player.name,
          ]);
          expect(
            awards.mostSus!.players.toSet().intersection(
              awards.pokerFace!.players.toSet(),
            ),
            isEmpty,
          );
        }
        final spike = awards.biggestSpike;
        if (spike != null) expect(spike.result.score, greaterThan(0));
      }
    }
    expect(shared, greaterThan(0), reason: 'the batch has ties to share');
  });
}
