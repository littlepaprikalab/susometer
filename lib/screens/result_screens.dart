import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../game/awards.dart';
import '../game/game_controller.dart';
import '../game/models.dart';
import '../theme/fit_text.dart';
import '../theme/game_widgets.dart';
import '../theme/sparkline.dart';
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
    // No timer: the reveal waits for the tap (SPEC.md decision 76).
    final voted = game.pendingVotes.length;
    final waiting = [
      for (final p in game.voters)
        if (!game.pendingVotes.containsKey(p.id)) p.name,
    ];
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
              Text(
                '$voted / ${game.voters.length} voted',
                style: SusText.display(16),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // The board, the instructions and the voters scroll together, so on
          // a small phone at a large text size the voters get the whole
          // height instead of a strip under a fixed board.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MarqueeBoard(
                    color: SusColors.ink,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        children: [
                          Text(
                            'Call it!',
                            style: SusText.display(
                              44,
                              color: SusColors.mustard,
                            ),
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
                    '${game.currentPlayer.name}, hold the phone out. Everyone else: pick by your name.',
                    style: SusText.body(15, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  for (final (i, p) in game.voters.indexed) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _VoteRow(
                      player: p,
                      vote: game.pendingVotes[p.id],
                      onVote: (v) => game.castVote(p.id, v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Tap a pick again to take it back. No pick, no vote.',
                    textAlign: TextAlign.center,
                    style: SusText.body(13, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Reveal never waits for anyone (someone may be sitting this one
          // out), but one eager tap used to cost the rest of the room its
          // votes. So the button says who it would cut off, and only turns
          // into the solid "go" button once everyone's in (SPEC.md
          // decisions 80 and 90).
          if (waiting.isEmpty)
            ChunkyButton(
              label: 'Reveal',
              hint: stillToCall(waiting),
              shorterHints: [
                if (waiting.isNotEmpty) 'Still to call it: ${waiting.length}',
              ],
              height: 60,
              fontSize: 22,
              onPressed: game.reveal,
            )
          else
            ChunkyButton.light(
              label: 'Reveal',
              hint: stillToCall(waiting),
              shorterHints: [
                if (waiting.isNotEmpty) 'Still to call it: ${waiting.length}',
              ],
              height: 60,
              fontSize: 22,
              onPressed: game.reveal,
            ),
        ],
      ),
    );
  }
}

/// Reveal's hint: who hasn't picked yet ([waiting], in voter order). Two
/// names at most, so it stays one readable line with seven voters.
String stillToCall(List<String> waiting) => switch (waiting.length) {
  0 => "Everyone's in",
  1 || 2 => 'Still to call it: ${joinNames(waiting)}',
  final n => 'Still to call it: ${waiting.first} and ${n - 1} more',
};

/// One voter on Call it!: their name, then Legit and Sus to pick from
/// (SPEC.md decision 77). The pick fills with its verdict's color and a
/// check; picking it again takes the vote back.
class _VoteRow extends StatelessWidget {
  const _VoteRow({
    required this.player,
    required this.vote,
    required this.onVote,
  });

  final Player player;
  final Vote? vote;
  final ValueChanged<Vote> onVote;

  /// Leaves each pick 50 pt tall inside the border and padding.
  static const height = 64.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: SusColors.cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SusColors.ink, width: SusShape.borderWidth),
      ),
      child: Row(
        children: [
          // The body face, at the largest size that fits, on two lines if it
          // must: the display face is so wide that a long name beside two
          // buttons would shrink too small to read.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FitText(
                player.name,
                sizes: const [19, 17, 15, 13],
                overflow: FitOverflow.keepStart,
                style: (size) => SusText.body(size, weight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 8),
          for (final v in Vote.values) ...[
            if (v != Vote.values.first) const SizedBox(width: 6),
            _VotePick(
              name: player.name,
              vote: v,
              on: vote == v,
              onTap: () => onVote(v),
            ),
          ],
        ],
      ),
    );
  }
}

class _VotePick extends StatelessWidget {
  const _VotePick({
    required this.name,
    required this.vote,
    required this.on,
    required this.onTap,
  });

