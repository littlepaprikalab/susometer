import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../theme/tokens.dart';

/// Proof Panel (SPEC.md §10): a translucent overlay with the raw SmartSpectra
/// stream and the turn timing markers, for judges and the demo video.
class ProofPanel extends StatelessWidget {
  const ProofPanel({super.key, required this.game, this.telemetry = false});

  final GameController game;
  final bool telemetry;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: game.live,
        builder: (context, _) {
          final s = game.live.sample;
          final d = game.detector;
          String pct(double? v) => v == null ? '--' : '${(v * 100).round()}%';
          String rel(int? t) {
            if (t == null) return '--';
            final secs = (t - game.questionStartMs) / 1000;
            return '${secs >= 0 ? '+' : ''}${secs.toStringAsFixed(1)}s';
          }

          final top = s?.topExpression;
          final base = game.inGame
              ? game.currentTurn.baseline ?? game.calibBaseline
              : null;
          final lines = <String>[
            'SDK ${s?.status.name ?? 'idle'} · telemetry ${telemetry ? 'ON' : 'off'}'
                '${s?.insightSeen == true ? ' · LLM INSIGHT SEEN' : ''}',
            'pulse ${s?.pulse?.toStringAsFixed(1) ?? '--'} bpm  conf ${pct(s?.pulseConf)}'
                '${s?.pulseStable == true ? ' stable' : ''}',
            'rmssd ${s?.rmssd?.toStringAsFixed(1) ?? '--'} ms  conf ${pct(s?.hrvConf)}',
            'blink ${s?.blink == true ? 'Y' : 'n'}  talking ${s?.talking == true ? 'Y' : 'n'}'
                '  mic ${(game.live.micLevel * 100).round()}%',
            'expr ${top == null ? '--' : '${top.key} ${pct(top.value)}'}',
            'valid ${s?.validation?.code ?? '--'}',
            if ((s?.validation?.hint ?? '').isNotEmpty)
              '  "${s!.validation!.hint}"',
            if (s?.error != null)
              'error ${s!.error!.code}: ${s.error!.message}',
            if (base != null)
              'base ${base.pulse.toStringAsFixed(0)}bpm ${base.blinkRatePerMin.toStringAsFixed(0)}/min '
                  'lat ${base.latencyS.toStringAsFixed(1)}s '
                  'pulse ${(base.confidentPulseMs / 1000).toStringAsFixed(0)}s face ${pct(base.faceFraction)}',
            if (d != null)
              'tQ0 ${rel(d.tQ0)} tQ1 ${rel(d.tQ1)} tA0 ${rel(d.tA0)} tA1 ${rel(d.tA1)}'
                  '${d.questionEndReason == null ? '' : ' (${d.questionEndReason!.name})'}',
          ];
          // Sits low, over the camera area, so the host bubble and the live
          // transcript stay visible for the demo.
          return Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 150),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: SusColors.ink.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'PROOF PANEL · raw SmartSpectra',
                      style: TextStyle(
                        fontFamily: 'Menlo',
                        fontFamilyFallback: ['Courier'],
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: SusColors.mustard,
                      ),
                    ),
                    for (final l in lines)
                      Text(
                        l,
                        style: const TextStyle(
                          fontFamily: 'Menlo',
                          fontFamilyFallback: ['Courier'],
                          fontSize: 11.5,
                          color: SusColors.cream,
                          height: 1.3,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
