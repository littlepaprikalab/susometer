import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/presage/camera_preview.dart';

void main() {
  group('face guide', () {
    const clear = EdgeInsets.only(top: 42, bottom: 62);

    for (final size in const [
      Size(354, 428), // standard iPhone, Ask
      Size(270, 245), // iPhone SE, pillarboxed video
      Size(270, 214), // iPhone SE, largest text
      Size(354, 300), // a short box on a standard iPhone
    ]) {
      test('stays face-shaped and clear of the chips and cards ($size)', () {
        final r = faceOvalRect(size, clear);
        expect(r.width / r.height, closeTo(faceOvalAspect, 0.001));
        expect(r.top, greaterThanOrEqualTo(clear.top - 0.01));
        expect(r.bottom, lessThanOrEqualTo(size.height - clear.bottom + 0.01));
        expect(r.width, lessThanOrEqualTo(size.width * 0.53));
        expect(r.center.dx, closeTo(size.width / 2, 0.01));
      });
    }

    test('no room at all: no oval, no crash', () {
      expect(faceOvalRect(const Size(300, 80), clear), Rect.zero);
    });
  });

  group('video area', () {
    Future<Rect> videoIn(WidgetTester tester, Size box) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.fromSize(size: box, child: const CameraWindow()),
          ),
        ),
      );
      return tester.getRect(find.byType(CameraPreview));
    }

    testWidgets('a portrait-ish box uses the full width', (tester) async {
      final r = await videoIn(tester, const Size(354, 428));
      expect(r.width, closeTo(354 - 6, 0.01), reason: 'inside the border');
    });

    testWidgets('a short, wide box pillarboxes the video', (tester) async {
      final r = await videoIn(tester, const Size(339, 214));
      expect(r.width / r.height, closeTo(CameraWindow.maxVideoAspect, 0.01));
      expect(
        r.center.dx,
        closeTo(tester.getCenter(find.byType(CameraWindow)).dx, 0.01),
      );
    });
  });

  testWidgets('bars appearing (box gets shorter) keep the same native view', (
    tester,
  ) async {
    final height = ValueNotifier(428.0);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: ValueListenableBuilder(
            valueListenable: height,
            builder: (_, h, _) =>
                SizedBox(width: 354, height: h, child: const CameraWindow()),
          ),
        ),
      ),
    );
    final before = tester.element(find.byType(CameraPreview));
    height.value = 260; // 348 / 254 > maxVideoAspect: bars appear
    await tester.pump();
    final r = tester.getRect(find.byType(CameraPreview));
    expect(r.width, lessThan(340), reason: 'pillarboxed');
    expect(
      identical(tester.element(find.byType(CameraPreview)), before),
      isTrue,
      reason: 'the native preview must not be rebuilt',
    );
  });
}
