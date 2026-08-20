import 'dart:ui' show PointerDeviceKind;

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_field/kinetic_field.dart';
import 'package:flutter/widgets.dart';

void main() {
  test('motion samples normalise unsafe input', () {
    const sample = MotionSample(
      x: double.nan,
      y: 4,
      vx: double.infinity,
      vy: -5,
      energy: 2,
      confidence: -1,
      timestamp: Duration(milliseconds: 12),
    );

    expect(
      sample.normalised(),
      const MotionSample(
        x: 0.5,
        y: 1,
        vx: 0,
        vy: -1,
        energy: 1,
        confidence: 0,
        timestamp: Duration(milliseconds: 12),
      ),
    );
  });

  test('settings copy and normalise rendering limits', () {
    final settings = const KineticFieldSettings().copyWith(
      force: 9,
      radius: 0,
      pointSize: double.nan,
      quality: KineticQuality.high,
      calm: true,
    );

    expect(
      settings.normalised(),
      const KineticFieldSettings(
        force: 3,
        radius: 0.04,
        pointSize: 1.45,
        quality: KineticQuality.high,
        calm: true,
      ),
    );
  });

  test('controller accepts external motion and notifies listeners', () {
    final controller = KineticFieldController();
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    controller.updateMotion(
      const MotionSample(
        x: 1.4,
        y: -0.2,
        energy: 0.8,
        confidence: 0.9,
        timestamp: Duration(milliseconds: 10),
      ),
    );

    expect(controller.motion.x, 1);
    expect(controller.motion.y, 0);
    expect(controller.motion.energy, 0.8);
    expect(notifications, 1);
    controller.dispose();
  });

  test('pointer updates derive bounded velocity and energy', () {
    final controller = KineticFieldController();
    controller.updatePointer(
      x: 0.2,
      y: 0.4,
      timestamp: Duration.zero,
    );
    controller.updatePointer(
      x: 0.8,
      y: 0.1,
      timestamp: const Duration(microseconds: 16667),
      confidence: 0.75,
    );

    expect(controller.motion.x, 0.8);
    expect(controller.motion.y, 0.1);
    expect(controller.motion.vx, 0.18);
    expect(controller.motion.vy, -0.18);
    expect(controller.motion.energy, 1);
    expect(controller.motion.confidence, 0.75);
    controller.dispose();
  });

  testWidgets('view paints, handles pointer input and reports stats', (
    tester,
  ) async {
    final controller = KineticFieldController();
    KineticFieldStats? reportedStats;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 320,
            height: 180,
            child: KineticFieldView(
              controller: controller,
              onStats: (stats) => reportedStats = stats,
            ),
          ),
        ),
      ),
    );

    final field = find.byType(KineticFieldView);
    final topLeft = tester.getTopLeft(field);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: topLeft + const Offset(80, 70));
    await gesture.moveTo(topLeft + const Offset(230, 110));
    await tester.pump();
    expect(controller.motion.x, closeTo(230 / 320, 0.02));
    expect(controller.motion.energy, greaterThanOrEqualTo(0.16));

    for (var frame = 0; frame < 70; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byType(CustomPaint), findsOneWidget);
    expect(reportedStats, isNotNull);
    expect(reportedStats!.fps, greaterThan(0));
    expect(reportedStats!.particleCount, greaterThan(0));
    expect(controller.stats, reportedStats);

    await gesture.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
