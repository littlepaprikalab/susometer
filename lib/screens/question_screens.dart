import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../game/game_controller.dart';
import '../game/models.dart';
import '../presage/camera_preview.dart';
import '../theme/expression_stamp.dart';
import '../theme/fit_text.dart';
import '../theme/game_widgets.dart';
import '../theme/seam_button.dart';
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

/// The card's fixed height, which keeps the camera the same size and in the
/// same place from "Ask your question!" through "Locking in the reading…".
///
/// The room the host's line used to take above it (SPEC.md decision 85):
/// 160 pt, the 14 pt gap and the 48 pt bubble row; and the room it keeps
/// clear at its bottom for the buttons on the seam (decision 90).
const _cardHeight = 222.0 + SeamButton.cardRoom;

/// Distance from the bottom of the safe area to just above the camera's
/// live Pulse/Blinks cards, so overlays (the Proof Panel) never cover them:
/// screen padding + card inset + card + 8 pt. There's no row under the
/// camera: its buttons are on the seam (decision 90).
const hotSeatOverlayBottom =
    ScreenFrame.defaultBottomPadding +
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
          Expanded(
            child: SeamLayout(
              gap: 14,
              top: SizedBox(
                height: _cardHeight,
                child: waiting
                    ? _PulseWaitCard(game: game)
                    : answering
                    ? _AnswerCard(game: game)
                    : solo
                    ? _SoloQuestionCard(game: game)
                    : _AskerCard(game: game),
              ),
              camera: _MeasuringCamera(game: game),
              // Every button is on the seam, where the players are looking
              // (SPEC.md decision 90): Pause at the left, in the same place
              // in every phase, and what moves the question on at the right.
              leading: PauseButton(onPressed: game.pause),
              button: _seamAction(game, solo),
            ),
          ),
        ],
      ),
    );
  }
}

