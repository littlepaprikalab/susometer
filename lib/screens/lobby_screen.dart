import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../game/game_controller.dart';
import '../game/models.dart';
import '../theme/game_widgets.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';
import 'score_guide_screen.dart';
import 'settings_screen.dart';

/// 1 · Lobby (mock: docs/design/mocks/Main.dc.html).
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  int _logoTaps = 0;
  DateTime _lastLogoTap = DateTime.fromMillisecondsSinceEpoch(0);
  bool _starting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// Adds the typed name. [keepTyping] is the keyboard's Return: the
  /// keyboard stays up for the next name. The + button and Start put it
  /// away, so it doesn't sit over the screen once the names are in.
  void _add(GameController game, {bool keepTyping = false}) {
    // Also for VoiceOver's double-tap on +, which isn't a touch outside.
    if (!keepTyping) _nameFocus.unfocus();
    if (game.players.length >= GameController.maxPlayers) {
      _snack('Eight contestants is the max.');
      return;
    }
    if (game.addPlayer(_nameController.text)) {
      _nameController.clear();
      if (keepTyping) _nameFocus.requestFocus();
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Proof Panel shortcut (SPEC.md §10): long-press the logo or tap it 5 times.
  void _toggleProof() {
    final settings = AppScope.of(context).settings;
    settings.proofPanel = !settings.proofPanel;
    _snack(settings.proofPanel ? 'Proof panel on.' : 'Proof panel off.');
  }

  void _logoTap() {
    final now = DateTime.now();
    if (now.difference(_lastLogoTap) > const Duration(seconds: 2)) {
      _logoTaps = 0;
    }
    _lastLogoTap = now;
    _logoTaps++;
    if (_logoTaps >= 5) {
      _logoTaps = 0;
      _toggleProof();
    }
  }

  Future<void> _openSettings({bool focusKey = false}) async {
    final services = AppScope.of(context);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          focusKeyField: focusKey,
          onWipe: services.game.wipeAll,
        ),
      ),
    );
    await services.apiKey.refresh();
  }

  void _openScoreGuide() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ScoreGuideScreen()));
  }

  Future<void> _start(GameController game) async {
    if (_nameController.text.trim().isNotEmpty) _add(game);
    setState(() => _starting = true);
    final block = await game.startShow();
    if (!mounted) return;
    setState(() => _starting = false);
    switch (block) {
      case StartBlock.needPlayers:
        _snack(
          game.mode == GameMode.party
              ? 'Add at least 2 contestants for a party game.'
              : 'Add a contestant first.',
        );
      case StartBlock.needKey:
        // First run / no key: open Settings with the key field focused.
        await _openSettings(focusKey: true);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    return ListenableBuilder(
      listenable: game,
      builder: (context, _) => ScreenFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Neither opens while the show is starting: the game would
                // start (or Settings open for a missing key) under the page.
                RoundIconButton(
                  icon: Icons.question_mark_rounded,
                  tooltip: "How it's scored",
                  onPressed: _starting ? null : _openScoreGuide,
                ),
                const SizedBox(width: 10),
                RoundIconButton(
                  icon: Icons.settings_rounded,
                  tooltip: 'Settings',
                  onPressed: _starting ? null : _openSettings,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: SingleChildScrollView(
                // iPhone keyboards have no key to put them away.
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      onLongPress: _toggleProof,
                      onTap: _logoTap,
                      child: MarqueeBoard(
                        color: SusColors.tomato,
                        radius: 24,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Semantics(
                            header: true,
                            child: Text(
                              'Sus-o-meter',
                              style: SusText.display(
                                40,
                                color: SusColors.cream,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'The party game that reads your pulse. Not your mind.',
                      textAlign: TextAlign.center,
                      style: SusText.body(16, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 14),
                    Text('Contestants', style: SusText.display(22)),
                    const SizedBox(height: 8),
                    _Choices<GameMode>(
                      values: const [GameMode.party, GameMode.solo],
                      selected: game.mode,
                      label: (m) =>
                          m == GameMode.party ? 'Party' : 'Solo · host asks',
                      pill: true,
                      onSelected: game.setMode,
                    ),
                    const SizedBox(height: 10),
                    for (final p in game.players) ...[
                      _PlayerRow(
                        player: p,
                        onRemove: () => game.removePlayer(p.id),
                      ),
                      const SizedBox(height: 8),
                    ],
                    _AddRow(
                      controller: _nameController,
                      focus: _nameFocus,
                      enabled: game.players.length < GameController.maxPlayers,
                      onSubmitted: () => _add(game, keepTyping: true),
                      onAdd: () => _add(game),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      // How long that makes the whole game, once there are
                      // enough players to say.
                      switch (game.estimatedMinutes) {
                        null => 'Questions per turn',
                        final minutes =>
                          'Questions per turn · about $minutes min in all',
                      },
                      style: SusText.label(14),
                    ),
                    const SizedBox(height: 8),
                    _Choices<int>(
                      values: const [1, 3, 5],
                      selected: game.questionsPerTurn,
                      label: (v) => '$v',
                      display: true,
                      onSelected: game.setQuestionsPerTurn,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      game.mode == GameMode.solo
                          ? 'Question deck'
                          : 'Question deck · for suggestions',
                      style: SusText.label(14),
                    ),
                    const SizedBox(height: 8),
                    _Choices<DeckKind>(
                      values: DeckKind.values,
                      selected: game.deck,
                      label: (d) => d == DeckKind.mild ? 'Mild' : 'Spicy',
                      onSelected: game.setDeck,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.mic_none_rounded, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Everyone's voices are turned into text on this "
                            'phone, never recorded or sent anywhere.',
                            style: SusText.body(13, weight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            ChunkyButton(
              label: _starting ? 'Warming up…' : 'Start the show',
              height: 60,
              fontSize: 22,
              onPressed: _starting ? null : () => _start(game),
            ),
            const SizedBox(height: 12),
            Text(
              'For fun only. Measures stress reactions, not truth.',
              textAlign: TextAlign.center,
              style: SusText.body(13, weight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, required this.onRemove});

  final Player player;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: SusColors.cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SusColors.ink, width: 2.5),
      ),
      child: Row(
        children: [
          Avatar(initial: player.initial),
          const SizedBox(width: 12),
          // Long names shrink to fit rather than lose letters to "…".
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(player.name, maxLines: 1, style: SusText.display(21)),
            ),
          ),
          IconButton(
            tooltip: 'Remove ${player.name}',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, color: SusColors.ink),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ],
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({
    required this.controller,
    required this.focus,
    required this.enabled,
    required this.onSubmitted,
    required this.onAdd,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool enabled;

  /// The keyboard's Return.
  final VoidCallback onSubmitted;

  /// The + button.
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('addContestant'),
            controller: controller,
            focusNode: focus,
            enabled: enabled,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            maxLength: 20,
            onSubmitted: (_) => onSubmitted(),
            // On iPhone a touch elsewhere doesn't close the keyboard unless
            // the field says so.
            onTapOutside: (_) => focus.unfocus(),
            // Typed names use the same face and size as the contestant rows.
            style: SusText.display(21),
            decoration: InputDecoration(
              counterText: '',
              hintText: enabled ? 'Add a contestant' : 'Eight is the max',
              hintStyle: SusText.body(
                16,
                weight: FontWeight.w600,
                color: SusColors.brown,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 15,
              ),
              border: _border(),
              enabledBorder: _border(),
              disabledBorder: _border(),
              focusedBorder: _border(color: SusColors.teal),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: ChunkyButton.light(
            label: 'Add contestant',
            icon: Icons.add_rounded,
            height: 48,
            fontSize: 18,
            showLabel: false,
            onPressed: enabled ? onAdd : null,
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _border({Color color = SusColors.ink}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: 2.5),
      );
}

/// A row of choice tiles (mode, questions per turn, deck). The picked tile is
/// wider, taller and set in larger type than the others, so the choice reads
/// at a glance by size as well as by color.
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.display = false,
    this.pill = false,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  /// Labels in the display face (numbers) instead of bold body text.
  final bool display;

  /// Fully rounded tiles (the Party / Solo switch).
  final bool pill;

  static const _gap = 8.0;
  static const _height = 46.0;
  static const _pickedHeight = 56.0;

  /// The picked tile's width relative to the others.
  static const _pickedGrow = 1.3;

  TextStyle _style(bool on) {
    final color = on ? SusColors.mustard : SusColors.ink;
    if (display) return SusText.display(on ? 24 : 18, color: color);
    return SusText.body(on ? 18 : 15, weight: FontWeight.w700, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth - _gap * (values.length - 1);
        final unit = room / (values.length - 1 + _pickedGrow);
        return Row(
          children: [
            for (var i = 0; i < values.length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              _tile(values[i], unit, duration),
            ],
          ],
        );
      },
    );
  }

  Widget _tile(T value, double unit, Duration duration) {
    final on = value == selected;
    final height = on ? _pickedHeight : _height;
    return Semantics(
      button: true,
      selected: on,
      label: label(value),
      excludeSemantics: true,
      onTap: () => onSelected(value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelected(value),
        // The tap area keeps the picked tile's height, so the smaller tiles
        // are just as easy to hit.
        child: SizedBox(
          height: _pickedHeight,
          child: Center(
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              width: on ? unit * _pickedGrow : unit,
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? SusColors.ink : SusColors.cream,
                borderRadius: BorderRadius.circular(pill ? height / 2 : 14),
                border: Border.all(color: SusColors.ink, width: 2.5),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedDefaultTextStyle(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  style: _style(on),
                  child: Text(label(value), maxLines: 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
