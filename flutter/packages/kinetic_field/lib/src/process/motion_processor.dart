part of '../../kinetic_field.dart';

class _OneEuroAxis {
  _OneEuroAxis();

  static const minimumCutoff = 1.2;
  static const beta = 0.08;
  static const derivativeCutoff = 1.0;
  double? _value;
  double _derivative = 0;

  double update(double value, double deltaSeconds) {
    final previous = _value;
    if (previous == null || deltaSeconds <= 0) {
      _value = value;
      return value;
    }

    final rawDerivative = (value - previous) / deltaSeconds;
    final derivativeAlpha = _alpha(derivativeCutoff, deltaSeconds);
    _derivative += (rawDerivative - _derivative) * derivativeAlpha;
    final cutoff = minimumCutoff + beta * _derivative.abs();
    final valueAlpha = _alpha(cutoff, deltaSeconds);
    _value = previous + (value - previous) * valueAlpha;
    return _value!;
  }

  double _alpha(double cutoff, double deltaSeconds) {
    final tau = 1 / (2 * math.pi * cutoff);
    return 1 / (1 + tau / deltaSeconds);
  }

  void reset() {
    _value = null;
    _derivative = 0;
  }
}

class _LandmarkTrack {
  _LandmarkTrack(this.id);

  final KineticLandmarkId id;
  final _OneEuroAxis xFilter = _OneEuroAxis();
  final _OneEuroAxis yFilter = _OneEuroAxis();
  Duration? capturedAt;
  Duration seenAt = Duration.zero;
  double x = 0.5;
  double y = 0.5;
  double vx = 0;
  double vy = 0;
  double speed = 0;
  double acceleration = 0;
  double confidence = 0;
  bool acquired = false;

  void reset() {
    xFilter.reset();
    yFilter.reset();
    capturedAt = null;
    seenAt = Duration.zero;
    x = 0.5;
    y = 0.5;
    vx = 0;
    vy = 0;
    speed = 0;
    acceleration = 0;
    confidence = 0;
    acquired = false;
  }
}

/// Converts raw landmarks into low-latency, predicted bilateral motion.
///
/// The processor owns the only smoothing stage. It uses independent One Euro
/// filters, confidence hysteresis, short prediction and graceful occlusion.
class KineticMotionProcessor {
  KineticMotionProcessor({Duration Function()? clock}) : _readClock = clock {
    if (clock == null) _clock.start();
  }

  static const _acquireConfidence = 0.40;
  static const _retainConfidence = 0.20;
  static const _holdDuration = Duration(milliseconds: 120);
  static const _dropDuration = Duration(milliseconds: 420);
  static const _eventCooldown = Duration(milliseconds: 600);
  static const _eventDisplayDuration = Duration(milliseconds: 220);

  final Stopwatch _clock = Stopwatch();
  final Duration Function()? _readClock;
  final Map<KineticLandmarkId, _LandmarkTrack> _tracks =
      <KineticLandmarkId, _LandmarkTrack>{};
  Duration _lastEventAt = Duration.zero;
  Duration? _stillSince;
  double _shoulderSpan = 0.32;
  double _previousSeparation = 0;
  double _previousAngle = 0;
  Duration? _previousPairAt;
  bool _wasOpen = false;
  bool _wasGathered = false;
  bool _wasCrossed = false;
  double _pairOrderSign = 0;
  int _eventSequence = 0;
  KineticMotionEvent _event = KineticMotionEvent.none;

  Duration get _now => _readClock?.call() ?? _clock.elapsed;

  /// Ingests one raw platform frame.
  void ingest(KineticInputFrame input) {
    final frame = input.normalised();
    final now = _now;
    for (final observation in frame.landmarks) {
      final track = _tracks.putIfAbsent(
        observation.id,
        () => _LandmarkTrack(observation.id),
      );
      final threshold = track.acquired ? _retainConfidence : _acquireConfidence;
      if (observation.confidence < threshold) continue;

      final previousCapturedAt = track.capturedAt;
      final elapsedMicros = previousCapturedAt == null
          ? 0
          : frame.capturedAt.inMicroseconds - previousCapturedAt.inMicroseconds;
      final deltaSeconds =
          (elapsedMicros / Duration.microsecondsPerSecond).clamp(1 / 120, 0.12);
      final previousX = track.x;
      final previousY = track.y;
      final previousSpeed = track.speed;
      final directPointer = frame.kind == KineticInputKind.pointer;
      track.x = directPointer
          ? observation.x
          : track.xFilter.update(observation.x, deltaSeconds);
      track.y = directPointer
          ? observation.y
          : track.yFilter.update(observation.y, deltaSeconds);
      final measuredVx = previousCapturedAt == null
          ? 0.0
          : (track.x - previousX) / deltaSeconds;
      final measuredVy = previousCapturedAt == null
          ? 0.0
          : (track.y - previousY) / deltaSeconds;
      final velocityResponse = directPointer ? 1.0 : 0.58;
      track.vx += (measuredVx - track.vx) * velocityResponse;
      track.vy += (measuredVy - track.vy) * velocityResponse;
      track.speed = math.sqrt(track.vx * track.vx + track.vy * track.vy);
      track.acceleration = previousCapturedAt == null
          ? 0
          : ((track.speed - previousSpeed).abs() / deltaSeconds)
              .clamp(0.0, 12.0);
      track.confidence = observation.confidence;
      track.capturedAt = frame.capturedAt;
      track.seenAt = now;
      track.acquired = true;
    }

    final leftShoulder = _tracks[KineticLandmarkId.leftShoulder];
    final rightShoulder = _tracks[KineticLandmarkId.rightShoulder];
    if (leftShoulder != null &&
        rightShoulder != null &&
        leftShoulder.acquired &&
        rightShoulder.acquired) {
      final span = (leftShoulder.x - rightShoulder.x).abs();
      if (span >= 0.08 && span <= 0.75) {
        _shoulderSpan += (span - _shoulderSpan) * 0.18;
      }
    }
  }

