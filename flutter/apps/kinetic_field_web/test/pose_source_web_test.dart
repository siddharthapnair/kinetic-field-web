@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_field/kinetic_field.dart';
import 'package:kinetic_field_web/pose_source.dart';
import 'package:kinetic_field_web/pose_source_platform.dart';

class _BridgeHarness {
  _BridgeHarness() {
    bridge.setProperty(
      'start'.toJS,
      ((JSFunction onFrame, JSFunction onError) {
        frameCallback = onFrame;
        errorCallback = onError;
        return Future<JSAny?>.value(null).toJS;
      }).toJS,
    );
    bridge.setProperty(
      'stop'.toJS,
      (() {
        stops += 1;
        return Future<JSAny?>.value(null).toJS;
      }).toJS,
    );
  }

  final JSObject bridge = JSObject();
  late JSFunction frameCallback;
  late JSFunction errorCallback;
  var stops = 0;

  void install() {
    globalContext.setProperty('kineticFieldMoveNet'.toJS, bridge);
  }

  void emit(JSObject frame) {
    frameCallback.callAsFunction(null, frame);
  }

  void uninstall() {
    globalContext.delete('kineticFieldMoveNet'.toJS);
  }
}

JSObject _landmark(String id, double x, double y, double confidence) {
  return JSObject()
    ..setProperty('id'.toJS, id.toJS)
    ..setProperty('x'.toJS, x.toJS)
    ..setProperty('y'.toJS, y.toJS)
    ..setProperty('confidence'.toJS, confidence.toJS);
}

JSObject _frame({
  double version = 1,
  double sequence = 1,
  double capturedAtMs = 10,
  double completedAtMs = 14,
  List<JSObject>? landmarks,
}) {
  return JSObject()
    ..setProperty('version'.toJS, version.toJS)
    ..setProperty('sequence'.toJS, sequence.toJS)
    ..setProperty('capturedAtMs'.toJS, capturedAtMs.toJS)
    ..setProperty('completedAtMs'.toJS, completedAtMs.toJS)
    ..setProperty('landmarks'.toJS, (landmarks ?? <JSObject>[]).toJS);
}

Future<void> _expectRejected(JSObject frame) async {
  final harness = _BridgeHarness()..install();
  final source = createPlatformPoseSource();
  final errors = <Object>[];
  final subscription = source.observations.listen((_) {}, onError: errors.add);
  await source.start();

  harness.emit(frame);
  await Future<void>.delayed(Duration.zero);

  expect(errors, hasLength(1));
  expect(errors.single, isA<PoseSourceException>());
  expect(harness.stops, 1);

  await subscription.cancel();
  await source.dispose();
  harness.uninstall();
}

void main() {
  test('web adapter maps the six raw MoveNet landmarks', () async {
    final harness = _BridgeHarness()..install();
    final source = createPlatformPoseSource();
    await source.start();
    final received = source.observations.first;

    harness.emit(
      _frame(
        sequence: 7,
        capturedAtMs: 120.25,
        completedAtMs: 126.75,
        landmarks: <JSObject>[
          _landmark('leftWrist', 0.1, 0.2, 0.91),
          _landmark('rightWrist', 0.9, 0.3, 0.92),
          _landmark('leftElbow', 0.2, 0.4, 0.93),
          _landmark('rightElbow', 0.8, 0.5, 0.94),
          _landmark('leftShoulder', 0.3, 0.6, 0.95),
          _landmark('rightShoulder', 0.7, 0.7, 0.96),
        ],
      ),
    );

    final frame = await received;
    expect(frame.version, 1);
    expect(frame.sequence, 7);
    expect(frame.capturedAt, const Duration(microseconds: 120250));
    expect(frame.receivedAt, const Duration(microseconds: 126750));
    expect(
      frame.landmarks.map((landmark) => landmark.id),
      KineticLandmarkId.values.take(6),
    );

    await source.stop();
    expect(harness.stops, 1);
    await source.dispose();
    harness.uninstall();
  });

  test('web adapter rejects unsupported and malformed packets', () async {
    await _expectRejected(_frame(version: 2));
    await _expectRejected(_frame(capturedAtMs: 20, completedAtMs: 19));
    await _expectRejected(
      _frame(
        landmarks: <JSObject>[
          _landmark('leftWrist', 0.2, 0.3, 0.9),
          _landmark('leftWrist', 0.4, 0.5, 0.8),
        ],
      ),
    );
  });

  test('web adapter rejects a duplicate or stale sequence', () async {
    final harness = _BridgeHarness()..install();
    final source = createPlatformPoseSource();
    final frames = <KineticInputFrame>[];
    final errors = <Object>[];
    final subscription = source.observations.listen(
      frames.add,
      onError: errors.add,
    );
    await source.start();

    harness.emit(_frame(sequence: 3, capturedAtMs: 30, completedAtMs: 34));
    harness.emit(_frame(sequence: 3, capturedAtMs: 31, completedAtMs: 35));
    await Future<void>.delayed(Duration.zero);

    expect(frames, hasLength(1));
    expect(errors, hasLength(1));
    expect(harness.stops, 1);

    await subscription.cancel();
    await source.dispose();
    harness.uninstall();
  });
}
