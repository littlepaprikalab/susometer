import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../presage/camera_preview.dart';
import '../presage/presage_models.dart';
import '../screens/settings_screen.dart';
import '../settings/app_settings.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';
import '../voice/speech_service.dart';

/// Milestone 1 bridge spike (SPEC.md §14): live SmartSpectra signals and the
/// on-device transcript on one bare screen, to confirm on the iPhone that the
/// camera (SDK) and the mic (speech) work at the same time.
class BridgeSpikeScreen extends StatefulWidget {
  const BridgeSpikeScreen({super.key});

  @override
  State<BridgeSpikeScreen> createState() => _BridgeSpikeScreenState();
}

class _BridgeSpikeScreenState extends State<BridgeSpikeScreen> {
  AppServices? _services;
  StreamSubscription<PresageSample>? _presageSub;
  StreamSubscription<SpeechEvent>? _speechSub;
  Timer? _clock;

  PresageSample? _sample;
  int _blinks = 0;
  int _talkStarts = 0;
  int? _lastPulseAt;
  final List<double> _trace = [];
  bool _measureBusy = false;
  String? _presageError;
  String? _sdkVersion;

  final TranscriptBuffer _transcript = TranscriptBuffer();
  double _level = 0;
  String _speechState = 'stopped';
  String? _speechError;
  SpeechPermissions? _perms;
  bool _speechBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    final services = AppScope.of(context);
    _services = services;
    _presageSub = services.presage.samples.listen(
      _onSample,
      onError: (Object e) {
        setState(() => _presageError = '$e');
      },
    );
    _speechSub = services.speech.events.listen(
      _onSpeech,
      onError: (Object e) {
        setState(() => _speechError = '$e');
      },
    );
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
    services.apiKey.refresh();
    _loadSdkVersion(services);
  }

  Future<void> _loadSdkVersion(AppServices services) async {
    try {
      final info = await services.presage.sdkInfo();
      if (mounted) setState(() => _sdkVersion = info['version']?.toString());
    } on PresageException {
      // Not on an iPhone (tests) or bridge unavailable: leave it blank.
    }
  }

  @override
  void dispose() {
    _presageSub?.cancel();
    _speechSub?.cancel();
    _clock?.cancel();
    final services = _services;
    if (services != null) {
      services.presage.stop().catchError((Object _) {});
      services.speech.stop().catchError((Object _) {});
      services.device.setKeepAwake(false);
    }
    super.dispose();
  }

  void _onSample(PresageSample s) {
    setState(() {
      _sample = s;
      if (s.pulseAtMs != null && s.pulseAtMs != _lastPulseAt) {
        _lastPulseAt = s.pulseAtMs;
      }
      for (final e in s.events) {
        if (e.type == PresageEdgeType.blink) _blinks++;
        if (e.type == PresageEdgeType.talkStart) _talkStarts++;
      }
      _trace.addAll(s.trace);
      if (_trace.length > 240) _trace.removeRange(0, _trace.length - 240);
    });
  }

  void _onSpeech(SpeechEvent e) {
    setState(() {
      switch (e) {
        case SpeechText():
          _transcript.add(e);
        case SpeechLevel():
          _level = e.level;
        case SpeechStateChange():
          _speechState = e.state;
          if (e.state == 'stopped') _level = 0;
        case SpeechError():
          _speechError = '${e.code}: ${e.message}';
      }
    });
  }

  bool get _measuring {
    final status = _sample?.status;
    return status == PresageStatus.running || status == PresageStatus.starting;
  }

  Future<void> _openSettings({bool focusKey = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(focusKeyField: focusKey),
      ),
    );
    await _services?.apiKey.refresh();
  }

  Future<void> _startMeasuring() async {
    final services = _services!;
    if (!services.apiKey.hasKey) {
      await _openSettings(focusKey: true);
      return;
    }
    setState(() {
      _measureBusy = true;
      _presageError = null;
      _blinks = 0;
      _talkStarts = 0;
      _lastPulseAt = null;
      _trace.clear();
    });
    try {
      await services.presage.configure(telemetry: services.settings.telemetry);
      await services.presage.start();
      await services.device.setKeepAwake(true);
    } on PresageException catch (e) {
      _presageError =
          'Error code: ${e.code}. ${describePresageCode(e.code, e.message)}';
    } finally {
      if (mounted) setState(() => _measureBusy = false);
    }
  }

  Future<void> _stopMeasuring() async {
    final services = _services!;
    setState(() => _measureBusy = true);
    try {
      await services.presage.stop();
    } on PresageException catch (e) {
      _presageError = 'Error code: ${e.code}. ${e.message}';
    } finally {
      await services.device.setKeepAwake(false);
      if (mounted) setState(() => _measureBusy = false);
    }
  }

  Future<void> _startListening() async {
    final speech = _services!.speech;
    setState(() {
      _speechBusy = true;
      _speechError = null;
    });
    try {
      var perms = await speech.permissionStatus();
      if (perms.undetermined) perms = await speech.requestPermissions();
      _perms = perms;
      if (!perms.granted) {
        _speechError =
            'Microphone or speech recognition is off (mic: ${perms.mic}, '
            'speech: ${perms.speech}). Turn them on in iOS Settings.';
        return;
      }
      if (!perms.onDevice) {
        _speechError =
            "This iPhone can't recognize speech on-device for the current "
            "language, and the app won't send audio to a server.";
        return;
      }
      _transcript.clear();
      await speech.start();
    } on SpeechException catch (e) {
      _speechError = '${e.code}: ${e.message}';
    } finally {
      if (mounted) setState(() => _speechBusy = false);
    }
  }

  Future<void> _stopListening() async {
    try {
      await _services!.speech.stop();
    } on SpeechException catch (e) {
      setState(() => _speechError = '${e.code}: ${e.message}');
    }
  }

  Future<void> _startBoth() async {
    await _startMeasuring();
    if (_measuring || _presageError == null) await _startListening();
  }

  String _ago(int? ms) {
    if (ms == null) return 'never';
    final s = (DateTime.now().millisecondsSinceEpoch - ms) / 1000;
    return '${math.max(0, s).toStringAsFixed(1)} s ago';
  }

  @override
  Widget build(BuildContext context) {
    final s = _sample;
    final listening = _speechState == 'listening' || _speechState == 'paused';
    final pulseText = s?.pulse == null ? '--' : s!.pulse!.round().toString();
    final top = s?.topExpression;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Bridge spike', style: SusText.display(28)),
                ),
                RoundIconButton(
                  icon: Icons.settings_rounded,
                  tooltip: 'Settings',
                  onPressed: _openSettings,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'For fun only. Measures stress reactions, not truth.',
              style: SusText.body(14, weight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 300,
              child: CameraWindow(
                overlay: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SusPill(
                          label: _measuring ? 'Measuring' : 'Camera off',
                          icon: Icons.videocam_rounded,
                        ),
                        SusPill(
                          label: '$pulseText BPM',
                          icon: Icons.favorite_rounded,
                          color: SusColors.cream,
                          textColor: SusColors.ink,
                          fontSize: 15,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SusCard(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pulse waveform', style: SusText.label(13)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 56,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: WaveformPainter(List.of(_trace)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Grid(
              children: [
                _Stat(
                  label: 'Pulse',
                  value: s?.pulse == null
                      ? '--'
                      : '${s!.pulse!.toStringAsFixed(1)} BPM',
                  detail:
                      'conf ${_pct(s?.pulseConf)}${s?.pulseStable == true ? ' · stable' : ''}\n'
                      'updated ${_ago(_lastPulseAt)}',
                ),
                _Stat(
                  label: 'HRV (RMSSD)',
                  value: s?.rmssd == null
                      ? '--'
                      : '${s!.rmssd!.toStringAsFixed(1)} ms',
                  detail: 'conf ${_pct(s?.hrvConf)} · needs ~60 s',
                ),
                _Stat(
                  label: 'Blinks',
                  value: '$_blinks',
                  detail: s?.blink == true ? 'blinking now' : 'eyes open',
                ),
                _Stat(
                  label: 'Talking',
                  value: s?.talking == true ? 'YES' : 'no',
                  detail: '$_talkStarts talk starts',
                ),
                _Stat(
                  label: 'Expression',
                  value: top == null ? '--' : top.key,
                  detail: top == null ? '' : _pct(top.value),
                ),
                _Stat(
                  label: 'SDK status',
                  value: s?.status.name ?? 'idle',
                  detail: _sdkVersion == null ? '' : 'SDK $_sdkVersion',
                ),
                _Stat(
                  label: 'Validation',
                  value: s?.validation?.code ?? '--',
                  detail: s?.validation?.hint ?? '',
                ),
                _Stat(
                  label: 'LLM insights',
                  value: s?.insight != null
                      ? '${s!.insight!.count}'
                      : (s?.insightSeen == true ? 'yes' : 'none yet'),
                  detail: s?.insight?.summary ?? 'SDK auto-fires them',
                ),
              ],
            ),
            if (s?.error != null) ...[
              const SizedBox(height: 8),
              Text(
                'SDK error: ${s!.error!.code}. ${s.error!.message}',
                style: SusText.body(14, weight: FontWeight.w700),
              ),
            ],
            if (_presageError != null) ...[
              const SizedBox(height: 8),
              Text(
                _presageError!,
                style: SusText.body(14, weight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 12),
            SusCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Transcript', style: SusText.label(16)),
                      ),
                      SusPill(label: _speechState, icon: Icons.mic_rounded),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _LevelBar(level: _level),
                  const SizedBox(height: 10),
                  Text(
                    _transcript.isEmpty ? 'Say something…' : _transcript.text,
                    style: SusText.body(17, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'updated ${_ago(_transcript.lastUpdateMs)}'
                    '${_perms == null ? '' : ' · on-device: ${_perms!.onDevice ? 'yes' : 'no'}'}',
                    style: SusText.body(13),
                  ),
                  if (_speechError != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _speechError!,
                      style: SusText.body(14, weight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            ChunkyButton(
              label: 'Start both',
              icon: Icons.play_arrow_rounded,
              onPressed:
                  (_measuring || listening || _measureBusy || _speechBusy)
                  ? null
                  : _startBoth,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ChunkyButton.light(
                    label: _measuring ? 'Stop camera' : 'Camera',
                    icon: Icons.favorite_rounded,
                    fontSize: 15,
                    onPressed: _measureBusy
                        ? null
                        : (_measuring ? _stopMeasuring : _startMeasuring),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChunkyButton.light(
                    label: listening ? 'Stop mic' : 'Mic',
                    icon: Icons.mic_rounded,
                    fontSize: 15,
                    onPressed: _speechBusy
                        ? null
                        : (listening ? _stopListening : _startListening),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _pct(double? v) => v == null ? '--' : '${(v * 100).round()}%';
}

class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              const SizedBox(width: 10),
              Expanded(
                child: i + 1 < children.length
                    ? children[i + 1]
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      );
      rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.detail = ''});

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return SusCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: SusText.label(12)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SusText.body(19, weight: FontWeight.w700),
          ),
          if (detail.isNotEmpty) Text(detail, style: SusText.body(12)),
        ],
      ),
    );
  }
}

class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final lit = (level.clamp(0, 1) * 10).round();
    return Semantics(
      label: 'Mic level',
      value: '${(level * 100).round()}%',
      child: Row(
        children: [
          for (var i = 0; i < 10; i++)
            Expanded(
              child: Container(
                height: 12,
                margin: EdgeInsets.only(right: i == 9 ? 0 : 3),
                decoration: BoxDecoration(
                  color: i < lit ? SusColors.meterRamp[i] : SusColors.unlit,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: SusColors.ink, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Draws a scrolling line from the SDK's arterial pressure trace.
class WaveformPainter extends CustomPainter {
  WaveformPainter(this.samples);

  final List<double> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = SusColors.unlit
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      base,
    );
    if (samples.length < 2) return;
    var lo = samples.first;
    var hi = samples.first;
    for (final v in samples) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    final range = math.max(hi - lo, 1e-6);
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = size.width * i / (samples.length - 1);
      final y = size.height * (1 - (samples[i] - lo) / range);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = SusColors.tomato
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) => true;
}
