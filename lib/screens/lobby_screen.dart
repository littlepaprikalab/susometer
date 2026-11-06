import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../game/game_controller.dart';
import '../game/models.dart';
import '../theme/game_widgets.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';
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

  void _add(GameController game) {
    if (game.players.length >= GameController.maxPlayers) {
      _snack('Eight contestants is the max.');
      return;
    }
    if (game.addPlayer(_nameController.text)) {
      _nameController.clear();
      _nameFocus.requestFocus();
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
            Align(
              alignment: Alignment.centerRight,
              child: RoundIconButton(
                icon: Icons.settings_rounded,
                tooltip: 'Settings',
                onPressed: _openSettings,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: SingleChildScrollView(
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
                    Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Contestants',
                              style: SusText.display(22),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          flex: 3,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: _ModeToggle(game: game),
                          ),
                        ),
                      ],
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
                      onAdd: () => _add(game),
                    ),
                    const SizedBox(height: 14),
                    Text('Questions per turn', style: SusText.label(14)),
                    const SizedBox(height: 8),
                    _Segmented<int>(
                      values: const [3, 5, 7],
                      selected: game.questionsPerTurn,
                      label: (v) => '$v',
                      display: true,
                      onSelected: game.setQuestionsPerTurn,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      game.mode == GameMode.solo
                          ? 'Question deck'
                          : 'Question deck · for solo mode',
                      style: SusText.label(14),
                    ),
                    const SizedBox(height: 8),
                    _Segmented<DeckKind>(
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

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    Widget option(String label, GameMode mode) {
      final on = game.mode == mode;
      return Semantics(
        button: true,
        selected: on,
        label: label,
        excludeSemantics: true,
        onTap: () => game.setMode(mode),
        child: GestureDetector(
          onTap: () => game.setMode(mode),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            color: on ? SusColors.ink : Colors.transparent,
            child: Text(
              label,
              style: SusText.body(
                14,
                weight: FontWeight.w700,
                color: on ? SusColors.mustard : SusColors.ink,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: SusColors.cream,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SusColors.ink, width: 2.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          option('Party', GameMode.party),
          option('Solo · host asks', GameMode.solo),
        ],
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
          Expanded(
            child: Text(
              player.name,
              overflow: TextOverflow.ellipsis,
              style: SusText.body(17, weight: FontWeight.w700),
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
    required this.onAdd,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool enabled;
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
            onSubmitted: (_) => onAdd(),
            style: SusText.body(16, weight: FontWeight.w600),
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

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.display = false,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;
  final bool display;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              button: true,
              selected: values[i] == selected,
              label: label(values[i]),
              excludeSemantics: true,
              onTap: () => onSelected(values[i]),
              child: GestureDetector(
                onTap: () => onSelected(values[i]),
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: values[i] == selected
                        ? SusColors.ink
                        : SusColors.cream,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: SusColors.ink, width: 2.5),
                  ),
                  child: Text(
                    label(values[i]),
                    style: display
                        ? SusText.display(
                            18,
                            color: values[i] == selected
                                ? SusColors.mustard
                                : SusColors.ink,
                          )
                        : SusText.body(
                            15,
                            weight: FontWeight.w700,
                            color: values[i] == selected
                                ? SusColors.mustard
                                : SusColors.ink,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
