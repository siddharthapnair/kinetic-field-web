import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_field/kinetic_field.dart';
import 'package:kinetic_field_web/fullscreen_controller.dart';
import 'package:kinetic_field_web/kinetic_field_app.dart';
import 'package:kinetic_field_web/pose_source.dart';

class _FakePoseSource implements PoseSource {
  _FakePoseSource({this.startFailure});

  final PoseSourceException? startFailure;
  final StreamController<PoseObservation> controller =
      StreamController<PoseObservation>.broadcast();
  var starts = 0;
  var stops = 0;

  @override
  Stream<PoseObservation> get observations => controller.stream;

  @override
  Future<void> start() async {
    starts += 1;
    final failure = startFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> stop() async => stops += 1;

  @override
  Future<void> dispose() => controller.close();
}

class _FakeFullscreenController implements FullscreenController {
  final StreamController<bool> controller = StreamController<bool>.broadcast(
    sync: true,
  );
  final List<bool> requests = <bool>[];
  var disposed = false;

  @override
  Stream<bool> get changes => controller.stream;

  @override
  Future<bool> setEnabled(bool enabled) async {
    requests.add(enabled);
    return enabled;
  }

  void reportBrowserState(bool enabled) => controller.add(enabled);

  @override
  Future<void> dispose() async {
    disposed = true;
    await controller.close();
  }
}

void main() {
  testWidgets('starts camera and forwards mirrored pose samples', (
    tester,
  ) async {
    final source = _FakePoseSource();
    final controller = KineticFieldController();

    await tester.pumpWidget(
      KineticFieldApp(poseSourceFactory: () => source, controller: controller),
    );
    expect(find.text('Shape motion\ninto light.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Enable camera'));
    await tester.pump();
    await tester.pump();
    expect(source.starts, 1);
    expect(find.text('CAMERA POSE ACTIVE'), findsOneWidget);

    source.controller.add(
      const PoseObservation(
        x: 0.25,
        y: 0.4,
        vx: 0.08,
        vy: -0.03,
        energy: 0.75,
        confidence: 0.9,
        timestamp: Duration(milliseconds: 20),
      ),
    );
    await tester.pump();
    expect(controller.motion.x, closeTo(0.75, 0.0001));
    expect(controller.motion.vx, closeTo(-0.08, 0.0001));
    expect(controller.motion.confidence, 0.9);
  });

  testWidgets('camera failure retains pointer mode and recovery copy', (
    tester,
  ) async {
    final source = _FakePoseSource(
      startFailure: const PoseSourceException(
        PoseSourceFailure.denied,
        'Permission denied',
      ),
    );
    await tester.pumpWidget(KineticFieldApp(poseSourceFactory: () => source));

    await tester.tap(find.widgetWithText(FilledButton, 'Enable camera'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Camera access was declined. Pointer mode remains active.'),
      findsWidgets,
    );
    expect(find.text('Continue with pointer'), findsOneWidget);
  });

  testWidgets('runtime inference failure restores pointer input', (
    tester,
  ) async {
    final source = _FakePoseSource();
    final controller = KineticFieldController();
    await tester.pumpWidget(
      KineticFieldApp(poseSourceFactory: () => source, controller: controller),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Enable camera'));
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<KineticFieldView>(find.byType(KineticFieldView))
          .enablePointer,
      isFalse,
    );

    source.controller.addError(
      const PoseSourceException(PoseSourceFailure.failed, 'Inference failed'),
    );
    await tester.pump();

    expect(
      find.text('The camera could not continue. Pointer mode remains active.'),
      findsWidgets,
    );
    expect(
      tester
          .widget<KineticFieldView>(find.byType(KineticFieldView))
          .enablePointer,
      isTrue,
    );
    expect(controller.motion.energy, 0);
  });

  testWidgets('settings and keyboard presentation mode remain available', (
    tester,
  ) async {
    final source = _FakePoseSource();
    final fullscreen = _FakeFullscreenController();
    bool? presentationMode;
    await tester.pumpWidget(
      KineticFieldApp(
        poseSourceFactory: () => source,
        fullscreenController: fullscreen,
        onPresentationModeChanged: (enabled) => presentationMode = enabled,
      ),
    );

    await tester.tap(find.byTooltip('Field controls'));
    await tester.pump();
    expect(find.text('Shape the response'), findsOneWidget);
    expect(find.text('Mirror camera'), findsOneWidget);
    expect(find.text('Calm motion'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Shape the response'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(fullscreen.requests, <bool>[true]);
    expect(presentationMode, isTrue);

    fullscreen.reportBrowserState(false);
    await tester.pump();
    expect(presentationMode, isFalse);
    expect(find.byTooltip('Enter presentation mode'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(fullscreen.requests, <bool>[true, true, false]);
    expect(fullscreen.disposed, isTrue);
  });

  testWidgets('short mobile layout opens without overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      KineticFieldApp(poseSourceFactory: _FakePoseSource.new),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Field controls'));
    await tester.pump();
    expect(find.text('Shape the response'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced-motion reset preserves calm mode', (tester) async {
    final controller = KineticFieldController(
      settings: const KineticFieldSettings(force: 2, calm: true),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: KineticFieldExperience(
            poseSourceFactory: _FakePoseSource.new,
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pump();
    controller.updateSettings(
      controller.settings.copyWith(force: 2, calm: true),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(controller.settings.force, closeTo(1.18, 0.0001));
    expect(controller.settings.calm, isTrue);
  });

  testWidgets('settings fit a very short landscape viewport', (tester) async {
    tester.view.physicalSize = const Size(640, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      KineticFieldApp(poseSourceFactory: _FakePoseSource.new),
    );
    await tester.tap(find.byTooltip('Field controls'));
    await tester.pump();

    expect(find.text('Shape the response'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
