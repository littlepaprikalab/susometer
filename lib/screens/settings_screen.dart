import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../debug/bridge_spike_screen.dart';
import '../settings/app_settings.dart';
import '../theme/game_widgets.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';

/// 8 · Settings · Presage API key (mock: docs/design/mocks/Settings.dc.html).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.focusKeyField = false, this.onWipe});

  /// First run / no key: open with the key field focused.
  final bool focusKeyField;

  /// Clears all in-memory game data.
  final Future<void> Function()? onWipe;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          // iPhone keyboards have no key to put them away.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            Row(
              children: [
                RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back to lobby',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 12),
                Semantics(
                  header: true,
                  child: Text('Settings', style: SusText.display(32)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ApiKeyCard(autofocus: focusKeyField),
            const SizedBox(height: 14),
            _TogglesCard(settings: services.settings),
            const SizedBox(height: 14),
            ChunkyButton.light(
              label: 'Wipe all game data now',
              icon: Icons.delete_outline_rounded,
              height: 50,
              fontSize: 15,
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await onWipe?.call();
                messenger.showSnackBar(
                  const SnackBar(content: Text('All game data wiped.')),
                );
              },
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: SusColors.ink,
                  minimumSize: const Size(44, 44),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BridgeSpikeScreen(),
                  ),
                ),
                child: Text(
                  'Signal check: camera, pulse and mic together',
                  style: SusText.label(13),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Sus-o-meter v0.1 · For fun only. Not a medical device. Not a lie detector.',
              textAlign: TextAlign.center,
              style: SusText.body(12, weight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Presage API key card: password-style field with Show, Paste, Remove and
/// Test connection, plus a status chip.
class ApiKeyCard extends StatefulWidget {
  const ApiKeyCard({super.key, this.autofocus = false});

  final bool autofocus;

  @override
  State<ApiKeyCard> createState() => _ApiKeyCardState();
}

class _ApiKeyCardState extends State<ApiKeyCard> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _show = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
  }

  /// Saves a newly typed key (if any), then tests the connection.
  Future<void> _saveAndTest(ApiKeyController keys, bool telemetry) async {
    setState(() => _busy = true);
    if (_controller.text.trim().isNotEmpty) {
      final ok = await keys.save(_controller.text);
      if (!mounted) return;
      if (!ok) {
        setState(() => _busy = false);
        return;
      }
      // The typed key is gone from Dart once it's in the Keychain.
      _controller.clear();
      _show = false;
      _focus.unfocus();
    }
    await keys.test(telemetry: telemetry);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _confirmRemove(ApiKeyController keys) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SusColors.cream,
        title: Text('Remove the key?', style: SusText.display(22)),
        content: Text(
          'The key is deleted from this iPhone. You can paste it again later.',
          style: SusText.body(15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Keep it', style: SusText.label(15)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Remove', style: SusText.label(15)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await keys.remove();
      _controller.clear();
    }
  }

  String _helper(ApiKeyController keys) {
    final last = keys.lastTest;
    return switch (keys.state) {
      ApiKeyState.connected =>
        last?.elapsedMs == null
            ? 'Checked just now.'
            : 'Signed in to Presage in ${(last!.elapsedMs! / 1000).toStringAsFixed(1)} s.',
      ApiKeyState.none => "The show can't start without a key.",
      ApiKeyState.rejected =>
        'Presage said ${last?.code ?? 'no'}. Check for typos or make a new key.',
      ApiKeyState.testing => 'Signing in to Presage…',
      ApiKeyState.saved when last != null && !last.ok =>
        'Error code: ${last.code}. ${describePresageCode(last.code, last.message)}',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final keys = services.apiKey;
    return ListenableBuilder(
      listenable: keys,
      builder: (context, _) {
        final typed = _controller.text.trim().isNotEmpty;
        final testing = keys.state == ApiKeyState.testing || _busy;
        final helper = _helper(keys);
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: SusColors.cream,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: SusColors.ink,
              width: SusShape.borderWidth,
            ),
            boxShadow: const [
              BoxShadow(color: SusColors.ink, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Presage API key', style: SusText.display(17)),
                  ),
                  KeyStatusChip(state: keys.state),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('apiKeyField'),
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: widget.autofocus,
                      obscureText: !_show,
                      autocorrect: false,
                      enableSuggestions: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.done,
                      // On iPhone a touch elsewhere doesn't close the
                      // keyboard unless the field says so.
                      onTapOutside: (_) => _focus.unfocus(),
                      onSubmitted: typed
                          ? (_) =>
                                _saveAndTest(keys, services.settings.telemetry)
                          : null,
                      style: const TextStyle(
                        fontFamily: 'Menlo',
                        fontFamilyFallback: ['Courier'],
                        fontSize: 16,
                        color: SusColors.ink,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: keys.hint != null
                            ? 'Saved ${keys.hint}. Paste a new key to replace it.'
                            : 'Paste your key here',
                        hintMaxLines: 2,
                        hintStyle: SusText.body(14, color: SusColors.brown),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 13,
                        ),
                        enabledBorder: _border(),
                        focusedBorder: _border(color: SusColors.teal),
                        border: _border(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Part of the field: Show and Hide leave the keyboard up.
                  TextFieldTapRegion(
                    child: Semantics(
                      button: true,
                      label: _show ? 'Hide key' : 'Show key',
                      excludeSemantics: true,
                      onTap: typed
                          ? () => setState(() => _show = !_show)
                          : null,
                      child: GestureDetector(
                        // Show only reveals text that hasn't been saved yet.
                        onTap: typed
                            ? () => setState(() => _show = !_show)
                            : null,
                        child: Opacity(
                          opacity: typed ? 1 : 0.5,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: SusColors.cream,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: SusColors.ink,
                                width: 2.5,
                              ),
                            ),
                            child: Icon(
                              _show
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              color: SusColors.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: ChunkyButton.light(
                      label: 'Paste',
                      height: 44,
                      fontSize: 14,
                      onPressed: _paste,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 5,
                    child: ChunkyButton.light(
                      label: 'Remove',
                      height: 44,
                      fontSize: 14,
                      onPressed: keys.hasKey && !testing
                          ? () => _confirmRemove(keys)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 7,
                    child: ChunkyButton(
                      label: testing
                          ? 'Testing…'
                          : (typed ? 'Save & test' : 'Test connection'),
                      height: 44,
                      fontSize: 14,
                      onPressed: (typed || keys.hasKey) && !testing
                          ? () =>
                                _saveAndTest(keys, services.settings.telemetry)
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (keys.error != null) ...[
                Text(
                  keys.error!,
                  style: SusText.body(13, weight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
              ],
              Text.rich(
                TextSpan(
                  style: SusText.body(13),
                  children: [
                    if (helper.isNotEmpty) TextSpan(text: '$helper '),
                    const TextSpan(
                      text:
                          "Saved in this iPhone's Keychain, used only to sign in to Presage. Get one at ",
                    ),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: Semantics(
                        link: true,
                        child: GestureDetector(
                          onTap: services.device.openPortal,
                          child: Text(
                            'physiology.presagetech.com',
                            style: SusText.body(
                              13,
                              weight: FontWeight.w700,
                            ).copyWith(decoration: TextDecoration.underline),
                          ),
                        ),
                      ),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  OutlineInputBorder _border({Color color = SusColors.ink}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: 2.5),
      );
}

/// Status chip: outlined, with a colored dot (mock style).
class KeyStatusChip extends StatelessWidget {
  const KeyStatusChip({super.key, required this.state});

  final ApiKeyState state;

  @override
  Widget build(BuildContext context) {
    final (label, dot) = switch (state) {
      ApiKeyState.connected => ('Connected', SusColors.teal),
      ApiKeyState.none => ('No key yet', SusColors.tomato),
      ApiKeyState.rejected => ('Key rejected', SusColors.tomato),
      ApiKeyState.saved => ('Key saved', SusColors.brown),
      ApiKeyState.testing => ('Testing…', SusColors.bulb),
      ApiKeyState.checking => ('Checking…', SusColors.unlit),
    };
    return DotChip(label: label, dot: dot, outlined: true);
  }
}

class _TogglesCard extends StatelessWidget {
  const _TogglesCard({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final rows = [
          (
            'Host voice',
            'The host speaks prompts out loud',
            settings.hostVoice,
            (bool v) => settings.hostVoice = v,
          ),
          (
            'Sound effects',
            'Drumroll, buzzer, ding',
            settings.soundEffects,
            (bool v) => settings.soundEffects = v,
          ),
          (
            'Haptics',
            'Never while measuring',
            settings.haptics,
            (bool v) => settings.haptics = v,
          ),
          (
            'SDK telemetry',
            'Off by default. Anonymous per-session diagnostics to Presage: no video, no vitals, no IDs',
            settings.telemetry,
            (bool v) => settings.telemetry = v,
          ),
          (
            'Proof panel',
            'Show raw SmartSpectra values',
            settings.proofPanel,
            (bool v) => settings.proofPanel = v,
          ),
        ];
        return SusCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                _ToggleRow(
                  title: rows[i].$1,
                  subtitle: rows[i].$2,
                  value: rows[i].$3,
                  onChanged: rows[i].$4,
                  last: i == rows.length - 1,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.last = false,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool last;

  @override
  Widget build(BuildContext context) {
    // The whole 52 pt row is the tap target (≥ 44 pt).
    return Semantics(
      toggled: value,
      label: title,
      hint: subtitle,
      excludeSemantics: true,
      onTap: () => onChanged(!value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: last
                ? null
                : const Border(
                    bottom: BorderSide(color: SusColors.ink, width: 1.5),
                  ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: SusText.label(15)),
                    Text(subtitle, style: SusText.body(12)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 54,
                height: 32,
                padding: const EdgeInsets.all(2),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: value ? SusColors.teal : SusColors.unlit,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: SusColors.ink, width: 2.5),
                ),
                child: Container(
                  width: 23,
                  height: 23,
                  decoration: BoxDecoration(
                    color: SusColors.cream,
                    shape: BoxShape.circle,
                    border: Border.all(color: SusColors.ink, width: 2),
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
