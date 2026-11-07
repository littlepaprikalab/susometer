import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../game/game_controller.dart';
import '../settings/app_settings.dart';
import '../theme/game_widgets.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';
import 'settings_screen.dart';

/// E2 · Camera / mic permission off (mock: Edge-Permissions.dc.html).
class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final p = game.permissions;
    final cameraOk = p?.cameraOk ?? false;
    final rows = [
      (
        'Camera',
        'required',
        'Reads pulse, blinks and expressions',
        cameraOk ? 'On' : 'Off',
        cameraOk,
      ),
      (
        'Microphone',
        'optional',
        'Hears the question and the answer',
        p?.mic == 'granted' ? 'On' : 'Off',
        p?.mic == 'granted',
      ),
      (
        'Speech recognition',
        'optional',
        (p?.onDevice ?? true)
            ? 'Turns speech into text, on this phone'
            : "On-device recognition isn't available for this language",
        p?.speech == 'authorized' && (p?.onDevice ?? false) ? 'On' : 'Off',
        p?.speech == 'authorized' && (p?.onDevice ?? false),
      ),
    ];
    return ScreenFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerLeft,
            child: IconBadge(icon: Icons.videocam_off_rounded),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'The show needs eyes and ears',
                    style: SusText.display(32),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Turn these on in Settings. Video and audio never leave this phone.',
                    style: SusText.body(15),
                  ),
                  const SizedBox(height: 16),
                  SusCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < rows.length; i++)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              border: i < rows.length - 1
                                  ? const Border(
                                      bottom: BorderSide(
                                        color: SusColors.ink,
                                        width: 1.5,
                                      ),
                                    )
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text.rich(
                                        TextSpan(
                                          text: rows[i].$1,
                                          style: SusText.label(16),
                                          children: [
                                            TextSpan(
                                              text: ' · ${rows[i].$2}',
                                              style: SusText.body(
                                                12,
                                                weight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(rows[i].$3, style: SusText.body(13)),
                                    ],
                                  ),
                                ),
                                DotChip(
                                  outlined: true,
                                  fontSize: 13,
                                  label: rows[i].$4,
                                  dot: rows[i].$5
                                      ? SusColors.teal
                                      : SusColors.tomato,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    cameraOk
                        ? 'No mic? You can still play. There are no transcripts, and you tap to move between question and answer.'
                        : "The camera is the one thing the show can't do without.",
                    style: SusText.body(14, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ChunkyButton(
            label: 'Open Settings',
            height: 60,
            fontSize: 21,
            onPressed: game.openAppSettings,
          ),
          const SizedBox(height: 10),
          ChunkyButton.light(
            label: cameraOk ? 'Play without voice' : 'Back to lobby',
            height: 48,
            fontSize: 15,
            onPressed: cameraOk ? game.playWithoutVoice : game.backToLobby,
          ),
        ],
      ),
    );
  }
}

/// E4 · No clean read: redo (mock: Edge-RedoQuestion.dc.html).
class RedoScreen extends StatelessWidget {
  const RedoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final reasons = game.currentResult?.noCleanReadReasons ?? const <String>[];
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
              Flexible(
                child: HotSeatPill(
                  "${game.currentPlayer.name}'s in the hot seat",
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          MarqueeBoard(
            color: const Color(0xFF5A4A3A),
            bulbColorAt: (i) =>
                i % 3 == 0 ? SusColors.bulb : const Color(0xFF8A7A5A),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 8),
              child: Column(
                children: [
                  Text(
                    '? ? ?',
                    style: SusText.display(64, color: SusColors.cream),
                  ),
                  Text(
                    'No clean read',
                    style: SusText.display(28, color: SusColors.cream),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SusCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  game.currentResult?.noCleanReadTitle ??
                      'The meter couldn\'t get a read',
                  style: SusText.display(18),
                ),
                const SizedBox(height: 10),
                for (final r in reasons) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(
                          color: SusColors.tomato,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(r, style: SusText.body(15))),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Container(
                  padding: const EdgeInsets.only(top: 8),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: SusColors.ink, width: 1.5),
                    ),
                  ),
                  child: Text(
                    'Shaky readings never get a score. No fake verdicts.',
                    style: SusText.label(13),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: ChunkyButton.light(
                  label: 'Skip it',
                  fontSize: 15,
                  onPressed: game.skipQuestion,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ChunkyButton(
                  label: 'Ask it again',
                  fontSize: 19,
                  onPressed: game.askAgain,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// E5 · SDK sign-in failed / offline (mock: Edge-SdkOffline.dc.html).
class SdkOfflineScreen extends StatelessWidget {
  const SdkOfflineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final game = GameScope.of(context);
    final error = game.sdkError;
    final code = error?.code ?? 'UNKNOWN';
    final fixes = presageFixes(code);
    return ScreenFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: IconBadge(
              icon: switch (code) {
                'inputUnavailable' => Icons.videocam_off_rounded,
                _
                    when code == 'NO_KEY' ||
                        ApiKeyController.keyErrorCodes.contains(code) =>
                  Icons.key_off_rounded,
                _ => Icons.wifi_off_rounded,
              },
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text("The meter won't warm up", style: SusText.display(32)),
                  const SizedBox(height: 6),
                  Text(
                    'The Presage vitals engine signs in when a game starts. Video is still '
                    'processed on this phone, but it needs a connection to begin.',
                    style: SusText.body(15),
                  ),
                  const SizedBox(height: 16),
                  SusCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Try this', style: SusText.display(17)),
                        const SizedBox(height: 10),
                        for (var i = 0; i < fixes.length; i++) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: SusColors.ink,
                                    width: 2,
                                  ),
                                ),
                                child: Text(
                                  '${i + 1}',
                                  style: SusText.label(12),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(fixes[i], style: SusText.body(15)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: SusColors.ink,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$code · session not started',
                        style: const TextStyle(
                          fontFamily: 'Menlo',
                          fontFamilyFallback: ['Courier'],
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: SusColors.mustard,
                        ),
                      ),
                    ),
                  ),
                  if (error != null && error.message.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      describePresageCode(error.code, error.message),
                      style: SusText.body(13, weight: FontWeight.w600),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: SusColors.teal,
                        minimumSize: const Size(44, 44),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                SettingsScreen(onWipe: game.wipeAll),
                          ),
                        );
                        await services.apiKey.refresh();
                      },
                      child: Text(
                        'Open Presage key settings',
                        style: SusText.label(14, color: SusColors.teal),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ChunkyButton(
            label: 'Try again',
            height: 60,
            fontSize: 21,
            onPressed: game.retrySdk,
          ),
          const SizedBox(height: 10),
          ChunkyButton.light(
            label: 'Back to lobby',
            height: 48,
            fontSize: 15,
            onPressed: game.backToLobby,
          ),
        ],
      ),
    );
  }
}

