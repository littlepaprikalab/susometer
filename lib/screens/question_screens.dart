import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../game/game_controller.dart';
import '../game/models.dart';
import '../presage/camera_preview.dart';
import '../theme/expression_stamp.dart';
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

/// After this long on the answer with nothing heard, Final answer's hint
/// suggests tapping anyway or skipping.
const noAnswerNudgeMs = 20000;

/// Fixed heights that keep the camera card the same size and in the same
/// place from "Ask your question!" through "Locking in the reading…".
///
/// The card has the room the host's line used to take above it (SPEC.md
/// decision 85): 160 pt, the 14 pt gap and the 48 pt bubble row.
const _cardHeight = 222.0;
const _actionsHeight = 92.0;

/// Distance from the bottom of the safe area to just above the camera's
/// live Pulse/Blinks cards, so overlays (the Proof Panel) never cover them:
/// screen padding + bottom row + gap + card inset + card + 8 pt.
const hotSeatOverlayBottom =
    ScreenFrame.defaultBottomPadding +
    _actionsHeight +
    12 +
    LiveStatCard.inset +
    LiveStatCard.height +
    8;

/// 4a and 4b in one layout (mocks: Question.dc.html, Question-Solo.dc.html,
/// Answer.dc.html). Ask, Answer and Settle share one frame: only the
/// card's text and the buttons change. The camera card never moves or
/// resizes, and its native preview isn't rebuilt between phases.
///
/// There's no host bubble here (SPEC.md decision 85): the card says what
/// the host says, and has the bubble's room for the question.
class HotSeatScreen extends StatelessWidget {
  const HotSeatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final solo = game.mode == GameMode.solo;
    // Solo keeps the question card up until the player is ready.
    final shown = game.shownPhase;
    final answering = shown == GamePhase.answer || shown == GamePhase.settle;
    final waiting = game.waitingForPulse;
    return ScreenFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(game: game, solo: solo),
          const SizedBox(height: 14),
          SizedBox(
            height: _cardHeight,
            child: waiting
                ? _PulseWaitCard(game: game)
                : answering
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
    return ListenableBuilder(
      listenable: game.live,
      builder: (context, _) {
        final issue = game.visibleIssue;
        // The same overlay on Ask, Answer and Settle, so nothing over the
        // face changes between them. A camera problem (E3) is stamped on
        // the picture, where the player is looking, with its fix in the
        // live cards' row; nothing outside the camera moves.
        final stampFlex = issue == null ? stampRowFlex : issueStampRowFlex;
        return CameraWindow(
          guideClear: cameraGuideClear(context),
          overlay: Stack(
            children: [
              // No name: the header pill already says whose turn it is, and
              // it's their face in the frame. The chip shrinks to fit at
              // large text sizes rather than run under the expression stamp,
              // which hangs from the same row and may run over the oval's
              // edge.
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 100 - stampFlex,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: DotChip(
                            label: issue == null
                                ? 'Measuring'
                                : 'Reading paused',
                            dot: SusColors.tomato,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: stampFlex,
                      child: CameraStampSlot(
                        tag: issue == null ? game.live.expression.tag : null,
                        stressTags: game.config.exprCategories,
                        issue: issue == null ? null : issueStampFor(issue),
                      ),
                    ),
                  ],
                ),
              ),
              // While the reading is paused, the cards' row says how to fix
              // it instead.
              Positioned(
                left: LiveStatCard.inset,
                right: LiveStatCard.inset,
                bottom: LiveStatCard.inset,
                child: issue == null
                    ? _LiveStats(game: game)
                    : PausedFixRow(issue.fix),
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
          child: LiveStatCard(
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
          child: LiveStatCard(
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

    if (game.waitingForPulse) return beside(_PulseWaitStatus(game: game));
    switch (game.shownPhase) {
      case GamePhase.settle:
        return beside(_SettleCard(game: game));
      case GamePhase.answer:
        // Nothing ends by itself (SPEC.md decision 76), so a long silence
        // gets a nudge instead.
        final d = game.detector;
        final waited = d?.hesitationFromMs == null
            ? 0
            : game.nowMs - d!.hesitationFromMs!;
        final stuck = d?.tA0 == null && waited >= noAnswerNudgeMs;
        return beside(
          _FinalAnswerButton(
            onPressed: game.finalAnswer,
            hint: stuck
                ? 'No answer? Tap anyway, or Pause to skip'
                : "Tap when you're done",
          ),
        );
      default:
        final notice = game.notice;
        final hint =
            notice ??
            (solo
                ? 'Tap the question, then answer out loud.'
                : '${game.currentPlayer.name}: tap Done asking, then answer.');
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
                  // Alone here: the way on to the answer is the question
                  // card itself, where the player is reading (SPEC.md
                  // decision 85).
                  ? ChunkyButton.light(
                      label: 'Different question',
                      icon: Icons.shuffle_rounded,
                      height: 48,
                      fontSize: 16,
                      onPressed: game.differentQuestion,
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
  const _TranscriptCard({required this.children, this.tallHeader = false});

  final List<Widget> children;

  /// The first child is an [_AskerHeader], which is a tap target's height
  /// and brings its own room above and below.
  final bool tallHeader;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, tallHeader ? 0 : 12, 16, 12),
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
        final suggestion = game.suggestion;
        if (suggestion != null) {
          return _SuggestionCard(
            game: game,
            suggestion: suggestion,
            heard: game.micEnabled ? text : '',
          );
        }
        return _TranscriptCard(
          tallHeader: true,
          children: [
            _AskerHeader(
              game: game,
              icon: Icons.mic_none_rounded,
              label: game.micEnabled
                  ? 'Asker · listening'
                  : 'Asker · ask out loud',
              action: 'Suggest one',
            ),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: FitText(
                  // Until there are words, the host's line: who asks. It
                  // had a bubble of its own above the card (SPEC.md
                  // decision 85).
                  !game.micEnabled
                      ? '${game.askLine.replaceFirst('!', '')}, '
                            'then tap Done asking.'
                      : (text.isEmpty ? game.askLine : text),
                  sizes: placeholder
                      ? const [26, 22, 18]
                      : const [28, 24, 20, 17],
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

/// The asker card's top row: what the card is doing, the mic level, and the
/// button that deals a question from the deck (SPEC.md decision 81).
///
/// The button lives here, on the card it fills, and not in the bottom row:
/// beside Done asking, a thumb reaching for one could land on the other
/// (decision 84). The row is a tap target tall, so the button is easy to
/// hit though it's drawn small.
class _AskerHeader extends StatelessWidget {
  const _AskerHeader({
    required this.game,
    required this.icon,
    required this.label,
    required this.action,
  });

  final GameController game;
  final IconData icon;
  final String label;

  /// "Suggest one", or "Another one" once a suggestion is up.
  final String action;

  static const height = 44.0;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(13) > 14.5;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 6),
          // The label keeps its words: it shrinks a little before it would
          // lose any, and at large text the mic bars make room for it (the
          // card's own text shows the mic is live).
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(label, maxLines: 1, style: SusText.label(13)),
            ),
          ),
          const SizedBox(width: 8),
          if (game.micEnabled && !largeText) ...[
            LevelBars(level: game.live.micLevel, count: 5),
            const SizedBox(width: 8),
          ],
          Semantics(
            button: true,
            label: action,
            excludeSemantics: true,
            onTap: game.suggestQuestion,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: game.suggestQuestion,
              child: SizedBox(
                height: height,
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: SusColors.cream,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: SusColors.ink, width: 2.5),
                    ),
                    child: Text(
                      action,
                      maxLines: 1,
                      style: SusText.body(13, weight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 4a party, after "Suggest one": a deck question for the asker to read
/// out. It stays up while they ask, since the live transcript would push it
/// off the card mid-sentence; what the mic hears runs along the bottom
/// instead, so the room still sees it's listening.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.game,
    required this.suggestion,
    required this.heard,
  });

  final GameController game;
  final String suggestion;
  final String heard;

  @override
  Widget build(BuildContext context) {
    final line = MediaQuery.textScalerOf(context).scale(13) * 1.5;
    final small = SusText.body(
      13,
      weight: FontWeight.w600,
      color: SusColors.brown,
    );
    return _TranscriptCard(
      tallHeader: true,
      children: [
        _AskerHeader(
          game: game,
          icon: Icons.lightbulb_outline_rounded,
          label: 'Try this one',
          action: 'Another one',
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: FitText(
              suggestion,
              // Down to 12 so the longest card in either deck shows whole
              // on the smallest phone at the largest text (a test deals
              // them all).
              sizes: const [24, 21, 18, 16, 14, 12],
              overflow: FitOverflow.keepStart,
              style: (size) => SusText.display(size),
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: line,
          child: Row(
            children: [
              // Apart from the words, so trimming them to their newest end
              // never trims the label away.
              if (heard.isNotEmpty) Text('Heard: ', style: small),
              Expanded(
                child: FitText(
                  heard.isEmpty ? 'Read it out, or ask your own.' : heard,
                  sizes: const [13],
                  overflow: heard.isEmpty
                      ? FitOverflow.keepStart
                      : FitOverflow.keepEnd,
                  style: (_) => small,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What the button drawn on the solo question card says: the card is the
/// way on to the answer, and talking before the tap shows nothing on screen.
const readyCardLabel = "Don't answer yet · tap here first";

/// The drawn button's face, for tests.
const readyFaceKey = ValueKey('readyFace');

/// The drawn button sits this far off level (degrees), like the camera's
/// stamps: something put on the card to press, not part of its frame.
const readyFaceTilt = -2.0;

/// 4a solo: the host's question card, which is also the "ready to answer"
/// button (SPEC.md decision 85).
///
/// The player is reading the question, so that's where the tap is: the
/// buttons under the camera were half a screen from their eyes, and they
/// answered out loud before finding them. A teal button like the answer
/// buttons is drawn inside the card, so it reads as something to tap, and
/// the whole card takes the tap and presses it.
class _SoloQuestionCard extends StatefulWidget {
  const _SoloQuestionCard({required this.game});

  final GameController game;

  @override
  State<_SoloQuestionCard> createState() => _SoloQuestionCardState();
}

class _SoloQuestionCardState extends State<_SoloQuestionCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final deck = game.deck == DeckKind.mild ? 'MILD' : 'SPICY';
    final card = Container(
      // Room under and beside the button for its tilt: its ends ride about
      // 6 pt above and below level.
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: BoxDecoration(
        color: SusColors.tomato,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SusColors.ink, width: SusShape.borderWidth),
        boxShadow: const [
          BoxShadow(color: SusColors.ink, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
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
                  const SizedBox(height: 8),
                  Expanded(
                    child: FitText(
                      game.questionText,
                      // A size up on the asker card's: the question is
                      // all this card shows, and it has the room.
                      sizes: const [32, 28, 24, 20, 17],
                      overflow: FitOverflow.keepStart,
                      style: (size) =>
                          SusText.display(size, color: SusColors.cream),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Transform.rotate(
              angle: readyFaceTilt * math.pi / 180,
              child: _ReadyFace(down: _down),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: game.questionText,
      hint: "Don't answer yet. Tap here first, then answer.",
      excludeSemantics: true,
      onTap: game.readyToAnswer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: game.readyToAnswer,
        child: card,
      ),
    );
  }
}

/// The button drawn on the solo question card: a [ChunkyButton]'s look
/// (teal, ink border, hard shadow), pressed by a tap anywhere on the card.
/// It's only the picture; the card takes the tap.
class _ReadyFace extends StatelessWidget {
  const _ReadyFace({required this.down});

  final bool down;

  static const _height = 46.0;

  @override
  Widget build(BuildContext context) {
    final shadow = SusShape.shadowOffset.dy;
    return SizedBox(
      height: _height + shadow,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: shadow,
            height: _height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: SusColors.ink,
                borderRadius: BorderRadius.circular(SusShape.buttonRadius),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 60),
            left: 0,
            right: 0,
            top: down ? shadow : 0,
            height: _height,
            child: Container(
              key: readyFaceKey,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: SusColors.teal,
                borderRadius: BorderRadius.circular(SusShape.buttonRadius),
                border: Border.all(
                  color: SusColors.ink,
                  width: SusShape.borderWidth,
                ),
              ),
              alignment: Alignment.center,
              // One line that shrinks to fit, so the button never grows.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.touch_app_rounded,
                      color: SusColors.cream,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      readyCardLabel,
                      maxLines: 1,
                      style: SusText.body(
                        15,
                        weight: FontWeight.w700,
                        color: SusColors.cream,
                      ),
                    ),
                  ],
                ),
              ),
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
                    // By role, like "Asker · listening" in this slot on
                    // Ask; the header pill already names the player.
                    talking ? 'Hot seat · talking' : 'Hot seat · listening',
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
                  // Until there are words, the prompt the host bubble
                  // used to carry (SPEC.md decision 85).
                  !game.micEnabled
                      ? '${game.currentPlayer.name}, answer out loud.'
                      : (text.isEmpty
                            ? '${game.currentPlayer.name}, your answer?'
                            : text),
                  sizes: placeholder
                      ? const [26, 22, 18]
                      : const [28, 24, 20, 17],
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

/// The question waits until the camera has a fresh pulse (SPEC.md
/// decision 79), in the card's slot: why nothing's being asked yet.
class _PulseWaitCard extends StatelessWidget {
  const _PulseWaitCard({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final name = game.currentPlayer.name;
    final asker = game.currentAsker;
    final text = game.pulseWaitIsLong
        ? 'Still no pulse. Face the light and hold still, or Pause to skip.'
        : "The question starts once the camera has $name's pulse.";
    return _TranscriptCard(
      children: [
        Row(
          children: [
            const Icon(Icons.favorite_border_rounded, size: 17),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                // The asker can use the wait: they're named now, not when
                // it ends.
                asker == null
                    ? 'Hang on · no question yet'
                    : 'Hang on · ${asker.name} asks next',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SusText.label(13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: FitText(
              text,
              sizes: const [22, 18, 16],
              overflow: FitOverflow.keepStart,
              style: (size) => SusText.display(size, color: SusColors.brown),
            ),
          ),
        ),
      ],
    );
  }
}

/// The bottom row while the question waits: nothing to tap but Pause.
class _PulseWaitStatus extends StatelessWidget {
  const _PulseWaitStatus({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
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
              child: Text('Finding the pulse…', style: SusText.display(19)),
            ),
          ),
          const SizedBox(height: 2),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Sit still and look at the camera',
                style: SusText.body(13, weight: FontWeight.w600),
              ),
            ),
          ),
        ],
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
