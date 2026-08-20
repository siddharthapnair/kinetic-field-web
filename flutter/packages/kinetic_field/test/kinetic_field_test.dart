import 'dart:ui' show Color, PointerDeviceKind;

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
        pointSize: 1.7,
        quality: KineticQuality.high,
        calm: true,
      ),
    );
  });

  test('default settings favour a denser bounded field', () {
    const settings = KineticFieldSettings();

    expect(settings.pointSize, 1.7);
    expect(settings.depth, 1.0);
    expect(settings.trails, 0.86);
  });

  test('input frames normalise landmarks without changing their identity', () {
    final frame = KineticInputFrame(
      sequence: -4,
      capturedAt: const Duration(milliseconds: 10),
      receivedAt: const Duration(milliseconds: 20),
      kind: KineticInputKind.pose,
      landmarks: const <KineticLandmarkObservation>[
        KineticLandmarkObservation(
          id: KineticLandmarkId.leftWrist,
          x: double.nan,
          y: 1.4,
          confidence: 2,
        ),
      ],
    ).normalised();

    expect(frame.sequence, 0);
    expect(frame.landmarks.single.id, KineticLandmarkId.leftWrist);
    expect(frame.landmarks.single.x, 0.5);
    expect(frame.landmarks.single.y, 1);
    expect(frame.landmarks.single.confidence, 1);
  });

  test('processor keeps two wrists independent and derives pair features', () {
    final processor = KineticMotionProcessor();
    addTearDown(processor.dispose);
    processor.ingest(
      const KineticInputFrame(
        sequence: 1,
        capturedAt: Duration.zero,
        receivedAt: Duration(milliseconds: 4),
        kind: KineticInputKind.pose,
        landmarks: <KineticLandmarkObservation>[
          KineticLandmarkObservation(
            id: KineticLandmarkId.leftWrist,
            x: 0.2,
            y: 0.55,
            confidence: 0.92,
          ),
          KineticLandmarkObservation(
            id: KineticLandmarkId.rightWrist,
            x: 0.8,
            y: 0.45,
            confidence: 0.9,
          ),
          KineticLandmarkObservation(
            id: KineticLandmarkId.leftShoulder,
            x: 0.38,
            y: 0.42,
            confidence: 0.95,
          ),
          KineticLandmarkObservation(
            id: KineticLandmarkId.rightShoulder,
            x: 0.62,
            y: 0.42,
            confidence: 0.95,
          ),
        ],
      ),
    );

    final state = processor.sample();
    expect(state.visibleEffectorCount, 2);
    expect(state.left.x, closeTo(0.2, 0.001));
    expect(state.right.x, closeTo(0.8, 0.001));
    expect(state.midpointX, closeTo(0.5, 0.001));
    expect(state.separation, greaterThan(0.59));
    expect(state.shoulderSpan, lessThan(0.32));
  });

  test('processor retains an event for the display window', () {
    var now = const Duration(milliseconds: 700);
    final processor = KineticMotionProcessor(clock: () => now);
    addTearDown(processor.dispose);
    processor.ingest(
      const KineticInputFrame(
        sequence: 1,
        capturedAt: Duration.zero,
        receivedAt: Duration(milliseconds: 4),
        kind: KineticInputKind.pose,
        landmarks: <KineticLandmarkObservation>[
          KineticLandmarkObservation(
            id: KineticLandmarkId.leftWrist,
            x: 0.2,
            y: 0.5,
            confidence: 0.95,
          ),
          KineticLandmarkObservation(
            id: KineticLandmarkId.rightWrist,
            x: 0.8,
            y: 0.5,
            confidence: 0.95,
          ),
          KineticLandmarkObservation(
            id: KineticLandmarkId.leftShoulder,
            x: 0.38,
            y: 0.42,
            confidence: 0.95,
          ),
          KineticLandmarkObservation(
            id: KineticLandmarkId.rightShoulder,
            x: 0.62,
            y: 0.42,
            confidence: 0.95,
          ),
        ],
      ),
    );

    var state = processor.sample();
    expect(state.event, KineticMotionEvent.open);
    expect(state.eventSequence, 1);

    now = const Duration(milliseconds: 919);
    state = processor.sample();
    expect(state.event, KineticMotionEvent.open);
    expect(state.eventSequence, 1);

    now = const Duration(milliseconds: 921);
    state = processor.sample();
    expect(state.event, KineticMotionEvent.none);
    expect(state.eventSequence, 1);
  });

  test('cross detection is equivalent in mirrored anatomical coordinates', () {
    KineticMotionState deriveCross({required bool mirrored}) {
      var now = const Duration(milliseconds: 700);
      final processor = KineticMotionProcessor(clock: () => now);
      addTearDown(processor.dispose);
      double oriented(double x) => mirrored ? 1 - x : x;

      KineticInputFrame frame({
        required int sequence,
        required Duration capturedAt,
        required bool crossed,
      }) {
        final leftWrist = crossed ? 0.38 : 0.62;
        final rightWrist = crossed ? 0.62 : 0.38;
        return KineticInputFrame(
          sequence: sequence,
          capturedAt: capturedAt,
          receivedAt: capturedAt,
          kind: KineticInputKind.pose,
          landmarks: <KineticLandmarkObservation>[
            KineticLandmarkObservation(
              id: KineticLandmarkId.leftWrist,
              x: oriented(leftWrist),
              y: 0.5,
              confidence: 0.95,
            ),
            KineticLandmarkObservation(
              id: KineticLandmarkId.rightWrist,
              x: oriented(rightWrist),
              y: 0.5,
              confidence: 0.95,
            ),
            KineticLandmarkObservation(
              id: KineticLandmarkId.leftShoulder,
              x: oriented(0.62),
              y: 0.42,
              confidence: 0.95,
            ),
            KineticLandmarkObservation(
              id: KineticLandmarkId.rightShoulder,
              x: oriented(0.38),
              y: 0.42,
              confidence: 0.95,
            ),
          ],
        );
      }

      processor.ingest(
        frame(
          sequence: 1,
          capturedAt: Duration.zero,
          crossed: false,
        ),
      );
      expect(processor.sample().event, KineticMotionEvent.none);

      now = const Duration(milliseconds: 940);
      processor.ingest(
        frame(
          sequence: 2,
          capturedAt: const Duration(milliseconds: 120),
          crossed: true,
        ),
      );
      processor.ingest(
        frame(
          sequence: 3,
          capturedAt: const Duration(milliseconds: 240),
          crossed: true,
        ),
      );
      return processor.sample();
    }

    final unmirrored = deriveCross(mirrored: false);
    final mirrored = deriveCross(mirrored: true);

    expect(unmirrored.event, KineticMotionEvent.cross);
    expect(mirrored.event, KineticMotionEvent.cross);
    expect(unmirrored.eventSequence, mirrored.eventSequence);
  });

  test('controller keeps two stable pointer slots and drops lifts immediately',
      () {
    final controller = KineticFieldController();
    addTearDown(controller.dispose);
    controller.updatePointer(
      pointerId: 11,
      x: 0.25,
      y: 0.4,
      timestamp: Duration.zero,
    );
    controller.updatePointer(
      pointerId: 12,
      x: 0.75,
      y: 0.6,
      timestamp: const Duration(milliseconds: 16),
    );

    expect(controller.motionState.visibleEffectorCount, 2);
    expect(controller.motionState.left.x, 0.25);
    expect(controller.motionState.right.x, 0.75);

    controller.updatePointer(
      pointerId: 13,
      x: 0.95,
      y: 0.95,
      timestamp: const Duration(milliseconds: 24),
    );
    expect(controller.motionState.visibleEffectorCount, 2);
    expect(controller.motionState.left.x, 0.25);
    expect(controller.motionState.right.x, 0.75);

    controller.removePointer(
      11,
      timestamp: const Duration(milliseconds: 32),
    );
    expect(controller.motionState.visibleEffectorCount, 1);
    expect(controller.motionState.left.isVisible, isFalse);
    expect(controller.motionState.right.isVisible, isTrue);
    expect(
      controller.motionState.right.id,
      KineticLandmarkId.secondaryPointer,
    );
    expect(controller.motionState.right.x, 0.75);
    expect(controller.motionState.right.y, 0.6);
    expect(controller.motion.x, 0.75);
    expect(controller.motion.y, 0.6);
  });

  test('camera input clears any previous pointer tracks', () {
    final controller = KineticFieldController();
    addTearDown(controller.dispose);
    controller.updatePointer(
      pointerId: 11,
      x: 0.25,
      y: 0.4,
      timestamp: Duration.zero,
    );
    expect(controller.motionState.visibleEffectorCount, 1);

    controller.ingestFrame(
      const KineticInputFrame(
        sequence: 1,
        capturedAt: Duration(milliseconds: 16),
        receivedAt: Duration(milliseconds: 18),
        kind: KineticInputKind.pose,
        landmarks: <KineticLandmarkObservation>[],
      ),
    );

    expect(controller.motionState.visibleEffectorCount, 0);
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

  testWidgets('view reuses its painter across routine parent rebuilds', (
    tester,
  ) async {
    final controller = KineticFieldController();

    Widget field({
      required String label,
      Color background = const Color(0xFF050810),
    }) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 180,
          height: 120,
          child: KineticFieldView(
            controller: controller,
            backgroundColor: background,
            semanticLabel: label,
          ),
        ),
      );
    }

    await tester.pumpWidget(field(label: 'First label'));
    final firstPainter =
        tester.widget<CustomPaint>(find.byType(CustomPaint)).painter;

    await tester.pumpWidget(field(label: 'Updated label'));
    final reusedPainter =
        tester.widget<CustomPaint>(find.byType(CustomPaint)).painter;
    expect(reusedPainter, same(firstPainter));

    await tester.pumpWidget(
      field(
        label: 'Updated label',
        background: const Color(0xFF071019),
      ),
    );
    final replacement =
        tester.widget<CustomPaint>(find.byType(CustomPaint)).painter;
    expect(replacement, isNot(same(firstPainter)));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('calm mode still responds to direct input', (
    tester,
  ) async {
    final controller = KineticFieldController(
      settings: const KineticFieldSettings(calm: true),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 120,
          height: 80,
          child: KineticFieldView(controller: controller),
        ),
      ),
    );

    final painter =
        tester.widget<CustomPaint>(find.byType(CustomPaint)).painter as dynamic;
    expect(painter.debugAutonomousTime, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(painter.debugAutonomousTime, 0);

    final field = find.byType(KineticFieldView);
    final topLeft = tester.getTopLeft(field);
    final fieldSize = tester.getSize(field);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: topLeft + const Offset(24, 26));
    await gesture.moveTo(topLeft + const Offset(86, 51));
    await tester.pump();
    expect(controller.motionState.visibleEffectorCount, 1);
    expect(controller.motion.x, closeTo(86 / fieldSize.width, 0.02));
    expect(controller.motion.energy, greaterThan(0));

    await gesture.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
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
    expect(reportedStats!.particleCount, 4200);
    expect(controller.stats, reportedStats);

    await gesture.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
