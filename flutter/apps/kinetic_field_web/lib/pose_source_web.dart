import 'dart:async';
import 'dart:js_interop';

import 'package:kinetic_field/kinetic_field.dart';

import 'pose_source.dart';

@JS('kineticFieldMoveNet')
external _MoveNetBridge? get _moveNetBridge;

extension type _MoveNetBridge(JSObject _) implements JSObject {
  external JSPromise<JSAny?> start(JSFunction onFrame, JSFunction onError);

  external JSPromise<JSAny?> stop();
}

extension type _MoveNetFrame(JSObject _) implements JSObject {
  external JSNumber get version;

  external JSNumber get sequence;

  external JSNumber get capturedAtMs;

  external JSNumber get completedAtMs;

  external JSArray<_MoveNetLandmark> get landmarks;
}

extension type _MoveNetLandmark(JSObject _) implements JSObject {
  external JSString get id;

  external JSNumber get x;

  external JSNumber get y;

  external JSNumber get confidence;
}

PoseSourceFactory? _registeredFactory;

/// Overrides the conventional `window.kineticFieldMoveNet` bridge.
///
/// This keeps the host testable and lets an embedding application supply a
/// different MoveNet implementation without changing any UI code.
void registerMoveNetPoseSourceFactory(PoseSourceFactory factory) {
  _registeredFactory = factory;
}

PoseSource createPlatformPoseSource() {
  final registeredFactory = _registeredFactory;
  if (registeredFactory != null) return registeredFactory();

  final bridge = _moveNetBridge;
  if (bridge == null) {
    return const UnavailablePoseSource(
      'The MoveNet camera bridge has not been loaded.',
    );
  }

  return BridgePoseSource(
    (emit, fail) async {
      var failed = false;
      var lastSequence = -1;
      var lastCapturedAtMs = -1.0;

      void rejectFrame(String message) {
        if (failed) return;
        failed = true;
        unawaited(
          Future<void>.sync(() async {
            try {
              await bridge.stop().toDart;
            } catch (_) {
              // The typed frame failure remains the useful host error.
            }
          }),
        );
        fail(PoseSourceException(PoseSourceFailure.failed, message));
      }

      final JSFunction onFrame = ((JSObject frameObject) {
        if (failed) return;
        final frame = _MoveNetFrame(frameObject);
        final version = _integer(frame.version);
        final sequence = _integer(frame.sequence);
        final capturedAtMs = _finiteNumber(frame.capturedAtMs);
        final completedAtMs = _finiteNumber(frame.completedAtMs);
        if (version != 1) {
          rejectFrame('MoveNet emitted unsupported frame version $version.');
          return;
        }
        if (sequence == null || sequence < 0 || sequence <= lastSequence) {
          rejectFrame('MoveNet emitted a duplicate or out-of-order sequence.');
          return;
        }
        if (capturedAtMs == null ||
            completedAtMs == null ||
            capturedAtMs < 0 ||
            completedAtMs < capturedAtMs ||
            capturedAtMs <= lastCapturedAtMs) {
          rejectFrame('MoveNet emitted invalid or out-of-order timestamps.');
          return;
        }

        final landmarks = <KineticLandmarkObservation>[];
        final seen = <KineticLandmarkId>{};
        for (final rawLandmark in frame.landmarks.toDart) {
          final id = _landmarkId(rawLandmark.id.toDart);
          if (id == null) continue;
          if (!seen.add(id)) {
            rejectFrame('MoveNet emitted a duplicate ${id.name} landmark.');
            return;
          }
          final x = _finiteNumber(rawLandmark.x);
          final y = _finiteNumber(rawLandmark.y);
          final confidence = _finiteNumber(rawLandmark.confidence);
          if (x == null || y == null || confidence == null) {
            rejectFrame('MoveNet emitted a non-finite ${id.name} landmark.');
            return;
          }
          landmarks.add(
            KineticLandmarkObservation(
              id: id,
              x: x.clamp(0.0, 1.0),
              y: y.clamp(0.0, 1.0),
              confidence: confidence.clamp(0.0, 1.0),
            ),
          );
        }
        lastSequence = sequence;
        lastCapturedAtMs = capturedAtMs;
        emit(
          KineticInputFrame(
            version: 1,
            sequence: sequence,
            capturedAt: _milliseconds(capturedAtMs),
            receivedAt: _milliseconds(completedAtMs),
            kind: KineticInputKind.pose,
            landmarks: List<KineticLandmarkObservation>.unmodifiable(landmarks),
          ),
        );
      }).toJS;
      final JSFunction onError = ((JSString message) {
        fail(_poseSourceException(message.toDart));
      }).toJS;

      try {
        await bridge.start(onFrame, onError).toDart;
      } catch (error) {
        throw _poseSourceException(error.toString());
      }
    },
    () async {
      await bridge.stop().toDart;
    },
  );
}

KineticLandmarkId? _landmarkId(String id) => switch (id) {
  'leftWrist' => KineticLandmarkId.leftWrist,
  'rightWrist' => KineticLandmarkId.rightWrist,
  'leftElbow' => KineticLandmarkId.leftElbow,
  'rightElbow' => KineticLandmarkId.rightElbow,
  'leftShoulder' => KineticLandmarkId.leftShoulder,
  'rightShoulder' => KineticLandmarkId.rightShoulder,
  _ => null,
};

double? _finiteNumber(JSNumber number) {
  final value = number.toDartDouble;
  return value.isFinite ? value : null;
}

int? _integer(JSNumber number) {
  final value = _finiteNumber(number);
  if (value == null || value != value.roundToDouble()) return null;
  return value.toInt();
}

Duration _milliseconds(double value) {
  return Duration(microseconds: (value * 1000).round());
}

PoseSourceException _poseSourceException(String message) {
  final normalised = message.toLowerCase();
  if (normalised.contains('notallowed') || normalised.contains('permission')) {
    return PoseSourceException(PoseSourceFailure.denied, message);
  }
  if (normalised.contains('notfound') || normalised.contains('unavailable')) {
    return PoseSourceException(PoseSourceFailure.unavailable, message);
  }
  return PoseSourceException(PoseSourceFailure.failed, message);
}
