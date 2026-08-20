part of '../kinetic_field.dart';

class _PointerObservation {
  const _PointerObservation(this.landmarkId, this.x, this.y, this.confidence);

  final KineticLandmarkId landmarkId;
  final double x;
  final double y;
  final double confidence;
}

/// Owns input, processed motion, settings and performance state.
///
/// Platform code supplies raw [KineticInputFrame] values. The controller keeps
/// acquisition separate from [KineticMotionProcessor] and the visual output,
/// allowing camera, pointer or native sources to be replaced independently.
class KineticFieldController extends ChangeNotifier {
  KineticFieldController({
    KineticFieldSettings settings = const KineticFieldSettings(),
    MotionSample? motion,
    KineticMotionProcessor? motionProcessor,
  })  : _settings = settings.normalised(),
        _motion = (motion ?? MotionSample.idle).normalised(),
        _motionProcessor = motionProcessor ?? KineticMotionProcessor(),
        _ownsMotionProcessor = motionProcessor == null {
    _arrivalClock.start();
    if (motion != null) _motionState = _legacyState(_motion);
  }

  final Stopwatch _arrivalClock = Stopwatch();
  final KineticMotionProcessor _motionProcessor;
  final bool _ownsMotionProcessor;
  final Map<int, _PointerObservation> _pointers = <int, _PointerObservation>{};
  MotionSample _motion;
  KineticMotionState _motionState = KineticMotionState.idle;
  KineticFieldSettings _settings;
  KineticFieldStats _stats = KineticFieldStats.zero;
  int _inputSequence = 0;
  bool _usesProcessedInput = false;

  MotionSample get motion => _motion;

  /// Latest filtered bilateral state shared by visual and audio outputs.
  KineticMotionState get motionState => _motionState;

  KineticFieldSettings get settings => _settings;

  KineticFieldStats get stats => _stats;

  /// Sends a raw, versioned input packet through the motion processor.
  void ingestFrame(KineticInputFrame frame) {
    _usesProcessedInput = true;
    for (final pointer in _pointers.values) {
      _motionProcessor.removeLandmark(pointer.landmarkId);
    }
    _pointers.clear();
    _motionProcessor.ingest(frame);
    _motionState = _motionProcessor.sample();
    _motion = _compatibilitySample(_motionState, frame.capturedAt);
    notifyListeners();
  }

  /// Backwards-compatible single-effector input.
  ///
  /// New integrations should use [ingestFrame] so filtering, prediction and
  /// bilateral features remain consistent across platforms.
  void updateMotion(MotionSample sample) {
    _usesProcessedInput = false;
    _pointers.clear();
    _motionProcessor.reset();
    _motion = sample.normalised();
    _motionState = _legacyState(_motion);
    notifyListeners();
  }

  void updateSettings(KineticFieldSettings settings) {
    final next = settings.normalised();
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
  }

  /// Updates one pointer. Two concurrent touch or stylus pointers remain
  /// independent effectors; a mouse remains a complete one-effector input.
  void updatePointer({
    required double x,
    required double y,
    Duration? timestamp,
    double confidence = 1,
    int pointerId = 0,
  }) {
    _usesProcessedInput = true;
    final nextTimestamp = timestamp ?? _arrivalClock.elapsed;
    final existing = _pointers[pointerId];
    final landmarkId = existing?.landmarkId ?? _availablePointerLandmark();
    if (landmarkId == null) return;
    _pointers[pointerId] = _PointerObservation(
      landmarkId,
      _finiteOr(x, 0.5).clamp(0.0, 1.0),
      _finiteOr(y, 0.5).clamp(0.0, 1.0),
      _finiteOr(confidence, 0).clamp(0.0, 1.0),
    );
    _ingestPointers(nextTimestamp);
  }

  /// Removes a touch or stylus effector when its pointer leaves the surface.
  void removePointer(int pointerId, {Duration? timestamp}) {
    final pointer = _pointers.remove(pointerId);
    if (pointer == null) return;
    _motionProcessor.removeLandmark(pointer.landmarkId);
    _ingestPointers(timestamp ?? _arrivalClock.elapsed);
  }

