part of '../../kinetic_field.dart';

/// Identifies the platform adapter that produced a [KineticInputFrame].
enum KineticInputKind { pose, pointer, native }

/// Landmarks understood by the platform-neutral motion processor.
enum KineticLandmarkId {
  leftWrist,
  rightWrist,
  leftElbow,
  rightElbow,
  leftShoulder,
  rightShoulder,
  primaryPointer,
  secondaryPointer,
}

/// One raw, normalised landmark supplied by an input adapter.
///
/// Input adapters should not smooth, mirror or infer velocity. Those operations
/// belong to [KineticMotionProcessor], which keeps camera, pointer and native
/// input behaviour consistent.
@immutable
class KineticLandmarkObservation {
  const KineticLandmarkObservation({
    required this.id,
    required this.x,
    required this.y,
    this.confidence = 1,
  });

  final KineticLandmarkId id;
  final double x;
  final double y;
  final double confidence;

  KineticLandmarkObservation normalised() {
    return KineticLandmarkObservation(
      id: id,
      x: _finiteOr(x, 0.5).clamp(0.0, 1.0),
      y: _finiteOr(y, 0.5).clamp(0.0, 1.0),
      confidence: _finiteOr(confidence, 0).clamp(0.0, 1.0),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is KineticLandmarkObservation &&
            id == other.id &&
            x == other.x &&
            y == other.y &&
            confidence == other.confidence;
  }

  @override
  int get hashCode => Object.hash(id, x, y, confidence);
}

/// A versioned input packet crossing the input to processing boundary.
///
/// [capturedAt] and [receivedAt] use a monotonic source epoch. Their difference
/// is retained for host-side latency diagnostics, while the processor's own
/// clock controls freshness and prediction.
@immutable
class KineticInputFrame {
  const KineticInputFrame({
    this.version = 1,
    required this.sequence,
    required this.capturedAt,
    required this.receivedAt,
    required this.kind,
    required this.landmarks,
  });

  final int version;
  final int sequence;
  final Duration capturedAt;
  final Duration receivedAt;
  final KineticInputKind kind;
  final List<KineticLandmarkObservation> landmarks;

  KineticInputFrame normalised() {
    return KineticInputFrame(
      version: version <= 0 ? 1 : version,
      sequence: math.max(0, sequence),
      capturedAt: capturedAt,
      receivedAt: receivedAt,
      kind: kind,
      landmarks: List<KineticLandmarkObservation>.unmodifiable(
        landmarks.map((landmark) => landmark.normalised()),
      ),
    );
  }

  KineticLandmarkObservation? landmark(KineticLandmarkId id) {
    for (final landmark in landmarks) {
      if (landmark.id == id) return landmark;
    }
    return null;
  }
}

/// A filtered, predicted control point in viewport units per second.
@immutable
class KineticEffectorState {
  const KineticEffectorState({
    required this.id,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.speed,
    required this.acceleration,
    required this.confidence,
    required this.freshness,
  });

  const KineticEffectorState.idle(this.id)
      : x = 0.5,
        y = 0.5,
        vx = 0,
        vy = 0,
        speed = 0,
        acceleration = 0,
        confidence = 0,
        freshness = 0;

  final KineticLandmarkId id;
  final double x;
  final double y;
  final double vx;
  final double vy;
  final double speed;
  final double acceleration;
  final double confidence;
  final double freshness;

  bool get isVisible => confidence * freshness >= 0.08;

  double get energy =>
      (speed / 1.65 + acceleration / 8).clamp(0.0, 1.0) *
      confidence *
      freshness;
}

/// Discrete rewards derived from continuous movement.
enum KineticMotionEvent { none, open, gather, lift, settle, cross }

/// Stable motion state consumed independently by visual and audio outputs.
@immutable
class KineticMotionState {
  const KineticMotionState({
    required this.sampledAt,
    required this.left,
    required this.right,
    required this.midpointX,
    required this.midpointY,
    required this.separation,
    required this.separationVelocity,
    required this.angularVelocity,
    required this.energy,
    required this.shoulderSpan,
    required this.eventSequence,
    required this.event,
  });

  static const idle = KineticMotionState(
    sampledAt: Duration.zero,
    left: KineticEffectorState.idle(KineticLandmarkId.leftWrist),
    right: KineticEffectorState.idle(KineticLandmarkId.rightWrist),
    midpointX: 0.5,
    midpointY: 0.5,
    separation: 0,
    separationVelocity: 0,
    angularVelocity: 0,
    energy: 0,
    shoulderSpan: 0.32,
    eventSequence: 0,
    event: KineticMotionEvent.none,
  );

  final Duration sampledAt;
  final KineticEffectorState left;
  final KineticEffectorState right;
  final double midpointX;
  final double midpointY;
  final double separation;
  final double separationVelocity;
  final double angularVelocity;
  final double energy;
  final double shoulderSpan;
  final int eventSequence;
  final KineticMotionEvent event;

  int get visibleEffectorCount =>
      (left.isVisible ? 1 : 0) + (right.isVisible ? 1 : 0);

  Iterable<KineticEffectorState> get visibleEffectors sync* {
    if (left.isVisible) yield left;
    if (right.isVisible) yield right;
  }
}