  /// Samples a display-ready state with prediction capped at 50 milliseconds.
  KineticMotionState sample([Duration? displayTime]) {
    final now = _now;
    final sampledAt = displayTime ?? now;
    final left = _resolveEffector(
      KineticLandmarkId.leftWrist,
      KineticLandmarkId.primaryPointer,
      now,
    );
    final right = _resolveEffector(
      KineticLandmarkId.rightWrist,
      KineticLandmarkId.secondaryPointer,
      now,
    );
    final leftVisible = left.isVisible;
    final rightVisible = right.isVisible;
    final visibleCount = (leftVisible ? 1 : 0) + (rightVisible ? 1 : 0);
    final midpointX = visibleCount == 0
        ? 0.5
        : ((leftVisible ? left.x : 0) + (rightVisible ? right.x : 0)) /
            visibleCount;
    final midpointY = visibleCount == 0
        ? 0.5
        : ((leftVisible ? left.y : 0) + (rightVisible ? right.y : 0)) /
            visibleCount;

    var separation = 0.0;
    var separationVelocity = 0.0;
    var angularVelocity = 0.0;
    if (leftVisible && rightVisible) {
      final dx = right.x - left.x;
      final dy = right.y - left.y;
      separation = math.sqrt(dx * dx + dy * dy);
      final angle = math.atan2(dy, dx);
      final previousPairAt = _previousPairAt;
      if (previousPairAt != null) {
        final deltaSeconds = ((now - previousPairAt).inMicroseconds /
                Duration.microsecondsPerSecond)
            .clamp(1 / 120, 0.12);
        separationVelocity = (separation - _previousSeparation) / deltaSeconds;
        var angleDelta = angle - _previousAngle;
        if (angleDelta > math.pi) angleDelta -= math.pi * 2;
        if (angleDelta < -math.pi) angleDelta += math.pi * 2;
        angularVelocity = angleDelta / deltaSeconds;
      }
      _previousSeparation = separation;
      _previousAngle = angle;
      _previousPairAt = now;
    } else {
      _previousPairAt = null;
    }

    final energy = visibleCount == 0
        ? 0.0
        : ((leftVisible ? left.energy : 0) +
                (rightVisible ? right.energy : 0)) /
            visibleCount;
    _deriveEvent(
      now: now,
      left: left,
      right: right,
      separation: separation,
      separationVelocity: separationVelocity,
      energy: energy,
    );

    return KineticMotionState(
      sampledAt: sampledAt,
      left: left,
      right: right,
      midpointX: midpointX,
      midpointY: midpointY,
      separation: separation,
      separationVelocity: separationVelocity,
      angularVelocity: angularVelocity,
      energy: energy.clamp(0.0, 1.0),
      shoulderSpan: _shoulderSpan,
      eventSequence: _eventSequence,
      event: _event,
    );
  }

  KineticEffectorState _resolveEffector(
    KineticLandmarkId preferred,
    KineticLandmarkId fallback,
    Duration now,
  ) {
    final track = _tracks[preferred] ?? _tracks[fallback];
    if (track == null || !track.acquired) {
      return KineticEffectorState.idle(preferred);
    }
    final age = now - track.seenAt;
    if (age >= _dropDuration) {
      track.acquired = false;
      return KineticEffectorState.idle(preferred);
    }
    final fade = age <= _holdDuration
        ? 1.0
        : 1 -
            (age.inMicroseconds - _holdDuration.inMicroseconds) /
                (_dropDuration.inMicroseconds - _holdDuration.inMicroseconds);
    final isPointer = track.id == KineticLandmarkId.primaryPointer ||
        track.id == KineticLandmarkId.secondaryPointer;
    final predictionSeconds = isPointer
        ? 0.0
        : (age.inMicroseconds / Duration.microsecondsPerSecond + 0.016).clamp(
            0.0,
            0.05,
          );
    return KineticEffectorState(
      id: track.id,
      x: (track.x + track.vx * predictionSeconds).clamp(0.0, 1.0),
      y: (track.y + track.vy * predictionSeconds).clamp(0.0, 1.0),
      vx: track.vx.clamp(-12.0, 12.0),
      vy: track.vy.clamp(-12.0, 12.0),
      speed: track.speed.clamp(0.0, 12.0),
      acceleration: track.acceleration,
      confidence: track.confidence,
      freshness: fade.clamp(0.0, 1.0),
    );
  }

