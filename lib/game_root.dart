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
/// spot ("Done asking" → "Final answer", "Got it" → "I agree").
const phaseTapGuard = Duration(milliseconds: 450);

/// The guard's [IgnorePointer], so tests can wait it out.
const phaseTapGuardKey = ValueKey('phaseTapGuard');

/// The same guard on the Play again sheet, which comes up under the finger
/// that tapped Play again.
const sheetTapGuardKey = ValueKey('sheetTapGuard');

class _GameRootState extends State<GameRoot> with WidgetsBindingObserver {
  bool _confirmEnd = false;
  final GlobalKey _shareKey = GlobalKey();
  Object? _shownPhase;
  bool _freshPhase = false;
  Timer? _freshTimer;

  /// [phase] is what's shown: a phase, or a step within one that puts new
  /// buttons where the last ones were.
  void _notePhase(Object phase) {
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
    _sheetTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final game = GameScope.of(context);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      game.onAppBackgrounded();
    } else if (state == AppLifecycleState.inactive) {
      game.onAppInactive();
    } else if (state == AppLifecycleState.resumed) {
      game.onAppResumed();
    }
  }

  void _askEnd() => setState(() => _confirmEnd = true);
  void _closeEnd() => setState(() => _confirmEnd = false);

  bool _confirmNew = false;
  bool _freshSheet = false;
  Timer? _sheetTimer;

  /// Leaderboard and Replay "Play again": ask first when there's a game to
  /// lose (SPEC.md decision 82). With nothing played, there's nothing to ask
  /// about.
  void _askNew() {
    final game = GameScope.of(context);
    if (!game.turns.any((t) => t.results.isNotEmpty)) {
      game.playAgain();
      return;
    }
    // The sheet's buttons come up where Play again was: the second tap of a
    // double tap mustn't land on one.
    _sheetTimer?.cancel();
    _sheetTimer = Timer(phaseTapGuard, () {
      if (mounted) setState(() => _freshSheet = false);
    });
    setState(() {
      _confirmNew = true;
      _freshSheet = true;
    });
  }

  void _closeNew() => setState(() => _confirmNew = false);

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
        onPlayAgain: _askNew,
      ),
      GamePhase.replay => ReplayScreen(onPlayAgain: _askNew),
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
        // Solo's Ready to answer swaps in Final answer without a phase
        // change, so the guard follows what's shown. So does the end of a
        // question's wait for the pulse, which puts Done asking (or Ready
        // to answer) where the wait's status was.
        _notePhase((game.shownPhase, game.waitingForPulse));
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
            // BlockSemantics: VoiceOver can't reach the screen behind a
            // sheet either (it could tap Final answer behind Pause).
            if (game.showPauseSheet && !_confirmEnd)
              Positioned.fill(
                child: BlockSemantics(
                  child: SheetOverlay(child: PauseSheet(onEndShow: _askEnd)),
                ),
              ),
            // Only over the scores it would wipe: if the game moves on
            // some other way, the question goes with it.
            if (_confirmNew &&
                (game.phase == GamePhase.leaderboard ||
                    game.phase == GamePhase.replay))
              Positioned.fill(
                child: BlockSemantics(
                  child: IgnorePointer(
                    key: sheetTapGuardKey,
                    ignoring: _freshSheet,
                    child: SheetOverlay(
                      onDismiss: _closeNew,
                      child: NewGameSheet(
                        onKeepScores: _closeNew,
                        onPlayAgain: () {
                          _closeNew();
                          game.playAgain();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            if (_confirmEnd && game.inGame)
              Positioned.fill(
                child: BlockSemantics(
                  child: SheetOverlay(
                    onDismiss: _closeEnd,
                    child: EndShowSheet(onKeepPlaying: _closeEnd),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
