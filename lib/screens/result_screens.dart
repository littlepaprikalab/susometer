import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../game/awards.dart';
import '../game/game_controller.dart';
import '../game/models.dart';
import '../theme/game_widgets.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';

Color verdictColor(Verdict? v) => switch (v) {
  Verdict.legit => SusColors.teal,
  Verdict.hmm => SusColors.brown,
  Verdict.sus => SusColors.tomato,
  null => SusColors.ink,
};

/// Call it! — the room votes before the reveal (SPEC.md §5.6; not mocked).
class CallItScreen extends StatelessWidget {
  const CallItScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final left = ((game.callItDeadlineMs - game.nowMs) / 1000).ceil().clamp(
      0,
      10,
    );
    return ScreenFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: HotSeatPill(
                  "${game.currentPlayer.name}'s in the hot seat",
                ),
              ),
              const SizedBox(width: 8),
              Text('Reveal in ${left}s', style: SusText.display(16)),
            ],
          ),
          const SizedBox(height: 14),
          MarqueeBoard(
            color: SusColors.ink,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  Text(
                    'Call it!',
                    style: SusText.display(44, color: SusColors.mustard),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Legit or sus? Vote before the meter shows its hand.',
                    textAlign: TextAlign.center,
                    style: SusText.body(
                      15,
                      weight: FontWeight.w600,
                      color: SusColors.cream,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${game.currentPlayer.name}, hold the phone out. Everyone else: tap your name until it shows your call.',
            style: SusText.body(15, weight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final chipWidth = (constraints.maxWidth - 10) / 2;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final p in game.voters)
                        SizedBox(
                          width: chipWidth,
                          child: _VoteChip(
                            player: p,
                            vote: game.pendingVotes[p.id],
                            onTap: () => game.cycleVote(p.id),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          Text(
            'Measuring is done, so wiggle all you like. No tap means no vote.',
            textAlign: TextAlign.center,
            style: SusText.body(13, weight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ChunkyButton(
            label: 'Reveal',
            height: 60,
            fontSize: 22,
            onPressed: game.reveal,
          ),
        ],
      ),
    );
  }
}

class _VoteChip extends StatelessWidget {
  const _VoteChip({
    required this.player,
    required this.vote,
    required this.onTap,
  });

  final Player player;
  final Vote? vote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (vote) {
      null => (SusColors.cream, SusColors.ink, 'Tap to vote'),
      Vote.legit => (SusColors.teal, SusColors.cream, 'Legit'),
      Vote.sus => (SusColors.tomatoDeep, SusColors.cream, 'Sus'),
    };
    return Semantics(
      button: true,
      label: '${player.name}: ${vote == null ? 'no vote' : label}',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: SusColors.ink,
              width: SusShape.borderWidth,
            ),
            boxShadow: const [
              BoxShadow(color: SusColors.ink, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                player.name,
                overflow: TextOverflow.ellipsis,
                style: SusText.body(17, weight: FontWeight.w700, color: fg),
              ),
              Text(
                label,
                style: SusText.display(vote == null ? 15 : 22, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Countdown — mustard, flashing marquee bulbs, giant 3… 2… 1… (not mocked).
class CountdownScreen extends StatelessWidget {
  const CountdownScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final n = game.countdownValue.clamp(1, 3);
    final phase = (game.nowMs ~/ 250) % 2;
    return ScreenFrame(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        children: [
          BulbRow(count: 11, size: 18, phase: phase),
          Expanded(
            child: Row(
              children: [
                _BulbColumn(phase: phase),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('The Sus-o-meter says…', style: SusText.display(24)),
                      const SizedBox(height: 10),
                      Semantics(
                        liveRegion: true,
                        label: '$n',
                        child: Text('$n', style: SusText.display(220)),
                      ),
                      Text(
                        '${game.currentPlayer.name}, brace yourself',
                        style: SusText.body(16, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                _BulbColumn(phase: 1 - phase),
              ],
            ),
          ),
          BulbRow(count: 11, size: 18, phase: 1 - phase),
        ],
      ),
    );
  }
}

class _BulbColumn extends StatelessWidget {
  const _BulbColumn({required this.phase});

  final int phase;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < 12; i++)
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: (i + phase).isEven
                  ? SusColors.bulb
                  : const Color(0xFF8A7A5A),
              shape: BoxShape.circle,
              border: Border.all(color: SusColors.ink, width: 2),
            ),
          ),
      ],
    );
  }
}

