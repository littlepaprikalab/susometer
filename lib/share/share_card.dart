import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app_scope.dart';
import '../game/game_controller.dart';
import '../theme/game_widgets.dart';
import '../theme/tokens.dart';

/// The image behind "Share results": names, scores and awards only.
/// Transcripts (questions and answers) are never on it (SPEC.md §8).
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.boundaryKey, required this.game});

  final GlobalKey boundaryKey;
  final GameController game;

  @override
  Widget build(BuildContext context) {
    final awards = game.awards;
    if (awards == null) return const SizedBox.shrink();
    return RepaintBoundary(
      key: boundaryKey,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Material(
          color: SusColors.mustard,
          child: Container(
            width: 360,
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MarqueeBoard(
                  color: SusColors.tomato,
                  radius: 22,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Sus-o-meter',
                      textAlign: TextAlign.center,
                      style: SusText.display(34, color: SusColors.cream),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (awards.pokerFace != null)
                  _line(
                    'Best poker face',
                    awards.pokerFace!.names,
                    'avg ${awards.pokerFace!.average.round()}',
                  ),
                if (awards.mostSus != null)
                  _line(
                    'Most sus',
                    awards.mostSus!.names,
                    'avg ${awards.mostSus!.average.round()}',
                  ),
                if (awards.lieDetector != null)
                  _line(
                    'Best lie detector',
                    awards.lieDetector!.names,
                    '${awards.lieDetector!.matches} of ${awards.lieDetector!.votes}',
                  ),
                if (awards.biggestSpike != null)
                  _line(
                    'Biggest spike',
                    awards.biggestSpike!.player.name,
                    '${awards.biggestSpike!.result.score}',
                  ),
                const SizedBox(height: 10),
                for (var i = 0; i < awards.ranked.length; i++)
                  _line(
                    '${awards.placeOf(i)}.',
                    awards.ranked[i].player.name,
                    '${awards.ranked[i].average.round()}',
                  ),
                const SizedBox(height: 12),
                Text(
                  'For fun only. It reads stress, not truth.',
                  textAlign: TextAlign.center,
                  style: SusText.body(13, weight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(String label, String name, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: SusColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SusColors.ink, width: 2.5),
      ),
      child: Row(
        children: [
          Text(label, style: SusText.label(13)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: SusText.body(16, weight: FontWeight.w700),
            ),
          ),
          Text(value, style: SusText.display(16)),
        ],
      ),
    ),
  );
}

/// Renders the share card to a PNG in memory and opens the share sheet.
Future<void> shareResults(BuildContext context, GlobalKey boundaryKey) async {
  final services = AppScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return;
    await services.device.shareImage(
      data.buffer.asUint8List(),
      text: 'Sus-o-meter results. For fun only: it reads stress, not truth.',
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text("Couldn't share right now.")),
    );
  }
}
