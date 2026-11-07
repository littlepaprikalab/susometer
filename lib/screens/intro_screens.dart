import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../game/game_controller.dart';
import '../game/scoring.dart';
import '../presage/camera_preview.dart';
import '../theme/expression_stamp.dart';
import '../theme/fit_text.dart';
import '../theme/game_widgets.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';

/// E1 · How to play (mock: Edge-HowToPlay.dc.html). Shown once per app
/// session, before the first turn.
class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  static const _steps = [
    (
      'Prop it up or hold it steady',
      'Face in the oval, light in front of you, not behind.',
    ),
    (
      'Asker: say it out loud',
      'The host says who asks, then writes your question on screen.',
    ),
    (
      'Hot seat: tap, then answer',
      "Tap when the question's done, answer, then smash Final answer.",
    ),
    (
      'Get your verdict',
      'Pulse, blinks and face, compared with your own normal.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    return ScreenFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Semantics(
            header: true,
            child: Text('How to play', style: SusText.display(36)),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _steps.length; i++) ...[
                    SusCard(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Avatar(initial: '${i + 1}'),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_steps[i].$1, style: SusText.label(17)),
                                const SizedBox(height: 2),
                                Text(_steps[i].$2, style: SusText.body(14)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 4),
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
                          'Keep the questions fun, and anyone can skip their turn.',
                          style: SusText.body(14, color: SusColors.cream),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ChunkyButton(
            label: "Got it, let's play",
            height: 60,
            fontSize: 21,
            onPressed: game.dismissHowToPlay,
          ),
        ],
      ),
    );
  }
}

