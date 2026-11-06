import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../game/game_controller.dart';
import '../game/models.dart';
import '../presage/camera_preview.dart';
import '../theme/game_widgets.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';
import 'intro_screens.dart';

class _Header extends StatelessWidget {
  const _Header({required this.game, this.solo = false, this.dots = false});

  final GameController game;
  final bool solo;
  final bool dots;

  @override
  Widget build(BuildContext context) {
    final name = game.currentPlayer.name;
    return Row(
      children: [
        Flexible(
          child: HotSeatPill(
            solo ? 'Solo · $name vs. the host' : "$name's in the hot seat",
          ),
        ),
        const SizedBox(width: 8),
        if (dots)
          ProgressDots(
            total: game.questionsPerTurn,
            filled: game.questionIndex + 1,
          )
        else
          Text(
            'Q ${game.questionIndex + 1} / ${game.questionsPerTurn}',
            style: SusText.display(16),
          ),
      ],
    );
  }
}

/// E3 banner when a validation problem lasts more than 1.5 s, else nothing.
class _IssueBanner extends StatelessWidget {
  const _IssueBanner({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: game.live,
      builder: (context, _) {
        final issue = game.visibleIssue;
        if (issue == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SignalBannerCard(title: issue.title, body: issue.fix),
        );
      },
    );
  }
}

