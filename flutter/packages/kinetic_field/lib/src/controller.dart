part of '../kinetic_field.dart';

/// Owns motion, settings and performance state for a [KineticFieldView].
///
/// The controller performs no camera or sensor access. Platform applications
/// remain responsible for producing [MotionSample] values and may therefore
/// use a camera, pose model, accelerometer, remote stream or any other source.
class KineticFieldController extends ChangeNotifier {
  /// Creates a controller with optional initial state.
  KineticFieldController({
    KineticFieldSettings settings = const KineticFieldSettings(),
    MotionSample? motion,
  })  : _settings = settings.normalised(),
        _motion = (motion ?? MotionSample.idle).normalised() {
    _arrivalClock.start();
  }

  final Stopwatch _arrivalClock = Stopwatch();
  Duration _motionArrivedAt = Duration.zero;
  MotionSample? _lastPointer;
  MotionSample _motion;
  KineticFieldSettings _settings;
  KineticFieldStats _stats = KineticFieldStats.zero;

  /// Most recent finite, bounded motion observation.
  MotionSample get motion => _motion;

  /// Current finite, bounded field configuration.
  KineticFieldSettings get settings => _settings;

  /// Most recent performance report from the attached field.
  KineticFieldStats get stats => _stats;

  Duration get _motionAge {
    final age = _arrivalClock.elapsed - _motionArrivedAt;
    return age.isNegative ? Duration.zero : age;
  }

  /// Replaces the current motion observation.
  void updateMotion(MotionSample sample) {
    _lastPointer = null;
    _setMotion(sample.normalised());
  }

  /// Replaces the current settings.
  void updateSettings(KineticFieldSettings settings) {
    final next = settings.normalised();
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
  }

  /// Converts a normalised pointer position into a bounded motion sample.
  ///
  /// Supplying [timestamp] is recommended when forwarding a Flutter
  /// `PointerEvent.timeStamp`. When omitted, the controller uses its own
  /// monotonic clock.
  void updatePointer({
    required double x,
    required double y,
    Duration? timestamp,
    double confidence = 1,
  }) {
    final nextTimestamp = timestamp ?? _arrivalClock.elapsed;
    final nextX = _finiteOr(x, 0.5).clamp(0.0, 1.0);
    final nextY = _finiteOr(y, 0.5).clamp(0.0, 1.0);
    final previous = _lastPointer;

    var vx = 0.0;
    var vy = 0.0;
    var energy = 0.16;
    if (previous != null) {
      final elapsedMicros =
          nextTimestamp.inMicroseconds - previous.timestamp.inMicroseconds;
      final elapsedMillis = math.max(8.0, elapsedMicros / 1000);
      final frameScale = 16.667 / elapsedMillis;
      vx = ((nextX - previous.x) * frameScale).clamp(-0.18, 0.18);
      vy = ((nextY - previous.y) * frameScale).clamp(-0.18, 0.18);
      energy = (math.sqrt(vx * vx + vy * vy) * 7.5).clamp(0.16, 1.0);
    }

    final next = MotionSample(
      x: nextX,
      y: nextY,
      vx: vx,
      vy: vy,
      energy: energy,
      confidence: _finiteOr(confidence, 0).clamp(0.0, 1.0),
      timestamp: nextTimestamp,
    );
    _lastPointer = next;
    _setMotion(next);
  }

  /// Restores a centred, inactive motion sample.
  void resetMotion() {
    _lastPointer = null;
    _setMotion(MotionSample.idle.copyWith(timestamp: _arrivalClock.elapsed));
  }

  /// Restores the default field configuration.
  void resetSettings() {
    updateSettings(const KineticFieldSettings());
  }

  void _setMotion(MotionSample next) {
    _motion = next;
    _motionArrivedAt = _arrivalClock.elapsed;
    notifyListeners();
  }

  void _updateStats(KineticFieldStats next) {
    if (next == _stats) return;
    _stats = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _arrivalClock.stop();
    super.dispose();
  }
}