  final String name;
  final Vote vote;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = vote == Vote.legit ? 'Legit' : 'Sus';
    final fill = vote == Vote.legit ? SusColors.teal : SusColors.tomatoDeep;
    final fg = on ? SusColors.cream : SusColors.ink;
    return Semantics(
      button: true,
      selected: on,
      label: '$name: $label',
      hint: on ? 'Tap again to take it back' : null,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 120),
          width: 86,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: on ? fill : SusColors.cream,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SusColors.ink, width: 2.5),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (on) ...[
                  Icon(Icons.check_rounded, size: 20, color: fg),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  maxLines: 1,
                  style: SusText.body(17, weight: FontWeight.w800, color: fg),
                ),
              ],
            ),
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
                  // The room's calls come straight after the score, above
                  // the fold even on a small phone at large text: under the
                  // chart, nobody scrolled down to see who'd matched
                  // (SPEC.md decision 80).
                  if (r.votes.isNotEmpty || game.mode == GameMode.party) ...[
                    const SizedBox(height: 16),
                    _VotesSummary(game: game, result: r),
                  ],
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
                  if (r.pulseTrace.length > 1) ...[
                    const SizedBox(height: 14),
                    _PulseCard(result: r),
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
                // Who asks next, while the room is still looking at the
                // verdict: on Ask they'd hear it only as their question was
                // due (decision 80). On the button it's about (decision 90).
                child: ChunkyButton(
                  label: primary,
                  hint: switch (game.nextAsker) {
                    final asker? => '${asker.name} asks next',
                    null => null,
                  },
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
          // A Hmm… matches neither call (SPEC.md §5.6): say so, or a voter
          // with no "matched" by their name reads it as a miss.
          verdict == Verdict.hmm
              ? 'How the room called it · Hmm… matches nobody'
              : 'How the room called it',
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
                // A long name's chip shrinks to the row rather than run off
                // the screen at large text sizes.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: DotChip(
                    outlined: true,
                    fontSize: 13,
                    label:
                        '${p.name}: ${result.votes[p.id] == Vote.sus ? 'Sus' : 'Legit'}'
                        '${_matched(result.votes[p.id]!, verdict) ? ' · matched' : ''}',
                    dot: result.votes[p.id] == Vote.sus
                        ? SusColors.tomato
                        : SusColors.teal,
                  ),
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
  const LeaderboardScreen({
    super.key,
    this.onShare,
    this.onPlayAgain,
    this.shareKey,
  });

  final VoidCallback? onShare;

  /// "Play again". The game's own (which wipes at once) unless the page
  /// asks first, as GameRoot does.
  final VoidCallback? onPlayAgain;
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
                    // A tie is shared (SPEC.md decision 80). With everyone
                    // level there's no Most sus, and Best poker face gets
                    // the whole row.
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _AwardCard(
                              title: 'Best poker face',
                              name: awards.pokerFace!.names,
                              shared: awards.pokerFace!.players.length > 1,
                              detail:
                                  'avg ${awards.pokerFace!.average.round()}',
                              dot: SusColors.teal,
                            ),
                          ),
                          if (awards.mostSus case final mostSus?) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: _AwardCard(
                                title: 'Most sus',
                                name: mostSus.names,
                                shared: mostSus.players.length > 1,
                                detail: 'avg ${mostSus.average.round()}',
                                dot: SusColors.tomato,
                              ),
                            ),
                          ],
                        ],
                      ),
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
                      _RankRow(pos: awards.placeOf(i), avg: awards.ranked[i]),
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
            onPressed: onPlayAgain ?? game.playAgain,
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
    this.shared = false,
  });

  final String title;
  final String name;

  /// More than one winner: see [_WinnerNames].
  final bool shared;
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
          _WinnerNames(name, shared: shared, size: 26),
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

/// An award's winner. One name shrinks to fit on its line, as it always
/// did. Shared names wrap at a size that stays readable: shrunk onto one
/// line, four names came out at 10 pt and eight would be unreadable.
class _WinnerNames extends StatelessWidget {
  const _WinnerNames(this.names, {required this.shared, required this.size});