class _MeasuringCamera extends StatelessWidget {
  const _MeasuringCamera({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final name = game.currentPlayer.name;
    return ListenableBuilder(
      listenable: game.live,
      builder: (context, _) {
        final pulse = game.live.sample?.pulse;
        final issue = game.visibleIssue;
        return CameraWindow(
          overlay: Stack(
            children: [
              Positioned(
                top: 12,
                left: 12,
                child: DotChip(
                  label: issue == null ? 'Measuring $name' : 'Reading paused',
                  dot: SusColors.tomato,
                ),
              ),
              Positioned(
                bottom: 12,
                right: 12,
                child: DotChip(
                  label: '${pulse == null ? '--' : pulse.round()} BPM',
                  dot: SusColors.tomato,
                  fontSize: 13,
                  leading: const Icon(
                    Icons.monitor_heart_rounded,
                    size: 15,
                    color: SusColors.tomato,
                  ),
                ),
              ),
              if (issue != null)
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: DotChip(
                    label: "Picks up again when it's clear",
                    dot: SusColors.bulb,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 4a · Host: ask your question (party; mock: Question.dc.html).
class AskScreen extends StatelessWidget {
  const AskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final name = game.currentPlayer.name;
    return ScreenFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(game: game, dots: true),
          const SizedBox(height: 14),
          const HostBubble(text: 'Ask your question!'),
          const SizedBox(height: 14),
          _IssueBanner(game: game),
          _AskerCard(game: game),
          const SizedBox(height: 14),
          Expanded(child: _MeasuringCamera(game: game)),
          const SizedBox(height: 12),
          Text(
            "$name: just start answering when you're ready.",
            textAlign: TextAlign.center,
            style: SusText.body(15, weight: FontWeight.w700),
          ),
          if (game.notice != null) ...[
            const SizedBox(height: 6),
            Text(
              game.notice!,
              textAlign: TextAlign.center,
              style: SusText.body(13, weight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              PauseButton(onPressed: game.pause),
              const SizedBox(width: 10),
              Expanded(
                child: game.micEnabled
                    ? DashedButton(
                        label: game.turnConfig.autoQuestionEnd
                            ? 'Too loud? Tap when done asking'
                            : 'Tap when done asking',
                        onPressed: game.doneAsking,
                      )
                    : ChunkyButton(
                        label: 'Done asking',
                        height: 48,
                        fontSize: 16,
                        onPressed: game.doneAsking,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AskerCard extends StatelessWidget {
  const _AskerCard({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: game.live,
      builder: (context, _) {
        final text = game.live.askerText;
        return Container(
          constraints: const BoxConstraints(minHeight: 150),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: SusColors.cream,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: SusColors.ink,
              width: SusShape.borderWidth,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.mic_none_rounded, size: 17),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      game.micEnabled
                          ? 'Asker · listening'
                          : 'Asker · ask out loud',
                      style: SusText.label(13),
                    ),
                  ),
                  if (game.micEnabled) LevelBars(level: game.live.micLevel),
                ],
              ),
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                child: Text(
                  !game.micEnabled
                      ? 'Ask your question, then tap Done asking.'
                      : (text.isEmpty ? 'Listening for the question…' : text),
                  style: SusText.display(
                    text.isEmpty || !game.micEnabled ? 22 : 28,
                    color: text.isEmpty || !game.micEnabled
                        ? SusColors.brown
                        : SusColors.ink,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 4a · Solo mode: the host asks (mock: Question-Solo.dc.html).
class SoloAskScreen extends StatelessWidget {
  const SoloAskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final deck = game.deck == DeckKind.mild ? 'MILD' : 'SPICY';
    return ScreenFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(game: game, solo: true),
          const SizedBox(height: 14),
          HostBubble(text: "Here's one for you, ${game.currentPlayer.name}…"),
          const SizedBox(height: 14),
          _IssueBanner(game: game),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SusColors.tomato,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: SusColors.ink,
                width: SusShape.borderWidth,
              ),
              boxShadow: const [
                BoxShadow(color: SusColors.ink, offset: Offset(0, 6)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: SusColors.cream,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'FROM THE $deck DECK',
                        style: SusText.label(12).copyWith(letterSpacing: 0.7),
                      ),
                    ),
                    const Spacer(),
                    ListenableBuilder(
                      listenable: game.live,
                      builder: (context, _) => LevelBars(
                        level: game.live.micLevel,
                        color: SusColors.cream,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  game.questionText,
                  style: SusText.display(28, color: SusColors.cream),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(child: _MeasuringCamera(game: game)),
          const SizedBox(height: 12),
          Text(
            "Answer out loud when you're ready.",
            textAlign: TextAlign.center,
            style: SusText.body(15, weight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              PauseButton(onPressed: game.pause),
              const SizedBox(width: 10),
              Expanded(
                child: ChunkyButton.light(
                  label: 'Different question',
                  icon: Icons.shuffle_rounded,
                  height: 48,
                  fontSize: 15,
                  onPressed: game.differentQuestion,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 4b · {name} answers · Final answer (mock: Answer.dc.html), including the
/// Settle phase that holds until the measurement window closes.
class AnswerScreen extends StatelessWidget {
  const AnswerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final name = game.currentPlayer.name;
    final solo = game.mode == GameMode.solo;
    final settling = game.phase == GamePhase.settle;
    return ScreenFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(game: game, solo: solo),
          const SizedBox(height: 14),
          _PinnedQuestion(game: game),
          const SizedBox(height: 14),
          _IssueBanner(game: game),
          HostBubble(text: '$name, your answer?'),
          const SizedBox(height: 14),
          _AnswerCard(game: game),
          const SizedBox(height: 14),
          SizedBox(
            height: 128,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 104,
                  child: CameraWindow(
                    overlay: const Positioned(
                      top: 7,
                      left: 7,
                      child: DotChip(
                        label: 'LIVE',
                        dot: SusColors.tomato,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _SignalCards(game: game)),
              ],
            ),
          ),
          const Spacer(),
          if (settling)
            _SettleCard(game: game)
          else ...[
            _FinalAnswerButton(onPressed: game.finalAnswer),
            const SizedBox(height: 8),
            Text(
              game.micEnabled && game.turnConfig.autoAnswerEnd
                  ? 'Forgot to tap? It ends itself after 4s of silence.'
                  : 'Tap Final answer when you\'re done.',
              textAlign: TextAlign.center,
              style: SusText.body(13, weight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

class _PinnedQuestion extends StatelessWidget {
  const _PinnedQuestion({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final solo = game.mode == GameMode.solo;
    return ListenableBuilder(
      listenable: game.live,
      builder: (context, _) {
        final q = solo ? game.questionText : game.live.askerText;
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SusColors.ink, width: 2.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                solo ? 'The host asked' : 'The asker asked',
                style: SusText.label(12),
              ),
              const SizedBox(height: 2),
              Text(
                q.isEmpty ? '(asked out loud)' : '“$q”',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: SusText.body(16, weight: FontWeight.w700),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final name = game.currentPlayer.name;
    return ListenableBuilder(
      listenable: game.live,
      builder: (context, _) {
        final text = game.live.answerText;
        final talking = game.live.sample?.talking ?? false;
        final hes = game.live.hesitationS;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: SusColors.cream,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: SusColors.ink,
              width: SusShape.borderWidth,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.mic_none_rounded, size: 17),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      talking ? '$name · talking' : '$name · listening',
                      style: SusText.label(13),
                    ),
                  ),
                  LevelBars(
                    level: talking
                        ? (game.micEnabled
                              ? game.live.micLevel.clamp(0.4, 1.0)
                              : 0.8)
                        : 0.05,
                    color: SusColors.tomato,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                child: Text(
                  !game.micEnabled
                      ? 'Answer out loud.'
                      : (text.isEmpty ? '…' : text),
                  style: SusText.display(
                    text.isEmpty ? 22 : 26,
                    color: text.isEmpty ? SusColors.brown : SusColors.ink,
                  ),
                ),
              ),
              if (hes != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: SusColors.ink,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Took ${hes.toStringAsFixed(1)}s to start answering',
                    style: SusText.body(
                      13,
                      weight: FontWeight.w700,
                      color: SusColors.mustard,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SignalCards extends StatelessWidget {
  const _SignalCards({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final base = game.currentTurn.baseline;
    return ListenableBuilder(
      listenable: game.live,
      builder: (context, _) {
        final pulse = game.live.questionMeanPulse ?? game.live.sample?.pulse;
        final blinks = game.live.questionBlinkRate;
        final pulseDelta = pulse == null || base == null
            ? null
            : pulse - base.pulse;
        final blinkDelta = blinks == null || base == null
            ? null
            : blinks - base.blinkRatePerMin;
        return Column(
          children: [
            Expanded(
              child: _SignalCard(
                label: 'Pulse',
                value: pulse == null ? '--' : '${pulse.round()} BPM',
                delta: pulseDelta,
              ),
            ),
            const SizedBox(height: 7),
            Expanded(
              child: _SignalCard(
                label: 'Blinks',
                value: blinks == null ? '--' : '${blinks.round()} / min',
                delta: blinkDelta,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.label, required this.value, this.delta});

  final String label;
  final String value;
  final double? delta;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: SusColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SusColors.ink, width: 2.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: SusText.body(12, weight: FontWeight.w600)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: SusText.body(17, weight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          if (d != null && d.round() != 0)
            Row(
              children: [
                Icon(
                  d > 0
                      ? Icons.arrow_drop_up_rounded
                      : Icons.arrow_drop_down_rounded,
                  color: d > 0 ? SusColors.tomato : SusColors.teal,
                  size: 24,
                ),
                Text(
                  '${d.abs().round()}',
                  style: SusText.body(15, weight: FontWeight.w700),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FinalAnswerButton extends StatelessWidget {
  const _FinalAnswerButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Final answer',
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: 108,
          decoration: BoxDecoration(
            color: SusColors.teal,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: SusColors.ink,
              width: SusShape.borderWidth,
            ),
            boxShadow: const [
              BoxShadow(color: SusColors.ink, offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Final answer',
                style: SusText.display(32, color: SusColors.cream),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap anywhere here',
                style: SusText.body(
                  14,
                  weight: FontWeight.w600,
                  color: SusColors.cream,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettleCard extends StatelessWidget {
  const _SettleCard({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final until = game.settleUntilMs ?? game.nowMs;
    final start = game.detector?.tA1 ?? game.nowMs;
    final total = (until - start).clamp(1, 1 << 30);
    final progress = ((game.nowMs - start) / total).clamp(0.0, 1.0);
    final left = ((until - game.nowMs) / 1000).ceil().clamp(0, 99);
    return Container(
      constraints: const BoxConstraints(minHeight: 108),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: SusColors.cream,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SusColors.ink, width: SusShape.borderWidth),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Locking in the reading…', style: SusText.display(22)),
          const SizedBox(height: 4),
          Text(
            left > 0
                ? 'Stay in frame for $left more second${left == 1 ? '' : 's'}'
                : 'Done',
            style: SusText.body(14, weight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              color: SusColors.teal,
              backgroundColor: SusColors.unlit,
            ),
          ),
        ],
      ),
    );
  }
}