/// 5 · Verdict (mock: Verdict.dc.html; the vote moved to Call it!).
class VerdictScreen extends StatelessWidget {
  const VerdictScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final r = game.currentResult;
    if (r == null || r.breakdown == null) {
      return const ScreenFrame(child: SizedBox());
    }
    final b = r.breakdown!;
    final name = game.currentPlayer.name;
    final pulseDelta = r.pulseDelta;
    final blinkDelta = r.blinkDeltaFraction;
    final hes = r.features?.hesitationS;
    final last = game.isLastQuestion;
    final primary = !last
        ? 'Next question'
        : (game.isLastPlayer ? 'See the winners' : 'Next contestant');
    return ScreenFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Question ${game.questionIndex + 1}',
                style: SusText.display(18),
              ),
              const SizedBox(width: 8),
              Flexible(child: HotSeatPill("$name's in the hot seat")),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SusCard(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Q: “${r.question}”',
                          style: SusText.body(16, weight: FontWeight.w700),
                        ),
                        if (r.answer.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            '$name: “${r.answer}”',
                            style: SusText.body(
                              15,
                            ).copyWith(fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Semantics(
                    label:
                        'The Sus-o-meter says ${b.score}, ${b.verdict.label}',
                    excludeSemantics: true,
                    child: MarqueeBoard(
                      color: verdictColor(b.verdict),
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: SusColors.cream,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'THE SUS-O-METER SAYS',
                              style: SusText.label(
                                13,
                              ).copyWith(letterSpacing: 1),
                            ),
                          ),
                          Text(
                            '${b.score}',
                            style: SusText.display(96, color: SusColors.cream),
                          ),
                          Text(
                            b.verdict.label,
                            style: SusText.display(38, color: SusColors.cream),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ApplauseMeter(score: b.score),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Cool as ice', style: SusText.label(13)),
                      Text('Caught red-handed', style: SusText.label(13)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          value: pulseDelta == null
                              ? '--'
                              : _signed(pulseDelta.round()),
                          label: 'pulse',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatTile(
                          value: blinkDelta == null
                              ? '--'
                              : '${_signed((blinkDelta * 100).round())}%',
                          label: 'blinks',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatTile(
                          value: hes == null
                              ? '--'
                              : '${hes.toStringAsFixed(1)}s',
                          label: 'pause',
                        ),
                      ),
                    ],
                  ),
                  if (r.votes.isNotEmpty || game.mode == GameMode.party) ...[
                    const SizedBox(height: 14),
                    _VotesSummary(game: game, result: r),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!last) ...[
                Expanded(
                  child: ChunkyButton.light(
                    label: 'End turn',
                    fontSize: 15,
                    onPressed: game.endTurn,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: 2,
                child: ChunkyButton(
                  label: primary,
                  fontSize: 19,
                  onPressed: game.nextQuestion,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _signed(int v) => v > 0 ? '+$v' : '$v';
}

class _VotesSummary extends StatelessWidget {
  const _VotesSummary({required this.game, required this.result});

  final GameController game;
  final QuestionResult result;

  @override
  Widget build(BuildContext context) {
    final verdict = result.verdict;
    if (result.votes.isEmpty) {
      return Text(
        'Nobody called it this time.',
        textAlign: TextAlign.center,
        style: SusText.body(14, weight: FontWeight.w600),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How the room called it',
          textAlign: TextAlign.center,
          style: SusText.label(14),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in game.voters)
              if (result.votes[p.id] != null)
                DotChip(
                  outlined: true,
                  fontSize: 13,
                  label:
                      '${p.name}: ${result.votes[p.id] == Vote.sus ? 'Sus' : 'Legit'}'
                      '${_matched(result.votes[p.id]!, verdict) ? ' · matched' : ''}',
                  dot: result.votes[p.id] == Vote.sus
                      ? SusColors.tomato
                      : SusColors.teal,
                ),
          ],
        ),
      ],
    );
  }

  static bool _matched(Vote v, Verdict? verdict) =>
      (v == Vote.sus && verdict == Verdict.sus) ||
      (v == Vote.legit && verdict == Verdict.legit);
}

/// 6 · Leaderboard (mock: Leaderboard.dc.html).
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key, this.onShare, this.shareKey});

  final VoidCallback? onShare;
  final GlobalKey? shareKey;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final awards = game.awards ?? const Awards(ranked: []);
    return ScreenFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('And the winners are…', style: SusText.display(34)),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (awards.ranked.isEmpty)
                    SusCard(
                      child: Text(
                        'No clean reads this game, so no winners. The meter never fakes a verdict.',
                        style: SusText.body(15, weight: FontWeight.w600),
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: _AwardCard(
                            title: 'Best poker face',
                            name: awards.pokerFace!.player.name,
                            detail: 'avg ${awards.pokerFace!.average.round()}',
                            dot: SusColors.teal,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _AwardCard(
                            title: 'Most sus',
                            name: awards.mostSus!.player.name,
                            detail: 'avg ${awards.mostSus!.average.round()}',
                            dot: SusColors.tomato,
                          ),
                        ),
                      ],
                    ),
                    if (awards.lieDetector != null) ...[
                      const SizedBox(height: 10),
                      _LieDetectorCard(award: awards.lieDetector!),
                    ],
                    if (awards.biggestSpike != null) ...[
                      const SizedBox(height: 14),
                      _SpikeBoard(spike: awards.biggestSpike!),
                    ],
                    const SizedBox(height: 14),
                    for (var i = 0; i < awards.ranked.length; i++) ...[
                      _RankRow(pos: i + 1, avg: awards.ranked[i]),
                      const SizedBox(height: 7),
                    ],
                  ],
                  for (final p in awards.unscored)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Text(
                        '${p.name}: no score (skipped or no clean read)',
                        style: SusText.body(14, weight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          ChunkyButton(
            label: 'Play again',
            fontSize: 21,
            onPressed: game.playAgain,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ChunkyButton.light(
                  label: 'Watch the replay',
                  height: 48,
                  fontSize: 15,
                  onPressed: game.openReplay,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChunkyButton.light(
                  label: 'Share results',
                  height: 48,
                  fontSize: 15,
                  onPressed: awards.ranked.isEmpty ? null : onShare,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Scores are wiped when a new game starts or when you tap Wipe.',
            textAlign: TextAlign.center,
            style: SusText.body(13, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _AwardCard extends StatelessWidget {
  const _AwardCard({
    required this.title,
    required this.name,
    required this.detail,
    required this.dot,
  });

  final String title;
  final String name;
  final String detail;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SusColors.cream,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SusColors.ink, width: SusShape.borderWidth),
        boxShadow: const [
          BoxShadow(color: SusColors.ink, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: SusText.label(13)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(name, style: SusText.display(26)),
          ),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(detail, style: SusText.label(14)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LieDetectorCard extends StatelessWidget {
  const _LieDetectorCard({required this.award});

  final LieDetectorAward award;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: SusColors.cream,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SusColors.ink, width: SusShape.borderWidth),
        boxShadow: const [
          BoxShadow(color: SusColors.ink, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          const IconBadge(icon: Icons.manage_search_rounded, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Best lie detector', style: SusText.label(13)),
                Text(award.player.name, style: SusText.display(22)),
              ],
            ),
          ),
          Text(
            'Matched the\nmeter ${award.matches} of ${award.votes}',
            textAlign: TextAlign.right,
            style: SusText.label(14),
          ),
        ],
      ),
    );
  }
}

class _SpikeBoard extends StatelessWidget {
  const _SpikeBoard({required this.spike});

  final BiggestSpike spike;

  @override
  Widget build(BuildContext context) {
    return MarqueeBoard(
      color: SusColors.tomato,
      radius: 22,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Row(
          children: [
            Text(
              '${spike.result.score}',
              style: SusText.display(58, color: SusColors.cream),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: SusColors.cream,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BIGGEST SPIKE · ${spike.player.name.toUpperCase()}',
                      style: SusText.label(12).copyWith(letterSpacing: 0.7),
                    ),
                    Text(
                      '“${spike.result.question}”',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: SusText.body(15, weight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.pos, required this.avg});

  final int pos;
  final PlayerAverage avg;

  @override
  Widget build(BuildContext context) {
    final score = avg.average.round();
    final color = score >= 60
        ? SusColors.tomato
        : (score < 35 ? SusColors.teal : const Color(0xFFE7C64A));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: SusColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SusColors.ink, width: 2.5),
      ),
      child: Row(
        children: [
          SizedBox(width: 22, child: Text('$pos', style: SusText.display(16))),
          SizedBox(
            width: 78,
            child: Text(
              avg.player.name,
              overflow: TextOverflow.ellipsis,
              style: SusText.body(15, weight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                color: SusColors.unlit,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: SusColors.ink, width: 2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (score / 100).clamp(0.0, 1.0),
                child: Container(color: color),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$score',
              textAlign: TextAlign.right,
              style: SusText.display(16),
            ),
          ),
        ],
      ),
    );
  }
}

/// 7 · Replay (mock: Replay.dc.html).
class ReplayScreen extends StatefulWidget {
  const ReplayScreen({super.key});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final turns = game.turns.where((t) => t.results.isNotEmpty).toList();
    final tab = turns.isEmpty ? 0 : _tab.clamp(0, turns.length - 1);
    return ScreenFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RoundIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back to scores',
                onPressed: game.backToLeaderboard,
              ),
              const SizedBox(width: 12),
              Text('The replay', style: SusText.display(32)),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < turns.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Semantics(
                    button: true,
                    selected: i == tab,
                    label: turns[i].player.name,
                    excludeSemantics: true,
                    onTap: () => setState(() => _tab = i),
                    child: GestureDetector(
                      onTap: () => setState(() => _tab = i),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == tab ? SusColors.ink : SusColors.cream,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: SusColors.ink, width: 2.5),
                        ),
                        child: Text(
                          turns[i].player.name,
                          style: SusText.body(
                            14,
                            weight: FontWeight.w700,
                            color: i == tab ? SusColors.mustard : SusColors.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: turns.isEmpty
                ? Text(
                    'Nothing to replay yet.',
                    style: SusText.body(15, weight: FontWeight.w600),
                  )
                : ListView(
                    children: [
                      for (final r in turns[tab].results) ...[
                        _ReplayCard(result: r),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            'Transcripts live in memory only. Gone when you wipe or close the app.',
            textAlign: TextAlign.center,
            style: SusText.body(13, weight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ChunkyButton.light(
                  label: 'Wipe everything',
                  icon: Icons.delete_outline_rounded,
                  height: 56,
                  fontSize: 15,
                  onPressed: game.wipeAll,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChunkyButton(
                  label: 'Play again',
                  height: 56,
                  fontSize: 19,
                  onPressed: game.playAgain,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReplayCard extends StatelessWidget {
  const _ReplayCard({required this.result});

  final QuestionResult result;

  @override
  Widget build(BuildContext context) {
    final v = result.verdict;
    final label = result.skipped
        ? 'Skip'
        : switch (v) {
            Verdict.legit => 'Legit',
            Verdict.hmm => 'Hmm',
            Verdict.sus => 'Sus!',
            null => '—',
          };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: SusColors.cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SusColors.ink, width: 2.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.question,
                  style: SusText.body(15, weight: FontWeight.w700),
                ),
                if (result.answer.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    '“${result.answer}”',
                    style: SusText.body(
                      14,
                    ).copyWith(fontStyle: FontStyle.italic),
                  ),
                ],
                if (result.pulseSpark.length > 1) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 22,
                    width: 200,
                    child: CustomPaint(
                      painter: WaveformLinePainter(
                        _downsample(result.pulseSpark, 30),
                        SusColors.ink,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 60,
            height: 64,
            decoration: BoxDecoration(
              color: result.skipped
                  ? SusColors.ink
                  : (v == Verdict.sus ? SusColors.tomatoDeep : verdictColor(v)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SusColors.ink, width: 2.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  result.score?.toString() ?? '–',
                  style: SusText.display(24, color: SusColors.cream),
                ),
                Text(label, style: SusText.label(12, color: SusColors.cream)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<double> _downsample(List<double> values, int n) {
    if (values.length <= n) return values;
    final step = values.length / n;
    return [
      for (var i = 0; i < n; i++)
        values[math.min(values.length - 1, (i * step).floor())],
    ];
  }
}