  final String names;
  final bool shared;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (shared) return Text(names, style: SusText.display(17));
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(names, style: SusText.display(size)),
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
                _WinnerNames(
                  award.names,
                  shared: award.players.length > 1,
                  size: 22,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
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
  const ReplayScreen({super.key, this.onPlayAgain});

  /// "Play again": see [LeaderboardScreen.onPlayAgain].
  final VoidCallback? onPlayAgain;

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
          // One contestant gets a name line: a lone tab has nothing to
          // switch to and reads as a stray button.
          if (turns.length == 1) ...[
            _ReplayName(turn: turns.first),
            const SizedBox(height: 14),
          ] else if (turns.length > 1) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < turns.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    _ReplayTab(
                      player: turns[i].player,
                      selected: i == tab,
                      onTap: () => setState(() => _tab = i),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
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
                  onPressed: widget.onPlayAgain ?? game.playAgain,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The Replay's heading when only one contestant played: avatar and name, set
/// like the Lobby's player rows, and how many questions are below.
class _ReplayName extends StatelessWidget {
  const _ReplayName({required this.turn});

  final PlayerTurn turn;

  @override
  Widget build(BuildContext context) {
    final count = turn.results.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Avatar(initial: turn.player.initial),
          const SizedBox(width: 10),
          // Long names shrink to fit rather than lose letters to "…".
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                turn.player.name,
                maxLines: 1,
                style: SusText.display(22),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            count == 1 ? '1 question' : '$count questions',
            style: SusText.body(14, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// A contestant tab on the Replay. Ink when picked, like the Lobby pickers,
/// with the same teal initial as the player's Lobby row.
class _ReplayTab extends StatelessWidget {
  const _ReplayTab({
    required this.player,
    required this.selected,
    required this.onTap,
  });

  final Player player;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: player.name,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.fromLTRB(4, 0, 14, 0),
          decoration: BoxDecoration(
            color: selected ? SusColors.ink : SusColors.cream,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: SusColors.ink, width: 2.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Avatar(initial: player.initial, size: 32),
              const SizedBox(width: 8),
              Text(
                player.name,
                style: SusText.body(
                  15,
                  weight: FontWeight.w700,
                  color: selected ? SusColors.mustard : SusColors.ink,
                ),
              ),
            ],
          ),
        ),
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
                if (result.pulseTrace.length > 1) ...[
                  const SizedBox(height: 4),
                  SizedBox(height: 24, child: PulseTrace(result: result)),
                  const SizedBox(height: 3),
                  _TraceNumbers(result: result),
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
}

/// The two numbers that make a Replay row's pulse line readable: the player's
/// normal (the dashed line) and the highest reading (the top of the red line).
/// Not the first and last readings: the window runs on ~12 s past the
/// answer, so the pulse has often settled again by its end, and a spike in
/// the middle would go unnumbered.
class _TraceNumbers extends StatelessWidget {
  const _TraceNumbers({required this.result});

  final QuestionResult result;

  @override
  Widget build(BuildContext context) {
    final peak = result.pulseTrace.map((p) => p.$2).reduce(math.max).round();
    final base = result.basePulse?.round();
    final style = SusText.body(12, weight: FontWeight.w600);
    return Semantics(
      label: base == null
          ? 'Pulse peaked at $peak BPM.'
          : 'Pulse: your normal $base BPM, peak $peak BPM.',
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (base != null) ...[
                  const SizedBox(width: 16, child: _DashSwatch()),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'normal $base',
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('peak $peak BPM', style: style),
        ],
      ),
    );
  }
}

/// How a result's chart marks the answer.
enum AnswerMark {
  /// Shaded from when the player started talking to the answer's end.
  shaded,

  /// No start was heard: a rule at the Final answer, where the pause was
  /// measured to.
  finalAnswer,

  /// No timing to mark.
  none,
}

AnswerMark answerMarkFor(QuestionResult result) {
  final timing = result.timing;
  if (timing == null) return AnswerMark.none;
  final start = timing.tA0;
  return start != null && timing.tA1 > start
      ? AnswerMark.shaded
      : AnswerMark.finalAnswer;
}

/// A question's pulse over the scored window, with the answer marked and the
/// player's normal dashed (Verdict and Replay).
class PulseTrace extends StatelessWidget {
  const PulseTrace({super.key, required this.result});

  final QuestionResult result;

  @override
  Widget build(BuildContext context) {
    final timing = result.timing;
    final trace = result.pulseTrace;
    final from = timing?.tQ0 ?? trace.first.$1;
    final to = result.traceEndMs ?? trace.last.$1;
    final mark = answerMarkFor(result);
    return PulseSparkline(
      points: trace,
      baseline: result.basePulse,
      fromMs: from,
      nowMs: to,
      minSpanMs: 0,
      endDot: false,
      highlight: mark == AnswerMark.shaded ? (timing!.tA0!, timing.tA1) : null,
      marker: mark == AnswerMark.finalAnswer ? timing!.tA1 : null,
    );
  }
}

class _PulseCard extends StatelessWidget {
  const _PulseCard({required this.result});

  final QuestionResult result;

  @override
  Widget build(BuildContext context) {
    final values = [for (final (_, v) in result.pulseTrace) v];
    final mean = values.reduce((a, b) => a + b) / values.length;
    final peak = values.reduce(math.max);
    final base = result.basePulse;
    final vs = base == null
        ? ''
        : ', ${(mean - base).abs().round()} '
              '${mean >= base ? 'above' : 'below'} your normal of ${base.round()}';
    return Semantics(
      label:
          'Pulse through the question: averaged ${mean.round()} BPM$vs. '
          'Highest ${peak.round()} BPM.',
      excludeSemantics: true,
      child: SusCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pulse through the question',
                    style: SusText.label(13),
                  ),
                ),
                Text(
                  'peak ${peak.round()} BPM',
                  style: SusText.body(13, weight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(height: 56, child: PulseTrace(result: result)),
            const SizedBox(height: 6),
            Row(
              children: [
                ...switch (answerMarkFor(result)) {
                  AnswerMark.shaded => [
                    Container(
                      width: 16,
                      height: 10,
                      decoration: BoxDecoration(
                        color: SusColors.mustard.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Answering',
                      style: SusText.body(12, weight: FontWeight.w600),
                    ),
                    const SizedBox(width: 14),
                  ],
                  AnswerMark.finalAnswer => [
                    Container(
                      width: SparklinePainter.markerWidth,
                      height: 12,
                      color: SusColors.brown,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Final answer',
                      style: SusText.body(12, weight: FontWeight.w600),
                    ),
                    const SizedBox(width: 14),
                  ],
                  AnswerMark.none => const <Widget>[],
                },
                const SizedBox(width: 16, child: _DashSwatch()),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    base == null
                        ? 'Your normal'
                        : 'Your normal (${base.round()})',
                    overflow: TextOverflow.ellipsis,
                    style: SusText.body(12, weight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DashSwatch extends StatelessWidget {
  const _DashSwatch();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < 2; i++) ...[
        Container(width: 5, height: 2, color: SusColors.brown),
        if (i == 0) const SizedBox(width: 3),
      ],
    ],
  );
}
