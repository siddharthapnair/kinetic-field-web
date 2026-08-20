part of '../kinetic_field.dart';

/// Controls the particle budget used by [KineticFieldView].
enum KineticQuality {
  /// A smaller field for older or thermally constrained devices.
  low,

  /// A balanced field suitable for most phones, tablets and desktops.
  automatic,

  /// A denser field for powerful devices and large displays.
  high,
}

/// Built-in play worlds. Each scene has its own interaction strategy and
/// renderer, rather than being a colour preset for the same particle effect.
enum KineticScene {
  bloom,
  honeybees,
  fireflies,
  moonPond,
}

/// A normalised motion observation supplied to [KineticFieldController].
///
/// [x] and [y] use the inclusive `0..1` viewport range. Velocities are measured
/// in normalised viewport units per nominal 60 Hz frame. [timestamp] may use
/// any monotonic epoch, but consecutive samples should share that epoch.
@immutable
class MotionSample {
  /// Creates a motion observation.
  const MotionSample({
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
    this.energy = 0,
    this.confidence = 1,
    required this.timestamp,
  });

  /// A centred sample with no active motion.
  static const idle = MotionSample(
    x: 0.5,
    y: 0.5,
    timestamp: Duration.zero,
  );

  /// Horizontal position in the normalised viewport.
  final double x;

  /// Vertical position in the normalised viewport.
  final double y;

  /// Horizontal velocity in normalised viewport units per nominal frame.
  final double vx;

  /// Vertical velocity in normalised viewport units per nominal frame.
  final double vy;

  /// Motion intensity in the `0..1` range.
  final double energy;

  /// Reliability of this observation in the `0..1` range.
  final double confidence;

  /// Monotonic source timestamp retained for velocity calculations and fusion.
  final Duration timestamp;

