import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_field/kinetic_field.dart';
import 'package:kinetic_field_web/fullscreen_controller.dart';
import 'package:kinetic_field_web/kinetic_field_app.dart';
import 'package:kinetic_field_web/pose_source.dart';
import 'package:kinetic_field_web/soundscape_controller.dart';

class _FakePoseSource implements PoseSource {
  _FakePoseSource({this.startFailure});

  final PoseSourceException? startFailure;
  final StreamController<KineticInputFrame> controller =
      StreamController<KineticInputFrame>.broadcast();
  var starts = 0;
  var stops = 0;

  @override
  Stream<KineticInputFrame> get observations => controller.stream;

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

class _FakeSoundscapeController implements SoundscapeController {
  final List<String> scenes = <String>[];
  var _enabled = false;
  var _volume = defaultSoundscapeVolume;
  var disposed = false;

  @override
  bool get isSupported => true;

  @override
  bool get isEnabled => _enabled;

  @override
  double get volume => _volume;

  @override
  Future<bool> enable() async => _enabled = true;

  @override
  Future<bool> disable() async {
    _enabled = false;
    return true;
  }

  @override
  void setVolume(double value) => _volume = value.clamp(0, 1);

  @override
  void update({
    required String sceneId,
    required double energy,
    required int handCount,
    double? leftX,
    double? leftY,
    double? rightX,
    double? rightY,
    bool calm = false,
  }) {
    scenes.add(sceneId);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  testWidgets('starts camera and forwards mirrored pose samples', (
    tester,
  ) async {
    final source = _FakePoseSource();
    final controller = KineticFieldController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      KineticFieldApp(poseSourceFactory: () => source, controller: controller),
    );
    expect(find.text('Your hands\nmake worlds move.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Play with camera'));
    await tester.pump();
    await tester.pump();
    expect(source.starts, 1);
    expect(find.text('TWO-HAND CAMERA ACTIVE'), findsOneWidget);

    source.controller.add(
      const KineticInputFrame(
        sequence: 1,
        capturedAt: Duration(milliseconds: 20),
        receivedAt: Duration(milliseconds: 24),
        kind: KineticInputKind.pose,
        landmarks: <KineticLandmarkObservation>[
          KineticLandmarkObservation(
            id: KineticLandmarkId.leftWrist,
            x: 0.25,
            y: 0.4,
            confidence: 0.9,
          ),
          KineticLandmarkObservation(
            id: KineticLandmarkId.rightWrist,
            x: 0.72,
            y: 0.52,
            confidence: 0.88,
          ),
        ],
      ),
    );
    await tester.pump();
    expect(controller.motionState.visibleEffectorCount, 2);
    expect(controller.motionState.left.x, closeTo(0.75, 0.0001));
    expect(controller.motionState.right.x, closeTo(0.28, 0.0001));

    await tester.tap(find.byTooltip('Field controls'));
    await tester.pump();
    final mirrorTile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Mirror camera'),
    );
    mirrorTile.onChanged!(false);
    await tester.pump();
    expect(controller.motionState.visibleEffectorCount, 0);

    source.controller.add(
      const KineticInputFrame(
        sequence: 2,
        capturedAt: Duration(milliseconds: 40),
        receivedAt: Duration(milliseconds: 44),
        kind: KineticInputKind.pose,
        landmarks: <KineticLandmarkObservation>[
          KineticLandmarkObservation(
            id: KineticLandmarkId.leftWrist,
            x: 0.25,
            y: 0.4,
            confidence: 0.9,
          ),
          KineticLandmarkObservation(
            id: KineticLandmarkId.rightWrist,
            x: 0.72,
            y: 0.52,
            confidence: 0.88,
          ),
        ],
      ),
    );
    await tester.pump();
    expect(controller.motionState.left.x, closeTo(0.25, 0.0001));
    expect(controller.motionState.left.speed, 0);
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

    await tester.tap(find.widgetWithText(FilledButton, 'Play with camera'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Camera access was declined. Pointer mode remains active.'),
      findsWidgets,
    );
    expect(find.text('Play with pointer'), findsOneWidget);
  });

  testWidgets('world switching preserves camera and updates optional sound', (
    tester,
  ) async {
    final source = _FakePoseSource();
    final controller = KineticFieldController();
    final sound = _FakeSoundscapeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      KineticFieldApp(
        poseSourceFactory: () => source,
        controller: controller,
        soundscapeController: sound,
      ),
    );

    await tester.tap(find.text('Fireflies'));
    await tester.pump();
    expect(controller.settings.scene, KineticScene.fireflies);
    expect(find.text('Your hands\nmake worlds move.'), findsOneWidget);

    await tester.tap(find.byTooltip('Turn sound on'));
    await tester.pump();
    controller.updatePointer(
      x: 0.35,
      y: 0.4,
      timestamp: const Duration(milliseconds: 16),
    );
    expect(sound.scenes.last, 'fireflies');

    await tester.tap(find.widgetWithText(FilledButton, 'Play with camera'));
    await tester.pump();
    await tester.pump();
    expect(source.starts, 1);

    await tester.tap(find.byTooltip('Choose a play world'));
    await tester.pump();
    await tester.tap(find.text('Bloom').last);
    await tester.pump();
    expect(controller.settings.scene, KineticScene.bloom);
    expect(source.starts, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(sound.isEnabled, isFalse);
    expect(sound.disposed, isFalse);
  });

  testWidgets('runtime inference failure restores pointer input', (
    tester,
  ) async {
    final source = _FakePoseSource();
    final controller = KineticFieldController();
    await tester.pumpWidget(
      KineticFieldApp(poseSourceFactory: () => source, controller: controller),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Play with camera'));
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
