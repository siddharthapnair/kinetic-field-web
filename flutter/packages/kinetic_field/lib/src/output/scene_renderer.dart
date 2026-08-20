part of '../../kinetic_field.dart';

class _SceneRenderContext {
  const _SceneRenderContext({
    required this.canvas,
    required this.size,
    required this.time,
    required this.deltaSeconds,
    required this.motion,
    required this.frame,
    required this.settings,
    required this.automaticQualityScale,
  });

  final ui.Canvas canvas;
  final ui.Size size;
  final double time;
  final double deltaSeconds;
  final KineticMotionState motion;
  final KineticSceneFrame frame;
  final KineticFieldSettings settings;
  final double automaticQualityScale;

  ui.Offset screenFor(KineticEffectorState point) {
    return ui.Offset(point.x * size.width, point.y * size.height);
  }

  ui.Offset screenForEmitter(KineticEmitterState point) {
    return ui.Offset(point.x * size.width, point.y * size.height);
  }

  double get scale => size.shortestSide / 900;

  int qualityCount({
    required int low,
    required int automatic,
    required int high,
  }) {
    return switch (settings.quality) {
      KineticQuality.low => low,
      KineticQuality.automatic =>
        (automatic * automaticQualityScale.clamp(0.55, 1.0)).round(),
      KineticQuality.high => high,
    };
  }
}

abstract interface class _KineticSceneRenderer {
  void paint(_SceneRenderContext context);

  void reset();
}

class _SceneRendererRegistry {
  final Map<KineticScene, _KineticSceneRenderer> _renderers =
      <KineticScene, _KineticSceneRenderer>{
    KineticScene.bloom: _BloomSceneRenderer(),
    KineticScene.honeybees: _HoneybeeSceneRenderer(),
    KineticScene.fireflies: _FireflySceneRenderer(),
    KineticScene.moonPond: _MoonPondSceneRenderer(),
  };

  _KineticSceneRenderer rendererFor(KineticScene scene) => _renderers[scene]!;

  void reset(KineticScene scene) => _renderers[scene]?.reset();
}

ui.Color _sceneBackground(KineticScene scene) => switch (scene) {
      KineticScene.bloom => const ui.Color(0xFF06110F),
      KineticScene.honeybees => const ui.Color(0xFF151006),
      KineticScene.fireflies => const ui.Color(0xFF070818),
      KineticScene.moonPond => const ui.Color(0xFF04131B),
    };

ui.Color _sceneAccent(KineticScene scene) => switch (scene) {
      KineticScene.bloom => const ui.Color(0xFFFF70B5),
      KineticScene.honeybees => const ui.Color(0xFFFFD45A),
      KineticScene.fireflies => const ui.Color(0xFFB9FF72),
      KineticScene.moonPond => const ui.Color(0xFF68D8E8),
    };

ui.Color _alpha(ui.Color color, double opacity) {
  return color.withAlpha((opacity.clamp(0.0, 1.0) * 255).round());
}

double _hashUnit(int value) {
  var x = value;
  x = ((x >> 16) ^ x) * 0x45d9f3b;
  x = ((x >> 16) ^ x) * 0x45d9f3b;
  x = (x >> 16) ^ x;
  return (x & 0x7fffffff) / 0x7fffffff;
}

void _drawGlowDot(
  ui.Canvas canvas,
  ui.Offset centre,
  double radius,
  ui.Color colour,
  double opacity,
) {
  final paint = ui.Paint()
    ..blendMode = ui.BlendMode.plus
    ..shader = ui.Gradient.radial(
      centre,
      radius * 3.2,
      <ui.Color>[
        _alpha(colour, opacity),
        _alpha(colour, opacity * 0.22),
        _alpha(colour, 0),
      ],
      const <double>[0, 0.34, 1],
    );
  canvas.drawCircle(centre, radius * 3.2, paint);
  paint
    ..shader = null
    ..color = _alpha(colour, math.min(1, opacity * 1.35));
  canvas.drawCircle(centre, math.max(0.8, radius * 0.55), paint);
}

void _drawEffectorBridge(
  _SceneRenderContext context, {
  required ui.Color colour,
  double amplitude = 1,
}) {
  if (!context.motion.left.isVisible || !context.motion.right.isVisible) return;
  final left = context.screenFor(context.motion.left);
  final right = context.screenFor(context.motion.right);
  final midpoint = ui.Offset(
    (left.dx + right.dx) * 0.5,
    (left.dy + right.dy) * 0.5,
  );
  final bend = math.sin(context.time * 2.1) *
      context.size.shortestSide *
      0.035 *
      amplitude;
  final path = ui.Path()
    ..moveTo(left.dx, left.dy)
    ..quadraticBezierTo(midpoint.dx, midpoint.dy + bend, right.dx, right.dy);
  final paint = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..blendMode = ui.BlendMode.plus;
  context.canvas.drawPath(
    path,
    paint
      ..strokeWidth = 7 * context.scale.clamp(0.7, 1.4)
      ..color = _alpha(colour, 0.08 * amplitude),
  );
  context.canvas.drawPath(
    path,
    paint
      ..strokeWidth = 1.3 * context.scale.clamp(0.8, 1.5)
      ..color = _alpha(colour, 0.48 * amplitude),
  );
}
