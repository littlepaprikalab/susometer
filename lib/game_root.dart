import 'dart:async';

import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'debug/proof_panel.dart';
import 'game/game_controller.dart';
import 'screens/edge_screens.dart';
import 'screens/intro_screens.dart';
import 'screens/lobby_screen.dart';
import 'screens/question_screens.dart';
import 'screens/result_screens.dart';
import 'share/share_card.dart';

/// Shows the screen for the current [GamePhase], plus the Pause and End the
/// show overlays and the Proof Panel. Also forwards app lifecycle changes.
class GameRoot extends StatefulWidget {
  const GameRoot({super.key});

  @override
  State<GameRoot> createState() => _GameRootState();
}

/// After any phase change, taps are ignored this long: the second tap of a
/// double tap would otherwise land on whatever the new phase put in the same
/// spot ("Tap when done asking" → "Final answer", "Got it" → "I agree").
const phaseTapGuard = Duration(milliseconds: 450);

/// The guard's [IgnorePointer], so tests can wait it out.
const phaseTapGuardKey = ValueKey('phaseTapGuard');

class _GameRootState extends State<GameRoot> with WidgetsBindingObserver {
  bool _confirmEnd = false;
  final GlobalKey _shareKey = GlobalKey();
  GamePhase? _shownPhase;
  bool _freshPhase = false;
  Timer? _freshTimer;

  void _notePhase(GamePhase phase) {
    if (phase == _shownPhase) return;
    final first = _shownPhase == null;
    _shownPhase = phase;
    // The first screen at launch has no earlier tap to absorb.
    if (first) return;
    _freshPhase = true;
    _freshTimer?.cancel();
    _freshTimer = Timer(phaseTapGuard, () {
      if (mounted) setState(() => _freshPhase = false);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _freshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final game = GameScope.of(context);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      game.onAppBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      game.onAppResumed();
    }
  }

  void _askEnd() => setState(() => _confirmEnd = true);
  void _closeEnd() => setState(() => _confirmEnd = false);

  Widget _screen(GameController game) {
    return switch (game.phase) {
      GamePhase.lobby => const LobbyScreen(),
      GamePhase.howToPlay => const HowToPlayScreen(),
      GamePhase.permissions => const PermissionsScreen(),
      GamePhase.consent => ConsentScreen(
        onBack: () {
          final anyPlayed = game.turns.any((t) => t.results.isNotEmpty);
          if (game.playerIndex == 0 && !anyPlayed) {
            game.backToLobby();
          } else {
            _askEnd();
          }
        },
      ),
      GamePhase.calibrate => const CalibrateScreen(),
      GamePhase.ask ||
      GamePhase.answer ||
      GamePhase.settle => const HotSeatScreen(),
      GamePhase.redo => const RedoScreen(),
      GamePhase.callIt => const CallItScreen(),
      GamePhase.countdown => const CountdownScreen(),
      GamePhase.verdict => const VerdictScreen(),
      GamePhase.sdkOffline => const SdkOfflineScreen(),
      GamePhase.leaderboard => LeaderboardScreen(
        onShare: () => shareResults(context, _shareKey),
      ),
      GamePhase.replay => const ReplayScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final game = services.game;
    return ListenableBuilder(
      listenable: Listenable.merge([game, services.settings]),
      builder: (context, _) {
        final showProof = services.settings.proofPanel && game.isMeasuring;
        _notePhase(game.phase);
        return Stack(
          children: [
            if (game.phase == GamePhase.leaderboard && game.awards != null)
              Positioned(
                left: -2000,
                top: 0,
                // Off-screen, only rendered for the share image: hidden from
                // VoiceOver and touches.
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: ShareCard(boundaryKey: _shareKey, game: game),
                  ),
                ),
              ),
            Positioned.fill(
              // Blocks touch and VoiceOver actions for 450 ms; a deliberate
              // tap (VoiceOver: swipe to it, then double-tap) takes longer.
              child: IgnorePointer(
                key: phaseTapGuardKey,
                ignoring: _freshPhase,
                child: KeyedSubtree(
                  // Ask, answer and settle share one screen, so the camera
                  // preview isn't torn down and rebuilt between them.
                  key: ValueKey<Object>(switch (game.phase) {
                    GamePhase.ask ||
                    GamePhase.answer ||
                    GamePhase.settle => 'hotSeat',
                    final phase => phase,
                  }),
                  child: _screen(game),
                ),
              ),
            ),
            if (showProof)
              Positioned.fill(
                child: ProofPanel(
                  game: game,
                  telemetry: services.settings.telemetry,
                ),
              ),
            if (game.paused && !_confirmEnd)
              Positioned.fill(
                child: SheetOverlay(child: PauseSheet(onEndShow: _askEnd)),
              ),
            if (_confirmEnd && game.inGame)
              Positioned.fill(
                child: SheetOverlay(
                  onDismiss: _closeEnd,
                  child: EndShowSheet(onKeepPlaying: _closeEnd),
                ),
              ),
          ],
        );
      },
    );
  }
}