  KineticLandmarkId? _availablePointerLandmark() {
    var primaryInUse = false;
    var secondaryInUse = false;
    for (final pointer in _pointers.values) {
      primaryInUse |= pointer.landmarkId == KineticLandmarkId.primaryPointer;
      secondaryInUse |=
          pointer.landmarkId == KineticLandmarkId.secondaryPointer;
    }
    if (!primaryInUse) return KineticLandmarkId.primaryPointer;
    if (!secondaryInUse) return KineticLandmarkId.secondaryPointer;
    return null;
  }

  void _ingestPointers(Duration timestamp) {
    final landmarks = <KineticLandmarkObservation>[];
    for (final pointer in _pointers.values) {
      landmarks.add(
        KineticLandmarkObservation(
          id: pointer.landmarkId,
          x: pointer.x,
          y: pointer.y,
          confidence: pointer.confidence,
        ),
      );
    }
    final frame = KineticInputFrame(
      sequence: ++_inputSequence,
      capturedAt: timestamp,
      receivedAt: timestamp,
      kind: KineticInputKind.pointer,
      landmarks: landmarks,
    );
    _motionProcessor.ingest(frame);
    _motionState = _motionProcessor.sample();
    _motion = _compatibilitySample(_motionState, timestamp);
    notifyListeners();
  }

  void resetMotion() {
    _usesProcessedInput = false;
    _pointers.clear();
    _motionProcessor.reset();
    _motion = MotionSample.idle.copyWith(timestamp: _arrivalClock.elapsed);
    _motionState = KineticMotionState.idle;
    notifyListeners();
  }

  void resetSettings() {
    updateSettings(const KineticFieldSettings());
  }

  KineticMotionState _sampleMotion(Duration displayTime) {
    if (!_usesProcessedInput) return _motionState;
    _motionState = _motionProcessor.sample(displayTime);
    _motion = _compatibilitySample(_motionState, displayTime);
    return _motionState;
  }

  void _updateStats(KineticFieldStats next) {
    if (next == _stats) return;
    _stats = next;
    notifyListeners();
  }

  static MotionSample _compatibilitySample(
    KineticMotionState state,
    Duration timestamp,
  ) {
    final leftVisible = state.left.isVisible;
    final rightVisible = state.right.isVisible;
    final visibleCount = (leftVisible ? 1 : 0) + (rightVisible ? 1 : 0);
    if (visibleCount == 0) {
      return MotionSample.idle.copyWith(timestamp: timestamp);
    }
    final vx = ((leftVisible ? state.left.vx : 0) +
            (rightVisible ? state.right.vx : 0)) /
        visibleCount /
        60;
    final vy = ((leftVisible ? state.left.vy : 0) +
            (rightVisible ? state.right.vy : 0)) /
        visibleCount /
        60;
    final confidence =
        ((leftVisible ? state.left.confidence * state.left.freshness : 0) +
                (rightVisible
                    ? state.right.confidence * state.right.freshness
                    : 0)) /
            visibleCount;
    final compatibilityEnergy =
        confidence <= 0.01 ? 0.0 : (state.energy / confidence).clamp(0.0, 1.0);
    return MotionSample(
      x: state.midpointX,
      y: state.midpointY,
      vx: vx.clamp(-0.18, 0.18),
      vy: vy.clamp(-0.18, 0.18),
      energy: math.max(compatibilityEnergy, 0.16),
      confidence: confidence.clamp(0.0, 1.0),
      timestamp: timestamp,
    );
  }

  static KineticMotionState _legacyState(MotionSample sample) {
    final point = KineticEffectorState(
      id: KineticLandmarkId.primaryPointer,
      x: sample.x,
      y: sample.y,
      vx: sample.vx * 60,
      vy: sample.vy * 60,
      speed: math.sqrt(sample.vx * sample.vx + sample.vy * sample.vy) * 60,
      acceleration: 0,
      confidence: sample.confidence,
      freshness: 1,
    );
    return KineticMotionState(
      sampledAt: sample.timestamp,
      left: point,
      right: const KineticEffectorState.idle(
        KineticLandmarkId.rightWrist,
      ),
      midpointX: sample.x,
      midpointY: sample.y,
      separation: 0,
      separationVelocity: 0,
      angularVelocity: 0,
      energy: sample.energy,
      shoulderSpan: 0.32,
      eventSequence: 0,
      event: KineticMotionEvent.none,
    );
  }

  @override
  void dispose() {
    _arrivalClock.stop();
    if (_ownsMotionProcessor) _motionProcessor.dispose();
    super.dispose();
  }
}
