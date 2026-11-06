import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../game/game_controller.dart';
import '../game/models.dart';
import '../presage/camera_preview.dart';
import '../theme/fit_text.dart';
import '../theme/game_widgets.dart';
import '../theme/sparkline.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';
import 'intro_screens.dart';

class _Header extends StatelessWidget {
  const _Header({required this.game, this.solo = false});

  final GameController game;
  final bool solo;

  @override
  Widget build(BuildContext context) {
    final name = game.currentPlayer.name;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: HotSeatPill(
            solo ? 'Solo · $name vs. the host' : "$name's in the hot seat",
          ),
        ),
        const SizedBox(width: 8),
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

/// Fixed heights that keep the camera card the same size and in the same
/// place from "Ask your question!" through "Locking in the reading…".
const _cardHeight = 160.0;
const _actionsHeight = 92.0;
const _liveCardHeight = 48.0;
const _liveCardInset = 10.0;

/// Distance from the bottom of the safe area to just above the camera's
/// live Pulse/Blinks cards, so overlays (the Proof Panel) never cover them:
/// screen padding + bottom row + gap + card inset + card + 8 pt.
const hotSeatOverlayBottom =
    ScreenFrame.defaultBottomPadding +
    _actionsHeight +
    12 +
    _liveCardInset +
    _liveCardHeight +
    8;

/// 4a and 4b in one layout (mocks: Question.dc.html, Question-Solo.dc.html,
/// Answer.dc.html). Ask, Answer and Settle share one frame: only the host
/// line, the card's text and the buttons change. The camera card never
/// moves or resizes, and its native preview isn't rebuilt between phases.
class HotSeatScreen extends StatelessWidget {
  const HotSeatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final name = game.currentPlayer.name;
    final solo = game.mode == GameMode.solo;
    final answering =
        game.phase == GamePhase.answer || game.phase == GamePhase.settle;
    final host = answering
        ? '$name, your answer?'
        : solo
        ? "Here's one for you, $name…"
        : 'Ask your question!';
    return ScreenFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(game: game, solo: solo),
          const SizedBox(height: 14),
          HostBubble(text: host, singleLine: true),
          const SizedBox(height: 14),
          // The E3 banner slides in, so the camera eases down instead of
          // jumping.
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _IssueBanner(game: game),
          ),
          SizedBox(
            height: _cardHeight,
            child: answering
                ? _AnswerCard(game: game)
                : solo
                ? _SoloQuestionCard(game: game)
                : _AskerCard(game: game),
          ),
          const SizedBox(height: 14),
          Expanded(child: _MeasuringCamera(game: game)),
          const SizedBox(height: 12),
          SizedBox(
            height: _actionsHeight,
            child: _Actions(game: game, solo: solo),
          ),
        ],
      ),
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
        final issue = game.visibleIssue;
        // The same overlay on Ask, Answer and Settle, so nothing over the
        // face changes between them.
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
                left: _liveCardInset,
                right: _liveCardInset,
                bottom: _liveCardInset,
                child: _LiveStats(game: game),
              ),
              // On a short camera (small phone plus the E3 banner) this
              // chip would cover "Reading paused"; the banner says it too.
              if (issue != null)
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, c) => c.maxHeight < 200
                        ? const SizedBox.shrink()
                        : const Stack(
                            children: [
                              Positioned(
                                bottom: 68,
                                left: 12,
                                child: DotChip(
                                  label: "Picks up again when it's clear",
                                  dot: SusColors.bulb,
                                  fontSize: 12,
                                ),
                              ),
                            ],
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

/// Live pulse (with its trend) and blinks against the baseline, over the
/// bottom of the camera.
class _LiveStats extends StatelessWidget {
  const _LiveStats({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final base = game.currentTurn.baseline;
    final readings = game.live.questionPulse;
    // The latest confident reading, so the number matches the line's end.
    final pulse = readings.isNotEmpty
        ? readings.last.bpm
        : game.live.sample?.pulse;
    final blinks = game.live.questionBlinkRate;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _StatChip(
            label: 'Pulse',
            value: pulse == null ? '--' : '${pulse.round()} BPM',
            delta: pulse == null || base == null ? null : pulse - base.pulse,
            trend: PulseSparkline(
              points: [for (final p in readings) (p.tMs, p.bpm)],
              baseline: base?.pulse,
              fromMs: game.detector?.tQ0 ?? game.questionStartMs,
              nowMs: game.nowMs,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _StatChip(
            label: 'Blinks',
            value: blinks == null ? '--' : '${blinks.round()} / min',
            delta: blinks == null || base == null
                ? null
                : blinks - base.blinkRatePerMin,
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    this.delta,
    this.trend,
  });

  final String label;
  final String value;
  final double? delta;

  /// Optional small chart between the number and the arrow.
  final Widget? trend;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    final text = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: SusText.body(11, weight: FontWeight.w600),
            ),
          ),
        ),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: SusText.body(16, weight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
    return Container(
      height: _liveCardHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: SusColors.cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SusColors.ink, width: 2.5),
      ),
      child: Row(
        children: [
          if (trend == null)
            Expanded(child: text)
          else ...[
            // The number and the trend split the space; a long number
            // shrinks rather than squeezing the trend out.
            Flexible(child: text),
            const SizedBox(width: 8),
            Expanded(child: SizedBox(height: 30, child: trend)),
          ],
          if (d != null && d.round() != 0) ...[
            Icon(
              d > 0
                  ? Icons.arrow_drop_up_rounded
                  : Icons.arrow_drop_down_rounded,
              color: d > 0 ? SusColors.tomato : SusColors.teal,
              size: 22,
            ),
            Text(
              '${d.abs().round()}',
              style: SusText.body(14, weight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}

/// The bottom row. Pause stays in the same spot in every phase.
class _Actions extends StatelessWidget {
  const _Actions({required this.game, required this.solo});

  final GameController game;
  final bool solo;

  @override
  Widget build(BuildContext context) {
    final pause = PauseButton(onPressed: game.pause);
    Widget beside(Widget child) => Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        pause,
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    );

    switch (game.phase) {
      case GamePhase.settle:
        return beside(_SettleCard(game: game));
      case GamePhase.answer:
        return beside(
          _FinalAnswerButton(
            onPressed: game.finalAnswer,
            hint: game.micEnabled && game.turnConfig.autoAnswerEnd
                ? 'Or it ends itself after 4s of silence'
                : "Tap when you're done",
          ),
        );
      default:
        final notice = game.notice;
        final hint =
            notice ??
            (solo
                ? "Answer out loud when you're ready."
                : "${game.currentPlayer.name}: just start answering when you're ready.");
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FitText(
                  hint,
                  textAlign: TextAlign.center,
                  sizes: notice == null
                      ? const [15, 13, 12, 11]
                      : const [13, 12, 11],
                  overflow: FitOverflow.keepStart,
                  style: (size) => SusText.body(size, weight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 8),
            beside(
              solo
                  ? ChunkyButton.light(
                      label: 'Different question',
                      icon: Icons.shuffle_rounded,
                      height: 48,
                      fontSize: 15,
                      onPressed: game.differentQuestion,
                    )
                  : game.micEnabled
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
        );
    }
  }
}

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: SusColors.cream,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SusColors.ink, width: SusShape.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// 4a party: the asker's words, live.
class _AskerCard extends StatelessWidget {
  const _AskerCard({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: game.live,
      builder: (context, _) {
        final text = game.live.askerText;
        final placeholder = text.isEmpty || !game.micEnabled;
        return _TranscriptCard(
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
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: FitText(
                  !game.micEnabled
                      ? 'Ask your question, then tap Done asking.'
                      : (text.isEmpty ? 'Listening for the question…' : text),
                  sizes: placeholder ? const [22, 18] : const [28, 24, 20, 17],
                  overflow: placeholder
                      ? FitOverflow.keepStart
                      : FitOverflow.keepEnd,
                  style: (size) => SusText.display(
                    size,
                    color: placeholder ? SusColors.brown : SusColors.ink,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 4a solo: the host's question card.
class _SoloQuestionCard extends StatelessWidget {
  const _SoloQuestionCard({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final deck = game.deck == DeckKind.mild ? 'MILD' : 'SPICY';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SusColors.tomato,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SusColors.ink, width: SusShape.borderWidth),
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
          Expanded(
            child: FitText(
              game.questionText,
              overflow: FitOverflow.keepStart,
              style: (size) => SusText.display(size, color: SusColors.cream),
            ),
          ),
        ],
      ),
    );
  }
}

/// 4b: the question pinned, then the answer, live.
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final name = game.currentPlayer.name;
    final solo = game.mode == GameMode.solo;
    return ListenableBuilder(
      listenable: game.live,
      builder: (context, _) {
        final q = solo ? game.questionText : game.live.askerText;
        final text = game.live.answerText;
        final talking = game.live.sample?.talking ?? false;
        final hes = game.live.hesitationS;
        final placeholder = text.isEmpty || !game.micEnabled;
        return _TranscriptCard(
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
            const SizedBox(height: 4),
            Text(
              q.isEmpty ? 'Q: (asked out loud)' : 'Q: “$q”',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SusText.body(
                14,
                weight: FontWeight.w600,
                color: SusColors.brown,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: FitText(
                  !game.micEnabled
                      ? 'Answer out loud.'
                      : (text.isEmpty ? '…' : text),
                  sizes: placeholder ? const [22, 18] : const [26, 22, 18],
                  overflow: placeholder
                      ? FitOverflow.keepStart
                      : FitOverflow.keepEnd,
                  style: (size) => SusText.display(
                    size,
                    color: placeholder ? SusColors.brown : SusColors.ink,
                  ),
                ),
              ),
            ),
            if (hes != null) ...[
              const SizedBox(height: 6),
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
        );
      },
    );
  }
}

class _FinalAnswerButton extends StatelessWidget {
  const _FinalAnswerButton({required this.onPressed, required this.hint});

  final VoidCallback onPressed;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Final answer',
      hint: hint,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: _actionsHeight - 6,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
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
              Flexible(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Final answer',
                    style: SusText.display(30, color: SusColors.cream),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    hint,
                    maxLines: 1,
                    style: SusText.body(
                      13,
                      weight: FontWeight.w600,
                      color: SusColors.cream,
                    ),
                  ),
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
      height: _actionsHeight - 6,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: SusColors.cream,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SusColors.ink, width: SusShape.borderWidth),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Locking in the reading…',
                style: SusText.display(19),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                left > 0
                    ? 'Stay in frame for $left more second${left == 1 ? '' : 's'}'
                    : 'Done',
                style: SusText.body(13, weight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: SusColors.teal,
              backgroundColor: SusColors.unlit,
            ),
          ),
        ],
      ),
    );
  }
}