/// What's at the right of the seam: the button that moves the question on,
/// or what it's waiting for. Solo's question card is its own button
/// (decision 85), so there's nothing there while it's up.
Widget? _seamAction(GameController game, bool solo) {
  if (game.waitingForPulse) {
    return const _SeamStatus(
      title: 'Finding the pulse…',
      detail: 'Sit still and look at the camera',
    );
  }
  switch (game.shownPhase) {
    case GamePhase.settle:
      return _SettleStatus(game: game);
    case GamePhase.answer:
      // Nothing ends by itself (SPEC.md decision 76), so a long silence
      // gets a nudge instead.
      final d = game.detector;
      final waited = d?.hesitationFromMs == null
          ? 0
          : game.nowMs - d!.hesitationFromMs!;
      final stuck = d?.tA0 == null && waited >= noAnswerNudgeMs;
      return SeamButton(
        label: 'Final answer',
        hint: stuck
            ? 'No answer? Tap anyway, or Pause to skip'
            : "Tap here when you're done",
        onPressed: game.finalAnswer,
      );
    default:
      return solo
          ? null
          : SeamButton(
              label: 'Done asking',
              hint: '${game.currentPlayer.name}: tap here, then answer',
              onPressed: game.doneAsking,
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
                child: Align(
                  alignment: Alignment.topLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: DotChip(
                      label: issue == null ? 'Measuring' : 'Reading paused',
                      dot: SusColors.tomato,
                    ),
                  ),
                ),
              ),
              // The expression or problem stamp just under the chip, as on
              // Calibrate: the corner above is where the seam's stamp
              // reaches in (SPEC.md decision 90).
              Positioned(
                top: cameraGuideClear(context).top,
                left: 12,
                right: 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Spacer(flex: 100 - stampFlex),
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
              // A notice (voice off) above the live cards: there's no row
              // under the camera to say it any more (SPEC.md decision 90).
              if (game.notice != null && issue == null)
                Positioned(
                  left: LiveStatCard.inset,
                  right: LiveStatCard.inset,
                  bottom: LiveStatCard.inset + LiveStatCard.height + 6,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: DotChip(
                        label: game.notice!,
                        dot: SusColors.mustard,
                      ),
                    ),
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

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({required this.children, this.tallHeader = false});

  final List<Widget> children;

  /// The first child is an [_AskerHeader], which is a tap target's height
  /// and brings its own room above and below.
  final bool tallHeader;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        tallHeader ? 0 : 12,
        16,
        // Clear for the buttons hung across the bottom edge (decision 90).
        12 + SeamButton.cardRoom,
      ),
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
      // 6 pt above and below level. Under that, room for Pause, which hangs
      // across the card's bottom edge (SPEC.md decision 90).
      // The top row is a tap target tall (Different question) and brings its
      // own room above.
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12 + SeamButton.cardRoom),
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
                      Flexible(
                        child: ExcludeSemantics(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Container(
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
                                style: SusText.label(
                                  12,
                                ).copyWith(letterSpacing: 0.7),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // On the card it changes, its height away from the
                      // drawn button, as Suggest one is on the asker's card
                      // (decisions 84 and 90).
                      _CardPill(
                        label: 'Different question',
                        icon: Icons.shuffle_rounded,
                        onTap: game.differentQuestion,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: ExcludeSemantics(
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
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ExcludeSemantics(
              child: Transform.rotate(
                angle: readyFaceTilt * math.pi / 180,
                child: _ReadyFace(down: _down),
              ),
            ),
          ),
        ],
      ),
    );
    // VoiceOver: the card is one button, read as the question; Different
    // question is its own button inside it.
    return Semantics(
      container: true,
      button: true,
      label: game.questionText,
      hint: "Don't answer yet. Tap here first, then answer.",
      onTap: game.readyToAnswer,
      child: GestureDetector(
        // The Semantics above is the card's button; this only takes touches.
        excludeFromSemantics: true,
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
        final over = game.shownPhase == GamePhase.settle;
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
                  // used to carry (SPEC.md decision 85). Only while the
                  // answer is open: once it's locking in, nothing asks
                  // for one.
                  over
                      ? (placeholder ? '…' : text)
                      : !game.micEnabled
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

/// What the seam's right end says while there's nothing to tap: the wait
/// for the pulse, or the reading locking in. Not a button: a card, without
/// the shadow a button presses onto.
class _SeamStatus extends StatelessWidget {
  const _SeamStatus({required this.title, required this.detail, this.progress});

  final String title;
  final String detail;

  /// 0–1, drawn as a bar under the words; none if null.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    return Semantics(
      liveRegion: true,
      label: '$title $detail',
      excludeSemantics: true,
      child: Container(
        height: SeamButton.height,
        padding: const EdgeInsets.fromLTRB(14, 5, 14, 6),
        decoration: BoxDecoration(
          color: SusColors.cream,
          borderRadius: BorderRadius.circular(SusShape.buttonRadius),
          border: Border.all(color: SusColors.ink, width: SusShape.borderWidth),
        ),
        child: Center(
          widthFactor: 1,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, maxLines: 1, style: SusText.display(15)),
                Text(
                  detail,
                  maxLines: 1,
                  style: SusText.body(11.5, weight: FontWeight.w600),
                ),
                if (progress != null) ...[
                  const SizedBox(height: 3),
                  SizedBox(
                    width: 170,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        color: SusColors.teal,
                        backgroundColor: SusColors.unlit,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Locking in the reading…" while the score waits for its last seconds.
class _SettleStatus extends StatelessWidget {
  const _SettleStatus({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final until = game.settleUntilMs ?? game.nowMs;
    final start = game.detector?.tA1 ?? game.nowMs;
    final total = (until - start).clamp(1, 1 << 30);
    final left = ((until - game.nowMs) / 1000).ceil().clamp(0, 99);
    return _SeamStatus(
      title: 'Locking in the reading…',
      detail: left > 0
          ? 'Stay in frame for $left more second${left == 1 ? '' : 's'}'
          : 'Done',
      progress: ((game.nowMs - start) / total).clamp(0.0, 1.0),
    );
  }
}

/// A small cream button on a card's top row (Different question on the
/// solo card): drawn small, with the row's height to take the tap.
class _CardPill extends StatelessWidget {
  const _CardPill({required this.label, required this.icon, this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: SusColors.cream,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: SusColors.ink, width: 2.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: SusColors.ink),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    maxLines: 1,
                    style: SusText.body(13, weight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