/// 2 · Hot-seat consent (mock: Consent.dc.html). Consent is per player, per
/// game, from the person being measured (SPEC.md §2).
class ConsentScreen extends StatelessWidget {
  const ConsentScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final game = GameScope.of(context);
    final name = game.currentPlayer.name;
    final telemetryOn = services.settings.telemetry;
    final promises = [
      'Video is processed on this phone by the Presage SDK',
      'No video is ever saved or sent',
      'Your pulse numbers (not video) go to Presage for an AI check-in',
      'Scores are wiped when the show ends',
      telemetryOn
          ? 'SDK telemetry is on (anonymous diagnostics, no video or vitals)'
          : 'SDK telemetry is switched off',
    ];
    return ScreenFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RoundIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back to lobby',
                onPressed: onBack,
              ),
              const Spacer(),
              HotSeatPill(
                'Contestant ${game.playerIndex + 1} of ${game.turns.length}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (game.thermalWarning) ...[
                    const _BreatherNote(),
                    const SizedBox(height: 12),
                  ],
                  Text('Pass the phone to', style: SusText.label(17)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      header: true,
                      child: Text(name, style: SusText.display(76)),
                    ),
                  ),
                  Text(
                    'Only $name can say yes. Everyone else, hands off.',
                    style: SusText.body(15, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  SusCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your front camera reads',
                          style: SusText.display(17),
                        ),
                        const SizedBox(height: 12),
                        const _Reading(
                          Icons.monitor_heart_rounded,
                          'Pulse and heart-rate changes',
                        ),
                        const SizedBox(height: 12),
                        const _Reading(
                          Icons.visibility_rounded,
                          'Blinks and facial expressions',
                        ),
                        const SizedBox(height: 12),
                        const _Reading(
                          Icons.mic_none_rounded,
                          'When you start talking',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SusCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('What happens to it', style: SusText.display(17)),
                        const SizedBox(height: 10),
                        for (final p in promises) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 1),
                                child: Icon(
                                  Icons.check_rounded,
                                  color: SusColors.teal,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Text(p, style: SusText.body(15))),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ChunkyButton(
            label: 'I agree, measure me',
            height: 60,
            fontSize: 21,
            onPressed: game.agreeToMeasure,
          ),
          const SizedBox(height: 12),
          ChunkyButton.light(
            label: 'Skip my turn',
            height: 48,
            fontSize: 15,
            onPressed: game.skipTurn,
          ),
        ],
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: SusColors.tomato, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: SusText.body(16, weight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// Thermal note between turns (SPEC.md §9).
class _BreatherNote extends StatelessWidget {
  const _BreatherNote();

  @override
  Widget build(BuildContext context) {
    return SusCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          const Icon(
            Icons.thermostat_rounded,
            color: SusColors.tomato,
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Give the phone a breather. It's running hot, and a minute's rest "
              'keeps the readings steady.',
              style: SusText.body(14, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// 3 · Calibrate baseline (mock: Calibrate.dc.html).
class CalibrateScreen extends StatelessWidget {
  const CalibrateScreen({super.key});

  /// The host bubble is always this many lines tall, so the camera below
  /// never moves when a warm-up (or the lock-in) replaces "Sit still".
  static const bubbleLines = 3;

  /// ...and its text shrinks no smaller than this. Every warm-up fits whole
  /// on the smallest phone at the largest text size (a test checks the
  /// deck).
  static const bubbleMinFontSize = 14.0;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final name = game.currentPlayer.name;
    final elapsed = ((game.nowMs - game.calibStartMs) / 1000).floor().clamp(
      0,
      5999,
    );
    final timer =
        '${elapsed ~/ 60}:${(elapsed % 60).toString().padLeft(2, '0')}';
    final stage = game.calibStage;
    final warmup = game.currentWarmup;
    final chat = stage == CalibStage.chat || stage == CalibStage.done;
    final ready = stage == CalibStage.ready || stage == CalibStage.done;
    final warmupNumber = game.warmupNumber;
    final bubble = switch (stage) {
      CalibStage.starting => 'Warming up the camera…',
      CalibStage.quiet => 'Sit still and look at the camera.',
      _ => warmup?.question ?? game.hostLine,
    };
    return ScreenFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('Warming up $name', style: SusText.display(26)),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: SusColors.ink,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  timer,
                  style: SusText.display(16, color: SusColors.mustard),
                ),
              ),
              const SizedBox(width: 8),
              PauseButton(onPressed: game.pause),
            ],
          ),
          const SizedBox(height: 12),
          _CalibProgress(
            still: game.stillBlocks,
            chat: game.chatBlocks,
            chatDone: game.warmupsDone,
          ),
          const SizedBox(height: 12),
          _OneLine(
            ready
                ? 'Warm-ups done · your normal is locked in'
                : chat
                ? 'Warm-up $warmupNumber of ${game.config.calibMaxWarmups} · from the easy deck'
                : 'Step 1 · Sit still for about 20 seconds',
            style: SusText.label,
          ),
          const SizedBox(height: 6),
          HostBubble(
            text: bubble,
            lines: bubbleLines,
            minFontSize: bubbleMinFontSize,
          ),
          const SizedBox(height: 12),
          const Expanded(child: _CalibCamera()),
          const SizedBox(height: 12),
          // Nothing here moves on by itself (SPEC.md decision 76): each
          // warm-up waits for Next, and the questions for Start.
          if (ready)
            ChunkyButton(
              label: game.currentTurn.results.isEmpty
                  ? 'Start the questions'
                  : 'Back to the questions',
              height: 52,
              fontSize: 17,
              onPressed: game.startQuestions,
            )
          else
            Row(
              children: [
                Expanded(
                  child: ChunkyButton.light(
                    label: "Doesn't apply",
                    height: 52,
                    fontSize: 16,
                    onPressed: warmup == null ? null : game.skipWarmup,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChunkyButton(
                    label: 'Next',
                    icon: Icons.skip_next_rounded,
                    height: 52,
                    fontSize: 17,
                    onPressed: warmup == null ? null : game.nextWarmup,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 6),
          _OneLine(
            ready
                ? 'Tap when ready. The host says who asks first.'
                : chat
                ? 'Answer out loud, then tap Next.'
                : 'Easy warm-up questions come next.',
            textAlign: TextAlign.center,
            style: (size) => SusText.body(size, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// A line of Calibrate copy in a slot one line tall, whatever it says: it
/// shrinks to fit rather than wrap, so the camera below never moves when
/// the step changes (the sit-still is measured).
class _OneLine extends StatelessWidget {
  const _OneLine(this.text, {required this.style, this.textAlign});

  final String text;
  final TextStyle Function(double size) style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.textScalerOf(context).scale(13) * 1.5,
      child: FitText(
        text,
        sizes: const [13, 12, 11],
        overflow: FitOverflow.keepStart,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}

class _CalibProgress extends StatelessWidget {
  const _CalibProgress({
    required this.still,
    required this.chat,
    required this.chatDone,
  });

  final int still;
  final int chat;
  final int chatDone;

  @override
  Widget build(BuildContext context) {
    Widget blocks(int total, int lit) => Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 18,
              decoration: BoxDecoration(
                color: i < lit ? SusColors.teal : SusColors.cream,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: SusColors.ink, width: 2.5),
              ),
            ),
          ),
        ],
      ],
    );
    return Semantics(
      label:
          'Step 1, sit still, ${still >= 4 ? 'done' : '$still of 4'}. '
          'Step 2, chat a bit, $chat of 6',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                blocks(4, still),
                const SizedBox(height: 5),
                Row(
                  children: [
                    if (still >= 4) ...[
                      const Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: SusColors.teal,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        '1 · Sit still',
                        overflow: TextOverflow.ellipsis,
                        style: SusText.label(13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                blocks(6, chat),
                const SizedBox(height: 5),
                Text('2 · Chat a bit', style: SusText.label(13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CalibCamera extends StatelessWidget {
  const _CalibCamera();

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    return ListenableBuilder(
      listenable: game.live,
      builder: (context, _) {
        final s = game.live.sample;
        final code = s?.validation?.code;
        final faceOk = s?.validation != null && !(s!.validation!.faceMissing);
        final lightBad = code == 'TOO_DARK' || code == 'TOO_BRIGHT';
        // A camera problem is stamped on the picture as on Ask and Answer
        // (SPEC.md decision 69), and so is the hint once a clean baseline is
        // slow to come. Only a live problem pauses the reading, so only it
        // takes the pulse card's place with its fix.
        final paused = game.visibleIssue;
        final issue = paused ?? game.calibIssue;
        return CameraWindow(
          guideClear: cameraGuideClear(context),
          overlay: Stack(
            children: [
              // One row that shrinks to fit, never wraps, so the oval
              // below knows how tall it is.
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Row(
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: DotChip(
                          label: faceOk ? 'Face found' : 'Looking for a face',
                          dot: faceOk ? SusColors.teal : SusColors.tomato,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: DotChip(
                          label: lightBad
                              ? (code == 'TOO_DARK'
                                    ? 'Light too low'
                                    : 'Too bright')
                              : 'Light good',
                          dot: lightBad ? SusColors.tomato : SusColors.teal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // The expression or problem stamp, in the same corner and width
              // as on Ask and Answer, just under the chips.
              Positioned(
                top: cameraGuideClear(context).top,
                left: 12,
                right: 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Spacer(
                      flex:
                          100 -
                          (issue == null ? stampRowFlex : issueStampRowFlex),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: issue == null ? stampRowFlex : issueStampRowFlex,
                      child: CameraStampSlot(
                        tag: issue == null ? game.live.expression.tag : null,
                        stressTags: game.config.exprCategories,
                        issue: issue == null ? null : issueStampFor(issue),
                      ),
                    ),
                  ],
                ),
              ),
              // The same live card as on Ask and Answer, in the same place.
              Positioned(
                left: LiveStatCard.inset,
                right: LiveStatCard.inset,
                bottom: LiveStatCard.inset,
                child: paused != null
                    ? PausedFixRow(paused.fix)
                    : LiveStatCard(
                        label: 'Pulse · live',
                        value: s?.pulse == null
                            ? '--'
                            : '${s!.pulse!.round()} BPM',
                        trend: Waveform(samples: game.live.trace),
                        // The SDK's talking signal, inside the card so nothing
                        // sits in the face oval's space. No name: the title
                        // already says who's warming up.
                        trailing: (s?.talking ?? false)
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const LevelBars(
                                    level: 0.8,
                                    count: 5,
                                    maxHeight: 14,
                                    barWidth: 3,
                                  ),
                                  const SizedBox(width: 4),
                                  Text('Talking', style: SusText.label(11)),
                                ],
                              )
                            : null,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A camera problem as a stamp on the camera (SPEC.md decision 69).
/// VoiceOver reads the whole problem and its fix when it lands.
IssueStamp issueStampFor(SignalIssue issue) => IssueStamp(
  text: issue.stamp,
  semanticsLabel: '${issue.title}. ${issue.fix}',
);