  /// Returns a copy with selected values replaced.
  MotionSample copyWith({
    double? x,
    double? y,
    double? vx,
    double? vy,
    double? energy,
    double? confidence,
    Duration? timestamp,
  }) {
    return MotionSample(
      x: x ?? this.x,
      y: y ?? this.y,
      vx: vx ?? this.vx,
      vy: vy ?? this.vy,
      energy: energy ?? this.energy,
      confidence: confidence ?? this.confidence,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Produces a finite sample bounded to safe rendering limits.
  MotionSample normalised() {
    return MotionSample(
      x: _finiteOr(x, 0.5).clamp(0.0, 1.0),
      y: _finiteOr(y, 0.5).clamp(0.0, 1.0),
      vx: _finiteOr(vx, 0).clamp(-1.0, 1.0),
      vy: _finiteOr(vy, 0).clamp(-1.0, 1.0),
      energy: _finiteOr(energy, 0).clamp(0.0, 1.0),
      confidence: _finiteOr(confidence, 0).clamp(0.0, 1.0),
      timestamp: timestamp,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MotionSample &&
            x == other.x &&
            y == other.y &&
            vx == other.vx &&
            vy == other.vy &&
            energy == other.energy &&
            confidence == other.confidence &&
            timestamp == other.timestamp;
  }

  @override
  int get hashCode => Object.hash(x, y, vx, vy, energy, confidence, timestamp);

  @override
  String toString() {
    return 'MotionSample(x: $x, y: $y, vx: $vx, vy: $vy, '
        'energy: $energy, confidence: $confidence, timestamp: $timestamp)';
  }
}

/// Visual and performance controls for [KineticFieldView].
@immutable
class KineticFieldSettings {
  /// Creates a field configuration.
  const KineticFieldSettings({
    this.force = 1.18,
    this.radius = 0.30,
    this.swirl = 1.22,
    this.turbulence = 0.68,
    this.pointSize = 1.7,
    this.colourSpeed = 0.52,
    this.depth = 1.0,
    this.trails = 0.86,
    this.scene = KineticScene.bloom,
    this.quality = KineticQuality.automatic,
    this.calm = false,
  });

  /// Strength of local displacement around the interaction point.
  final double force;

  /// Interaction radius in normalised viewport-height units.
  final double radius;

  /// Tangential force applied around the interaction point.
  final double swirl;

  /// Fine spatial variation applied near active motion.
  final double turbulence;

  /// Base particle diameter in logical pixels.
  final double pointSize;

  /// Rate of autonomous colour drift.
  final double colourSpeed;

  /// Strength of procedural perspective and near/far displacement.
  final double depth;

  /// Amount of motion echo applied to the reactive particle subset.
  final double trails;

  /// Active play world and scene-specific interaction strategy.
  final KineticScene scene;

  /// Particle budget preset.
  final KineticQuality quality;

  /// Whether autonomous motion and response intensity should be reduced.
  final bool calm;

  /// Returns a copy with selected values replaced.
  KineticFieldSettings copyWith({
    double? force,
    double? radius,
    double? swirl,
    double? turbulence,
    double? pointSize,
    double? colourSpeed,
    double? depth,
    double? trails,
    KineticScene? scene,
    KineticQuality? quality,
    bool? calm,
  }) {
    return KineticFieldSettings(
      force: force ?? this.force,
      radius: radius ?? this.radius,
      swirl: swirl ?? this.swirl,
      turbulence: turbulence ?? this.turbulence,
      pointSize: pointSize ?? this.pointSize,
      colourSpeed: colourSpeed ?? this.colourSpeed,
      depth: depth ?? this.depth,
      trails: trails ?? this.trails,
      scene: scene ?? this.scene,
      quality: quality ?? this.quality,
      calm: calm ?? this.calm,
    );
  }

  /// Produces a finite configuration bounded to safe rendering limits.
  KineticFieldSettings normalised() {
    return KineticFieldSettings(
      force: _finiteOr(force, 1.18).clamp(0.0, 3.0),
      radius: _finiteOr(radius, 0.30).clamp(0.04, 1.0),
      swirl: _finiteOr(swirl, 1.22).clamp(0.0, 3.0),
      turbulence: _finiteOr(turbulence, 0.68).clamp(0.0, 2.0),
      pointSize: _finiteOr(pointSize, 1.7).clamp(0.5, 6.0),
      colourSpeed: _finiteOr(colourSpeed, 0.52).clamp(0.0, 3.0),
      depth: _finiteOr(depth, 1.0).clamp(0.0, 1.5),
      trails: _finiteOr(trails, 0.86).clamp(0.0, 1.0),
      scene: scene,
      quality: quality,
      calm: calm,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is KineticFieldSettings &&
            force == other.force &&
            radius == other.radius &&
            swirl == other.swirl &&
            turbulence == other.turbulence &&
            pointSize == other.pointSize &&
            colourSpeed == other.colourSpeed &&
            depth == other.depth &&
            trails == other.trails &&
            scene == other.scene &&
            quality == other.quality &&
            calm == other.calm;
  }

  @override
  int get hashCode => Object.hash(
        force,
        radius,
        swirl,
        turbulence,
        pointSize,
        colourSpeed,
        depth,
        trails,
        scene,
        quality,
        calm,
      );
}

/// Runtime performance information emitted by [KineticFieldView].
@immutable
class KineticFieldStats {
  /// Creates a performance sample.
  const KineticFieldStats({
    required this.fps,
    required this.particleCount,
    required this.averageFrameTime,
  });

  /// Initial empty performance state.
  static const zero = KineticFieldStats(
    fps: 0,
    particleCount: 0,
    averageFrameTime: Duration.zero,
  );

  /// Approximate rendered frames per second over the last reporting window.
  final int fps;

  /// Number of particles in the current viewport and quality mode.
  final int particleCount;

  /// Mean ticker interval over the last reporting window.
  final Duration averageFrameTime;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is KineticFieldStats &&
            fps == other.fps &&
            particleCount == other.particleCount &&
            averageFrameTime == other.averageFrameTime;
  }

  @override
  int get hashCode => Object.hash(fps, particleCount, averageFrameTime);
}

double _finiteOr(double value, double fallback) {
  return value.isFinite ? value : fallback;
}
