import 'dart:js_interop';

import 'pose_source.dart';

@JS('kineticFieldMoveNet')
external _MoveNetBridge? get _moveNetBridge;

extension type _MoveNetBridge(JSObject _) implements JSObject {
  external JSPromise<JSAny?> start(JSFunction onPose, JSFunction onError);

  external JSPromise<JSAny?> stop();
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
      final JSFunction onPose =
          (
                JSNumber x,
                JSNumber y,
                JSNumber vx,
                JSNumber vy,
                JSNumber energy,
                JSNumber confidence,
                JSNumber timestampMs,
              ) {
                emit(
                  PoseObservation(
                    x: x.toDartDouble.clamp(0, 1),
                    y: y.toDartDouble.clamp(0, 1),
                    vx: vx.toDartDouble.clamp(-1, 1),
                    vy: vy.toDartDouble.clamp(-1, 1),
                    energy: energy.toDartDouble.clamp(0, 1),
                    confidence: confidence.toDartDouble.clamp(0, 1),
                    timestamp: Duration(
                      microseconds: (timestampMs.toDartDouble * 1000).round(),
                    ),
                  ),
                );
              }
              .toJS;
      final JSFunction onError = ((JSString message) {
        fail(_poseSourceException(message.toDart));
      }).toJS;

      try {
        await bridge.start(onPose, onError).toDart;
      } catch (error) {
        throw _poseSourceException(error.toString());
      }
    },
    () async {
      await bridge.stop().toDart;
    },
  );
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