  void _deriveEvent({
    required Duration now,
    required KineticEffectorState left,
    required KineticEffectorState right,
    required double separation,
    required double separationVelocity,
    required double energy,
  }) {
    if (_event != KineticMotionEvent.none &&
        now - _lastEventAt >= _eventDisplayDuration) {
      _event = KineticMotionEvent.none;
    }
    final bothVisible = left.isVisible && right.isVisible;
    if (!bothVisible) {
      _stillSince = null;
      return;
    }
    final normalisedSeparation = separation / math.max(_shoulderSpan, 0.12);
    final isOpen = normalisedSeparation > 1.45;
    final isGathered = normalisedSeparation < 0.70;
    final isCrossed = _isCrossed(
      now: now,
      left: left,
      right: right,
    );
    final isStill = left.speed < 0.05 && right.speed < 0.05;
    _stillSince = isStill ? (_stillSince ?? now) : null;

    if (now - _lastEventAt < _eventCooldown) {
      _wasOpen = isOpen;
      _wasGathered = isGathered;
      _wasCrossed = isCrossed;
      return;
    }

    KineticMotionEvent next = KineticMotionEvent.none;
    if (isCrossed != _wasCrossed) {
      next = KineticMotionEvent.cross;
    } else if (isOpen && !_wasOpen) {
      next = KineticMotionEvent.open;
    } else if (isGathered && !_wasGathered) {
      next = KineticMotionEvent.gather;
    } else if (left.vy < -0.45 && right.vy < -0.45 && energy > 0.18) {
      next = KineticMotionEvent.lift;
    } else if (_stillSince != null &&
        now - _stillSince! >= const Duration(milliseconds: 650)) {
      next = KineticMotionEvent.settle;
      _stillSince = now;
    } else if (separationVelocity.abs() > 2.8) {
      next = separationVelocity > 0
          ? KineticMotionEvent.open
          : KineticMotionEvent.gather;
    }

    _wasOpen = isOpen;
    _wasGathered = isGathered;
    _wasCrossed = isCrossed;
    if (next == KineticMotionEvent.none) return;
    _event = next;
    _eventSequence += 1;
    _lastEventAt = now;
  }

  bool _isCrossed({
    required Duration now,
    required KineticEffectorState left,
    required KineticEffectorState right,
  }) {
    final shoulderOrder = _trackedShoulderOrder(now);
    if (shoulderOrder != null) {
      _pairOrderSign = shoulderOrder;
    }

    final wristOrder = right.x - left.x;
    if (_pairOrderSign == 0 && wristOrder.abs() >= 0.02) {
      _pairOrderSign = wristOrder.sign;
    }
    if (_pairOrderSign == 0 || wristOrder.abs() < 0.02) {
      return _wasCrossed;
    }
    return wristOrder.sign != _pairOrderSign;
  }

  double? _trackedShoulderOrder(Duration now) {
    final left = _tracks[KineticLandmarkId.leftShoulder];
    final right = _tracks[KineticLandmarkId.rightShoulder];
    if (left == null ||
        right == null ||
        !left.acquired ||
        !right.acquired ||
        now - left.seenAt >= _dropDuration ||
        now - right.seenAt >= _dropDuration) {
      return null;
    }
    final order = right.x - left.x;
    return order.abs() < 0.04 ? null : order.sign;
  }

  /// Immediately removes a landmark without waiting for occlusion fade-out.
  void removeLandmark(KineticLandmarkId id) {
    final track = _tracks.remove(id);
    if (track == null) return;
    track.reset();
    if (id == KineticLandmarkId.leftWrist ||
        id == KineticLandmarkId.rightWrist ||
        id == KineticLandmarkId.primaryPointer ||
        id == KineticLandmarkId.secondaryPointer) {
      _previousPairAt = null;
      _stillSince = null;
    }
  }

  void reset() {
    for (final track in _tracks.values) {
      track.reset();
    }
    _tracks.clear();
    _lastEventAt = Duration.zero;
    _stillSince = null;
    _shoulderSpan = 0.32;
    _previousSeparation = 0;
    _previousAngle = 0;
    _previousPairAt = null;
    _wasOpen = false;
    _wasGathered = false;
    _wasCrossed = false;
    _pairOrderSign = 0;
    _eventSequence = 0;
    _event = KineticMotionEvent.none;
  }

  void dispose() {
    if (_clock.isRunning) _clock.stop();
    reset();
  }
}
