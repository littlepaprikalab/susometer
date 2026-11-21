import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Live camera preview from the SmartSpectra SDK (`sdk.imageOutput`), hosted
/// as a native platform view. Off iOS (tests), shows a plain ink panel.
class CameraPreview extends StatelessWidget {
  const CameraPreview({super.key, this.mirror = true});

  /// Mirror horizontally, selfie-style, for the front camera.
  final bool mirror;

  /// Off iOS only: what stands in for the camera image. The demo film
  /// (`test/demo_film_test.dart`) draws a face here. Null: a plain ink panel.
  @visibleForTesting
  static WidgetBuilder? debugStandIn;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return debugStandIn?.call(context) ??
          const ColoredBox(color: SusColors.ink);
    }
    return UiKitView(
      viewType: 'sus/camera_preview',
      creationParams: {'mirror': mirror},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}

/// Camera window from the mockup: ink fill, 3px ink border, radius 24, and a
/// dashed bulb-colored face oval.
///
/// The preview fills its area and crops (aspect fill), so in a short, wide
/// box (a small phone) a portrait camera image would show only a thin band
/// and a face at a normal distance wouldn't fit. Past [maxVideoAspect] the
/// video is pillarboxed instead: ink bars at the sides, the overlay still
/// full width.
class CameraWindow extends StatelessWidget {
  const CameraWindow({
    super.key,
    this.overlay,
    this.showFaceGuide = true,
    this.guideClear = EdgeInsets.zero,
  });

  final Widget? overlay;
  final bool showFaceGuide;

  /// Space the overlay's chips and cards take at the top and bottom; the
  /// face oval stays between them instead of running under them.
  final EdgeInsets guideClear;

  /// Widest the video may be for its height (width / height).
  static const maxVideoAspect = 1.1;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SusColors.ink,
        borderRadius: BorderRadius.circular(SusShape.cameraRadius),
        border: Border.all(color: SusColors.ink, width: SusShape.borderWidth),
      ),
      // The video sits inside the border (a DecoratedBox paints its border
      // behind the child), with corners concentric to the card's.
      child: Padding(
        padding: const EdgeInsets.all(SusShape.borderWidth),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            SusShape.cameraRadius - SusShape.borderWidth,
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              final videoWidth = math.min(
                box.maxWidth,
                box.maxHeight * maxVideoAspect,
              );
              final side = (box.maxWidth - videoWidth) / 2;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    left: side,
                    right: side,
                    top: 0,
                    bottom: 0,
                    // Always present (radius 0 when full width), so bars
                    // appearing never rebuild the native preview.
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(side > 0 ? 14 : 0),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const CameraPreview(),
                          if (showFaceGuide)
                            IgnorePointer(
                              child: CustomPaint(
                                painter: _FaceOvalPainter(guideClear),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  ?overlay,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Width / height of the face guide: about a face, whatever the box's shape.
const faceOvalAspect = 0.72;

/// Where the face guide goes in a video area of [size]. As in the mock: at
/// most two thirds of the height, a little above centre, and about half the
/// width; never under the chips or cards in [clear].
@visibleForTesting
Rect faceOvalRect(Size size, EdgeInsets clear) {
  final top = math.max(clear.top, size.height * 0.14);
  final bottom = size.height - math.max(clear.bottom, size.height * 0.18);
  final h = math.min(bottom - top, size.width * 0.52 / faceOvalAspect);
  if (h <= 0) return Rect.zero;
  return Rect.fromCenter(
    center: Offset(size.width / 2, (top + bottom) / 2),
    width: h * faceOvalAspect,
    height: h,
  );
}

class _FaceOvalPainter extends CustomPainter {
  const _FaceOvalPainter(this.clear);

  final EdgeInsets clear;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = faceOvalRect(size, clear);
    if (rect.isEmpty) return;
    final paint = Paint()
      ..color = SusColors.bulb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final path = Path()..addOval(rect);
    for (final metric in path.computeMetrics()) {
      const dash = 12.0;
      const gap = 9.0;
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FaceOvalPainter oldDelegate) =>
      oldDelegate.clear != clear;
}
