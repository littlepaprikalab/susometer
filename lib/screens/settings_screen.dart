import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../presage/presage_models.dart';
import '../settings/app_settings.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';

/// 8 · Settings · Presage API key (SPEC.md §2).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.focusKeyField = false, this.onWipe});

  /// First run / no key: open with the key field focused.
  final bool focusKeyField;

  /// Clears all in-memory game data.
  final VoidCallback? onWipe;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text(
                      'Settings',
                      textAlign: TextAlign.center,
                      style: SusText.display(30),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  ApiKeyCard(autofocus: focusKeyField),
                  const SizedBox(height: 16),
                  _TogglesCard(settings: services.settings),
                  const SizedBox(height: 20),
                  ChunkyButton.light(
                    label: 'Wipe all game data now',
                    icon: Icons.delete_sweep_rounded,
                    onPressed: () {
                      onWipe?.call();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('All game data wiped.')),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'For fun only. Not a medical device. Not a lie detector.',
                    textAlign: TextAlign.center,
                    style: SusText.body(14, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Presage API key card: password-style field, Show / Paste / Remove,
/// Test connection and a status chip.
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
  bool _saving = false;

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

  Future<void> _save(ApiKeyController keys) async {
    setState(() => _saving = true);
    final ok = await keys.save(_controller.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        // The typed key is gone from Dart once it's in the Keychain.
        _controller.clear();
        _show = false;
      }
    });
    if (ok) _focus.unfocus();
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

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final keys = services.apiKey;
    return ListenableBuilder(
      listenable: keys,
      builder: (context, _) {
        final typed = _controller.text.trim().isNotEmpty;
        final testing = keys.state == ApiKeyState.testing;
        final last = keys.lastTest;
        return SusCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Presage API key', style: SusText.label(17)),
                  ),
                  KeyStatusChip(state: keys.state),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
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
                onSubmitted: typed ? (_) => _save(keys) : null,
                style: SusText.body(16, weight: FontWeight.w600),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: keys.hint != null
                      ? 'Saved ${keys.hint}. Paste a new key to replace it.'
                      : 'Paste your Presage key',
                  hintStyle: SusText.body(15, color: SusColors.brown),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  enabledBorder: _border(),
                  focusedBorder: _border(color: SusColors.teal),
                  border: _border(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ChunkyButton.light(
                      label: _show ? 'Hide' : 'Show',
                      icon: _show
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      height: 46,
                      fontSize: 14,
                      // Show only reveals text that hasn't been saved yet.
                      onPressed: typed
                          ? () => setState(() => _show = !_show)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChunkyButton.light(
                      label: 'Paste',
                      icon: Icons.content_paste_rounded,
                      height: 46,
                      fontSize: 14,
                      onPressed: _paste,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChunkyButton.light(
                      label: 'Remove',
                      icon: Icons.delete_outline_rounded,
                      height: 46,
                      fontSize: 14,
                      onPressed: keys.hasKey
                          ? () => _confirmRemove(keys)
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (typed) ...[
                ChunkyButton(
                  label: _saving ? 'Saving…' : 'Save key',
                  icon: Icons.check_rounded,
                  onPressed: _saving ? null : () => _save(keys),
                ),
                const SizedBox(height: 10),
              ],
              ChunkyButton(
                label: testing ? 'Testing…' : 'Test connection',
                icon: Icons.wifi_tethering_rounded,
                color: typed ? SusColors.cream : SusColors.teal,
                textColor: typed ? SusColors.ink : SusColors.cream,
                onPressed: keys.hasKey && !testing && !typed
                    ? () => keys.test(telemetry: services.settings.telemetry)
                    : null,
              ),
              if (last != null) ...[
                const SizedBox(height: 10),
                _TestDetail(result: last),
              ],
              if (keys.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  keys.error!,
                  style: SusText.body(14, weight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                "Saved in this iPhone's Keychain and used only to sign in to "
                'Presage. Get a free key at physiology.presagetech.com.',
                style: SusText.body(14),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: SusColors.teal,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 44),
                  ),
                  onPressed: () {
                    Clipboard.setData(
                      const ClipboardData(
                        text: 'https://physiology.presagetech.com',
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied.')),
                    );
                  },
                  icon: const Icon(Icons.link_rounded, size: 20),
                  label: Text(
                    'Copy portal link',
                    style: SusText.label(14, color: SusColors.teal),
                  ),
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
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: SusShape.borderWidth),
      );
}

class KeyStatusChip extends StatelessWidget {
  const KeyStatusChip({super.key, required this.state});

  final ApiKeyState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      ApiKeyState.connected => const SusPill(
        label: 'Connected',
        icon: Icons.check_circle_rounded,
        color: SusColors.teal,
        textColor: SusColors.cream,
      ),
      ApiKeyState.none => const SusPill(
        label: 'No key yet',
        icon: Icons.key_off_rounded,
        color: SusColors.tomato,
        textColor: SusColors.cream,
      ),
      ApiKeyState.rejected => const SusPill(
        label: 'Key rejected',
        icon: Icons.error_rounded,
        color: SusColors.tomato,
        textColor: SusColors.cream,
      ),
      ApiKeyState.saved => const SusPill(
        label: 'Key saved',
        icon: Icons.key_rounded,
      ),
      ApiKeyState.testing => const SusPill(label: 'Testing…'),
      ApiKeyState.checking => const SusPill(label: 'Checking…'),
    };
  }
}

class _TestDetail extends StatelessWidget {
  const _TestDetail({required this.result});

  final ConnectionTestResult result;

  @override
  Widget build(BuildContext context) {
    final ms = result.elapsedMs;
    final seconds = ms == null ? '' : ' in ${(ms / 1000).toStringAsFixed(1)} s';
    final text = result.ok
        ? 'Signed in to Presage$seconds.'
        : 'Error code: ${result.code}. '
              '${describePresageCode(result.code, result.message)}';
    return Text(text, style: SusText.body(14, weight: FontWeight.w600));
  }
}

class _TogglesCard extends StatelessWidget {
  const _TogglesCard({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => SusCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            _ToggleRow(
              title: 'Host voice',
              value: settings.hostVoice,
              onChanged: (v) => settings.hostVoice = v,
            ),
            _ToggleRow(
              title: 'Sound effects',
              value: settings.soundEffects,
              onChanged: (v) => settings.soundEffects = v,
            ),
            _ToggleRow(
              title: 'Haptics',
              subtitle: 'Never while measuring.',
              value: settings.haptics,
              onChanged: (v) => settings.haptics = v,
            ),
            _ToggleRow(
              title: 'SDK telemetry',
              subtitle:
                  'Off by default. When on, the SDK sends Presage an anonymous '
                  'per-session diagnostic summary: no video, no vitals, no IDs.',
              value: settings.telemetry,
              onChanged: (v) => settings.telemetry = v,
            ),
            _ToggleRow(
              title: 'Proof panel',
              subtitle: 'Shows raw SDK values on measuring screens.',
              value: settings.proofPanel,
              onChanged: (v) => settings.proofPanel = v,
              last: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.last = false,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(
                bottom: BorderSide(color: SusColors.unlit, width: 2),
              ),
      ),
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SusText.label(16)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: SusText.body(13)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
