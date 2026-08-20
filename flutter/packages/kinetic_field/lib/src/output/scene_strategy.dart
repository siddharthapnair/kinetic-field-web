part of '../../kinetic_field.dart';

/// One processed force emitter consumed by a visual scene.
@immutable
class KineticEmitterState {
  const KineticEmitterState({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.force,
    required this.radius,
    required this.spin,
    required this.confidence,
  });

  const KineticEmitterState.idle()
      : x = 0.5,
        y = 0.5,
        vx = 0,
        vy = 0,
        force = 0,
        radius = 0.2,
        spin = 0,
        confidence = 0;

  final double x;
  final double y;
  final double vx;
  final double vy;
  final double force;
  final double radius;
  final double spin;
  final double confidence;

  bool get isActive => confidence >= 0.08 && force > 0;
}

/// Compact visual output from a scene strategy.
@immutable
class KineticSceneFrame {
  const KineticSceneFrame({
    required this.left,
    required this.right,
    required this.tension,
    required this.depthPulse,
    required this.trailAmount,
    required this.huePhase,
    required this.burstEnvelope,
  });

  final KineticEmitterState left;
  final KineticEmitterState right;
  final double tension;
  final double depthPulse;
  final double trailAmount;
  final double huePhase;
  final double burstEnvelope;

  Iterable<KineticEmitterState> get activeEmitters sync* {
    if (left.isActive) yield left;
    if (right.isActive) yield right;
  }
}

/// Maps stable motion into scene-specific force, depth and trail values.
abstract interface class KineticSceneStrategy {
  const KineticSceneStrategy();

  KineticSceneFrame evaluate(
    KineticMotionState motion,
    KineticFieldSettings settings,
    Duration time,
  );
}

KineticSceneStrategy _strategyFor(KineticScene scene) => switch (scene) {
      KineticScene.bloom => const BloomSceneStrategy(),
      KineticScene.honeybees => const HoneybeeSceneStrategy(),
      KineticScene.fireflies => const FireflySceneStrategy(),
      KineticScene.moonPond => const MoonPondSceneStrategy(),
    };

KineticEmitterState _emitterFrom(
  KineticEffectorState point,
  KineticFieldSettings settings, {
  required double forceScale,
  required double radiusScale,
  required double spinDirection,
}) {
  if (!point.isVisible) return const KineticEmitterState.idle();
  final response = settings.calm ? 0.58 : 1.0;
  return KineticEmitterState(
    x: point.x,
    y: point.y,
    vx: point.vx.clamp(-3.0, 3.0),
    vy: point.vy.clamp(-3.0, 3.0),
    force: settings.force * forceScale * response * (0.38 + point.energy * 0.9),
    radius: (settings.radius * radiusScale).clamp(0.08, 0.72),
    spin: settings.swirl * spinDirection * response,
    confidence: point.confidence * point.freshness,
  );
}

double _burstFor(KineticMotionState motion) => switch (motion.event) {
      KineticMotionEvent.open => 0.86,
      KineticMotionEvent.gather => 1,
      KineticMotionEvent.lift => 0.92,
      KineticMotionEvent.cross => 0.78,
      KineticMotionEvent.settle => 0.55,
      KineticMotionEvent.none => 0,
    };

class BloomSceneStrategy implements KineticSceneStrategy {
  const BloomSceneStrategy();

  @override
  KineticSceneFrame evaluate(
    KineticMotionState motion,
    KineticFieldSettings settings,
    Duration time,
  ) {
    final separation = motion.separation / math.max(motion.shoulderSpan, 0.12);
    return KineticSceneFrame(
      left: _emitterFrom(
        motion.left,
        settings,
        forceScale: 1.05,
        radiusScale: 1.05,
        spinDirection: 1,
      ),
      right: _emitterFrom(
        motion.right,
        settings,
        forceScale: 1.05,
        radiusScale: 1.05,
        spinDirection: -1,
      ),
      tension: (separation / 1.6).clamp(0.0, 1.0),
      depthPulse: (motion.energy * 0.75 +
              (motion.event == KineticMotionEvent.gather ? 0.8 : 0))
          .clamp(0.0, 1.0),
      trailAmount: settings.trails * (0.42 + motion.energy * 0.58),
      huePhase: 0.12,
      burstEnvelope: _burstFor(motion),
    );
  }
}

class HoneybeeSceneStrategy implements KineticSceneStrategy {
  const HoneybeeSceneStrategy();

  @override
  KineticSceneFrame evaluate(
    KineticMotionState motion,
    KineticFieldSettings settings,
    Duration time,
  ) {
    return KineticSceneFrame(
      left: _emitterFrom(
        motion.left,
        settings,
        forceScale: 0.82,
        radiusScale: 0.82,
        spinDirection: 0.55,
      ),
      right: _emitterFrom(
        motion.right,
        settings,
        forceScale: 0.82,
        radiusScale: 0.82,
        spinDirection: -0.55,
      ),
      tension: (motion.separation / 0.72).clamp(0.0, 1.0),
      depthPulse: (motion.energy * 0.46).clamp(0.0, 1.0),
      trailAmount: settings.trails * (0.7 + motion.energy * 0.3),
      huePhase: 0.20,
      burstEnvelope: _burstFor(motion) * 0.72,
    );
  }
}

class FireflySceneStrategy implements KineticSceneStrategy {
  const FireflySceneStrategy();

  @override
  KineticSceneFrame evaluate(
    KineticMotionState motion,
    KineticFieldSettings settings,
    Duration time,
  ) {
    return KineticSceneFrame(
      left: _emitterFrom(
        motion.left,
        settings,
        forceScale: 0.72,
        radiusScale: 1.22,
        spinDirection: 0.36,
      ),
      right: _emitterFrom(
        motion.right,
        settings,
        forceScale: 0.72,
        radiusScale: 1.22,
        spinDirection: -0.36,
      ),
      tension: (motion.separation / 0.85).clamp(0.0, 1.0),
      depthPulse: (motion.event == KineticMotionEvent.settle ? 0.82 : 0.25),
      trailAmount: settings.trails * (0.58 + motion.energy * 0.34),
      huePhase: 0.57,
      burstEnvelope: _burstFor(motion) * 0.64,
    );
  }
}

class MoonPondSceneStrategy implements KineticSceneStrategy {
  const MoonPondSceneStrategy();

  @override
  KineticSceneFrame evaluate(
    KineticMotionState motion,
    KineticFieldSettings settings,
    Duration time,
  ) {
    final stillness = (1 - motion.energy * 2.5).clamp(0.0, 1.0);
    return KineticSceneFrame(
      left: _emitterFrom(
        motion.left,
        settings,
        forceScale: 0.58,
        radiusScale: 1.12,
        spinDirection: 0.22,
      ),
      right: _emitterFrom(
        motion.right,
        settings,
        forceScale: 0.58,
        radiusScale: 1.12,
        spinDirection: -0.22,
      ),
      tension: stillness,
      depthPulse: (motion.energy * 0.38).clamp(0.0, 1.0),
      trailAmount: settings.trails * 0.42,
      huePhase: 0.72,
      burstEnvelope: _burstFor(motion) * 0.34,
    );
  }
}
