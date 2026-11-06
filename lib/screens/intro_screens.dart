import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../game/game_controller.dart';
import '../presage/camera_preview.dart';
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
      'The host listens and writes your question on screen.',
    ),
    (
      'Hot seat: just answer',
      'Start talking when ready, then smash Final answer.',
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
      'Processed on this phone by the Presage SDK',
      'No video is ever saved or sent',
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
    final warmupNumber = game.warmups.length.clamp(
      1,
      game.config.calibMaxWarmups,
    );
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
          Text(
            chat
                ? 'Warm-up $warmupNumber of ${game.config.calibMaxWarmups} · from the easy deck'
                : 'Step 1 · Sit still for about 20 seconds',
            style: SusText.label(13),
          ),
          const SizedBox(height: 6),
          HostBubble(text: bubble),
          const SizedBox(height: 12),
          if (game.calibHint != null) ...[
            SignalBannerCard(title: 'Still calibrating', body: game.calibHint!),
            const SizedBox(height: 12),
          ],
          Expanded(child: _CalibCamera(name: name)),
          const SizedBox(height: 12),
          const _LiveBpmCard(),
          const SizedBox(height: 12),
          ChunkyButton.light(
            label: "Doesn't apply? Next one",
            icon: Icons.skip_next_rounded,
            height: 52,
            fontSize: 16,
            onPressed: warmup == null ? null : game.skipWarmup,
          ),
          const SizedBox(height: 6),
          Text(
            'The show starts by itself once your normal is locked in.',
            textAlign: TextAlign.center,
            style: SusText.body(13, weight: FontWeight.w600),
          ),
        ],
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
  const _CalibCamera({required this.name});

  final String name;

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
        return CameraWindow(
          guideClear: const EdgeInsets.only(top: 42, bottom: 42),
          overlay: Stack(
            children: [
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    DotChip(
                      label: faceOk ? 'Face found' : 'Looking for a face',
                      dot: faceOk ? SusColors.teal : SusColors.tomato,
                    ),
                    DotChip(
                      label: lightBad
                          ? (code == 'TOO_DARK'
                                ? 'Light too low'
                                : 'Too bright')
                          : 'Light good',
                      dot: lightBad ? SusColors.tomato : SusColors.teal,
                    ),
                  ],
                ),
              ),
              if (s?.talking ?? false)
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: DotChip(
                    label: '$name is talking',
                    dot: SusColors.teal,
                    leading: const LevelBars(
                      level: 0.8,
                      count: 5,
                      maxHeight: 14,
                      barWidth: 3,
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

class _LiveBpmCard extends StatelessWidget {
  const _LiveBpmCard();

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    return ListenableBuilder(
      listenable: game.live,
      builder: (context, _) {
        final pulse = game.live.sample?.pulse;
        return SusCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pulse == null ? '--' : pulse.round().toString(),
                      style: SusText.display(38, color: SusColors.tomato),
                    ),
                    Text('BPM · live', style: SusText.label(12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: Waveform(samples: game.live.trace),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// E3 · bad-signal banner (mock: Edge-SignalIssue.dc.html).
class SignalBannerCard extends StatelessWidget {
  const SignalBannerCard({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: SusColors.cream,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: SusColors.ink, width: SusShape.borderWidth),
          boxShadow: const [
            BoxShadow(color: SusColors.ink, offset: Offset(0, 5)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: SusColors.tomato,
                shape: BoxShape.circle,
                border: Border.all(color: SusColors.ink, width: 2.5),
              ),
              child: const Icon(
                Icons.wb_incandescent_outlined,
                color: SusColors.cream,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SusText.display(19)),
                  const SizedBox(height: 2),
                  Text(body, style: SusText.body(14, weight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
