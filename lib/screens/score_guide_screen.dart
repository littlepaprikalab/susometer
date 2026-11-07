import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../game/expression_tag.dart';
import '../game/models.dart';
import '../game/scoring_config.dart';
import '../theme/expression_stamp.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';
import 'result_screens.dart' show verdictColor;

/// How it's scored: the Sus score, the verdict bands and the expression
/// #tags, in plain words. Opened from the lobby's ? button, next to the gear
/// (SPEC.md decision 75).
///
/// Every number comes from the game's [ScoringConfig], so the page can't
/// drift from the scoring.
class ScoreGuideScreen extends StatelessWidget {
  const ScoreGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Through AppScope, not GameScope: the config never changes, so the page
    // needn't rebuild every time the game notifies.
    final c = AppScope.of(context).game.config;
    final quietS = (c.calibQuietMs / 1000).round();
    // "3", or "2–3" while calibration may end before its last warm-up.
    final warmups = c.calibMinWarmups >= c.calibMaxWarmups
        ? '${c.calibMaxWarmups}'
        : '${c.calibMinWarmups}–${c.calibMaxWarmups}';
    final noReadPct = ((1 - c.minCleanFraction) * 100).round();
    final grace = _grace(c.hesitationGraceS);
    final curve = c.scoreExponent < 1
        ? ', curved so a small reaction still shows'
        : (c.scoreExponent > 1
              ? ', curved so it takes a big reaction to score high'
              : '');
    final power = c.scoreExponent == 1 ? '' : '^${_w(c.scoreExponent)}';
    final others = [
      for (final l in ExpressionTagger.labels)
        if (!c.exprCategories.contains(l)) l,
    ];
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            Row(
              children: [
                RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back to lobby',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text("How it's scored", style: SusText.display(30)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'The Sus-o-meter compares how your body reacts to each question '
              'with your own normal. A calm answer scores near 0.',
              style: SusText.body(16, weight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            _Section(
              title: 'First, your normal',
              children: [
                Text(
                  'Before your questions you sit still for about $quietS '
                  'seconds, then chat through $warmups easy warm-ups. That '
                  'sets your usual '
                  'pulse, how often you blink while talking, how much your '
                  'face moves and how quickly you start answering. You are '
                  'only ever compared with you.',
                  style: SusText.body(15),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Section(
              title: 'What counts',
              children: [
                Text(
                  "Four signals from the camera. Each one counts only what's "
                  'bigger than your own normal ups and downs.',
                  style: SusText.body(15),
                ),
                const SizedBox(height: 12),
                _Signal(
                  icon: Icons.monitor_heart_rounded,
                  name: 'Pulse',
                  weight: c.wPulse,
                  text:
                      'Your heart rate jumping, running high or dipping just '
                      'after the question, compared with your warm-ups and '
                      'your other answers.',
                ),
                _Signal(
                  icon: Icons.visibility_rounded,
                  name: 'Blinks',
                  weight: c.wBlink,
                  text:
                      'Blinking a lot more than you usually do, or going '
                      'without a blink for far longer than you normally do.',
                ),
                _Signal(
                  icon: Icons.sentiment_neutral_rounded,
                  name: 'Expressions',
                  weight: c.wExpr,
                  text:
                      '${_list(c.exprCategories, 'or')} going past your '
                      'highest in the warm-ups. ${_list(others, 'and')} '
                      "don't count.",
                ),
                _Signal(
                  icon: Icons.hourglass_bottom_rounded,
                  name: 'Pause',
                  weight: c.wHesitation,
                  text: grace == null
                      ? 'Taking longer than usual to start answering.'
                      : 'Taking longer than usual to start answering. $grace '
                            'free: real questions take more thought than '
                            'warm-ups.',
                  last: true,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Section(
              title: 'The verdict',
              children: [
                Text(
                  'Each signal scores 0 to 1. They are weighted as above, '
                  'added up and turned into a score from 0 to 100$curve.',
                  style: SusText.body(15),
                ),
                const SizedBox(height: 12),
                _Bands(config: c),
                const SizedBox(height: 12),
                Text(
                  'On the verdict screen, pulse is beats a minute above your '
                  'normal, blinks is the change from your usual blink rate, '
                  'and pause is how long you took to start answering.',
                  style: SusText.body(15),
                ),
                const SizedBox(height: 8),
                Text(
                  'For the curious: score = 100 × (${_w(c.wPulse)} pulse + '
                  '${_w(c.wBlink)} blinks + ${_w(c.wExpr)} expressions + '
                  '${_w(c.wHesitation)} pause)$power',
                  style: SusText.body(13, weight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Section(
              title: 'No clean read',
              children: [
                Text(
                  "If the camera loses your face, or can't get a steady "
                  'pulse, for more than $noReadPct% of a question, there is '
                  'no score. You get the reason and Ask it again. It never '
                  'makes up a verdict.',
                  style: SusText.body(15),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _TagSection(stressTags: c.exprCategories, others: others),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: SusColors.ink,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'House rule',
                    style: SusText.display(18, color: SusColors.mustard),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "It reads stress, not truth. Nervous doesn't mean guilty. "
                    'For fun only: not a lie detector, not a medical device.',
                    style: SusText.body(14, color: SusColors.cream),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "The first extra second is", "The first extra 1.5 seconds are", or
  /// null when no pause is free.
  static String? _grace(double s) {
    if (s <= 0) return null;
    if (s == 1) return 'The first extra second is';
    final n = s == s.roundToDouble() ? '${s.round()}' : '$s';
    return 'The first extra $n seconds are';
  }

  /// A weight as written in the formula: 0.45, 0.8.
  static String _w(double v) => v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');

  /// "Surprise, fear, contempt or disgust", capitalized for a sentence.
  static String _list(List<String> words, String conjunction) {
    if (words.isEmpty) return 'None';
    final s = words.length == 1
        ? words.first
        : '${words.take(words.length - 1).join(', ')} $conjunction '
              '${words.last}';
    return s[0].toUpperCase() + s.substring(1);
  }
}

/// A cream card with a heading.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SusCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: SusText.display(19)),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

/// One signal: icon, name, its share of the score and what it means.
class _Signal extends StatelessWidget {
  const _Signal({
    required this.icon,
    required this.name,
    required this.weight,
    required this.text,
    this.last = false,
  });

  final IconData icon;
  final String name;
  final double weight;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final pct = (weight * 100).round();
    return Semantics(
      container: true,
      label: '$name, $pct% of the score. $text',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.only(top: 10, bottom: last ? 0 : 10),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: SusColors.ink, width: 1.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 24, color: SusColors.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(name, style: SusText.label(16))),
                      const SizedBox(width: 8),
                      SusPill(label: '$pct%', fontSize: 13),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(text, style: SusText.body(14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Legit / Hmm… / Sus! with their score ranges, in the verdict board colors.
class _Bands extends StatelessWidget {
  const _Bands({required this.config});

  final ScoringConfig config;

  @override
  Widget build(BuildContext context) {
    final bands = [
      (Verdict.legit, '0–${config.legitBelow - 1}'),
      (Verdict.hmm, '${config.legitBelow}–${config.susFrom - 1}'),
      (Verdict.sus, '${config.susFrom}–100'),
    ];
    return Row(
      children: [
        for (var i = 0; i < bands.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _Band(verdict: bands[i].$1, range: bands[i].$2),
          ),
        ],
      ],
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({required this.verdict, required this.range});

  final Verdict verdict;
  final String range;

  @override
  Widget build(BuildContext context) {
    // Small cream text needs the deeper red (contrast_test.dart).
    final color = verdict == Verdict.sus
        ? SusColors.tomatoDeep
        : verdictColor(verdict);
    return Semantics(
      label: '${verdict.label} ${range.replaceFirst('–', ' to ')}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SusColors.ink, width: 2.5),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                verdict.label,
                maxLines: 1,
                style: SusText.display(20, color: SusColors.cream),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                range,
                maxLines: 1,
                style: SusText.label(14, color: SusColors.cream),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The expression #tags stamped on the camera: which ones move the score,
/// and why a tag isn't a verdict.
class _TagSection extends StatelessWidget {
  const _TagSection({required this.stressTags, required this.others});

  /// The expressions the score counts (ScoringConfig.exprCategories).
  final List<String> stressTags;

  /// The other tags the camera can show.
  final List<String> others;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'The #tags on the camera',
      children: [
        Text(
          "While you're measured, the camera's corner stamps the strongest "
          "expression it sees right now, in Presage's own words.",
          style: SusText.body(15),
        ),
        const SizedBox(height: 12),
        _StampGroup(
          heading: 'Red ink: can move the score',
          labels: stressTags,
          stress: true,
        ),
        const SizedBox(height: 12),
        _StampGroup(
          heading: 'Teal ink: just for show',
          labels: others,
          stress: false,
        ),
        const SizedBox(height: 12),
        Text(
          "A tag is the live reading, not compared with your normal, so a red "
          "one doesn't mean you're scoring Sus. The score only counts those "
          '${_count(stressTags.length)} when they go past your warm-up '
          'high.',
          style: SusText.body(15),
        ),
        const SizedBox(height: 8),
        Text(
          "It's the camera's best guess, so it can misread a face. A tag "
          'changes only once a new expression clearly leads, and it hides '
          'when none does or your face is lost.',
          style: SusText.body(15),
        ),
      ],
    );
  }
}

/// "four", or the digits past ten.
String _count(int n) => n <= 10
    ? const [
        'zero', 'one', 'two', 'three', 'four', 'five', //
        'six', 'seven', 'eight', 'nine', 'ten',
      ][n]
    : '$n';

class _StampGroup extends StatelessWidget {
  const _StampGroup({
    required this.heading,
    required this.labels,
    required this.stress,
  });

  final String heading;
  final List<String> labels;
  final bool stress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: SusText.label(15)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final l in labels) ExpressionStamp(label: l, stress: stress),
          ],
        ),
      ],
    );
  }
}
