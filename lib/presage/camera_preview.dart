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

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return const ColoredBox(color: SusColors.ink);
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
class CameraWindow extends StatelessWidget {
  const CameraWindow({super.key, this.overlay, this.showFaceGuide = true});

  final Widget? overlay;
  final bool showFaceGuide;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SusColors.ink,
        borderRadius: BorderRadius.circular(SusShape.cameraRadius),
        border: Border.all(color: SusColors.ink, width: SusShape.borderWidth),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          SusShape.cameraRadius - SusShape.borderWidth,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CameraPreview(),
            if (showFaceGuide)
              const IgnorePointer(
                child: CustomPaint(painter: _FaceOvalPainter()),
              ),
            ?overlay,
          ],
        ),
      ),
    );
  }
}

class _FaceOvalPainter extends CustomPainter {
  const _FaceOvalPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.52;
    final h = size.height * 0.68;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.48),
      width: w,
      height: h,
    );
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
  bool shouldRepaint(covariant _FaceOvalPainter oldDelegate) => false;
}