/// Dim backdrop + bottom sheet, drawn inside the game page (no route), so
/// the game can't get stuck behind a dismissed modal.
class SheetOverlay extends StatelessWidget {
  const SheetOverlay({super.key, required this.child, this.onDismiss});

  final Widget child;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SusColors.ink.withValues(alpha: 0.72),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(onTap: () {}, child: child),
        ),
      ),
    );
  }
}

/// E6 · End the show early (mock: Edge-EndGame.dc.html).
class EndShowSheet extends StatelessWidget {
  const EndShowSheet({super.key, required this.onKeepPlaying});

  final VoidCallback onKeepPlaying;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final (played, notYet) = game.playedSummary();
    return SheetCard(
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        namesRoute: true,
        label: 'End the show?',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('End the show?', style: SusText.display(30)),
            const SizedBox(height: 14),
            Text(
              "We'll crown the winners from the questions played so far. Then "
              'everything is wiped: scores, transcripts, all of it.',
              style: SusText.body(15),
            ),
            const SizedBox(height: 14),
            if (played.isNotEmpty)
              Text(
                'Played: ${played.map((e) => '${e.$1.name} (${e.$2})').join(', ')}',
                style: SusText.body(14, weight: FontWeight.w600),
              ),
            if (notYet.isNotEmpty)
              Text(
                'Not played yet: ${notYet.map((p) => p.name).join(', ')}',
                style: SusText.body(14, weight: FontWeight.w600),
              ),
            const SizedBox(height: 14),
            ChunkyButton(
              label: 'End and see scores',
              color: SusColors.ink,
              textColor: SusColors.mustard,
              height: 56,
              fontSize: 19,
              onPressed: () {
                onKeepPlaying();
                game.endShowEarly();
              },
            ),
            const SizedBox(height: 10),
            ChunkyButton(
              label: 'Keep playing',
              height: 52,
              fontSize: 16,
              onPressed: onKeepPlaying,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pause (from 4a/4b, SPEC.md §4): Resume · Skip question · End the show,
/// plus a quick mute.
class PauseSheet extends StatelessWidget {
  const PauseSheet({super.key, required this.onEndShow});

  final VoidCallback onEndShow;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final game = GameScope.of(context);
    final settings = services.settings;
    final calibrating = game.phase == GamePhase.calibrate;
    // Leaving the app pauses the reveal too (Call it!, the countdown, the
    // verdict, No clean read); there's no question to restart or skip there.
    final inQuestion = game.isMeasuring && !calibrating;
    final why = game.pausedAway
        ? 'You left the app, so the camera stopped. '
        : '';
    final what = calibrating
        ? (game.cameraStopped
              ? 'Calibration starts over when you resume.'
              : 'Calibration picks up where it left off.')
        : inQuestion
        ? 'The question starts over when you resume.'
        : 'The game picks up where it left off.';
    return SheetCard(
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final soundOn = settings.hostVoice || settings.soundEffects;
          return Semantics(
            scopesRoute: true,
            explicitChildNodes: true,
            namesRoute: true,
            label: 'Paused',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Paused', style: SusText.display(30)),
                const SizedBox(height: 6),
                Text('$why$what', style: SusText.body(15)),
                const SizedBox(height: 14),
                ChunkyButton(
                  label: 'Resume',
                  height: 56,
                  fontSize: 19,
                  onPressed: game.resume,
                ),
                const SizedBox(height: 10),
                if (calibrating || inQuestion) ...[
                  ChunkyButton.light(
                    label: calibrating ? 'Skip my turn' : 'Skip question',
                    height: 50,
                    fontSize: 15,
                    onPressed: calibrating ? game.skipTurn : game.skipQuestion,
                  ),
                  const SizedBox(height: 10),
                ],
                ChunkyButton(
                  label: 'End the show',
                  color: SusColors.ink,
                  textColor: SusColors.mustard,
                  height: 50,
                  fontSize: 15,
                  onPressed: onEndShow,
                ),
                const SizedBox(height: 8),
                MergeSemantics(
                  child: Row(
                    children: [
                      Icon(
                        soundOn
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Host voice and sounds',
                          style: SusText.label(15),
                        ),
                      ),
                      Switch(
                        value: soundOn,
                        onChanged: (v) {
                          settings.hostVoice = v;
                          settings.soundEffects = v;
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
