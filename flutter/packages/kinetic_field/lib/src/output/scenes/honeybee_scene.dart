part of '../../../kinetic_field.dart';

class _HoneybeeSceneRenderer implements _KineticSceneRenderer {
  final Map<KineticLandmarkId, List<ui.Offset>> _trails =
      <KineticLandmarkId, List<ui.Offset>>{};
  final Float32List _pollen = Float32List(520 * 2);
  final ui.Paint _paint = ui.Paint()..isAntiAlias = true;

  @override
  void paint(_SceneRenderContext context) {
    _drawMeadow(context);
    _drawPollen(context);
    for (final hand in context.motion.visibleEffectors) {
      final position = context.screenFor(hand);
      final trail = _trails.putIfAbsent(hand.id, () => <ui.Offset>[]);
      if (trail.isEmpty || (trail.last - position).distance > 2) {
        trail.add(position);
      }
      while (trail.length > 22) {
        trail.removeAt(0);
      }
      _drawTrail(context.canvas, trail, hand.energy);
      _drawSwarm(context, hand, position);
      _drawBee(
        context.canvas,
        position,
        math.atan2(hand.vy, hand.vx),
        18 + hand.energy * 7,
        context.time,
      );
    }
    _drawEffectorBridge(
      context,
      colour: const ui.Color(0xFFFFD45A),
      amplitude: 0.25 + context.motion.energy * 0.45,
    );
  }

  void _drawMeadow(_SceneRenderContext context) {
    final canvas = context.canvas;
    final size = context.size;
    final horizon = size.height * 0.78;
    final haze = ui.Gradient.linear(
      ui.Offset(0, horizon),
      ui.Offset(0, size.height),
      const <ui.Color>[ui.Color(0x00151006), ui.Color(0xB322260A)],
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(0, horizon, size.width, size.height - horizon),
      _paint
        ..style = ui.PaintingStyle.fill
        ..blendMode = ui.BlendMode.srcOver
        ..shader = haze,
    );
    _paint.shader = null;
    for (var index = 0; index < 12; index += 1) {
      final x = size.width * (index + 0.45) / 12;
      final top = ui.Offset(
        x + math.sin(index * 2.3) * 9,
        horizon - 18 - _hashUnit(index + 42) * 56,
      );
      canvas.drawLine(
        ui.Offset(x, size.height),
        top,
        _paint
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = _alpha(const ui.Color(0xFF8EAE55), 0.28),
      );
      final flowerColour = index.isEven
          ? const ui.Color(0xFFFFD45A)
          : const ui.Color(0xFFFF8CAB);
      for (var petal = 0; petal < 6; petal += 1) {
        final angle = petal * math.pi / 3;
        final petalCentre =
            top + ui.Offset(math.cos(angle), math.sin(angle)) * 7;
        canvas.drawOval(
          ui.Rect.fromCenter(center: petalCentre, width: 8, height: 4),
          _paint
            ..style = ui.PaintingStyle.fill
            ..blendMode = ui.BlendMode.plus
            ..color = _alpha(flowerColour, 0.36),
        );
      }
      canvas.drawCircle(
        top,
        2.4,
        _paint..color = _alpha(const ui.Color(0xFFFFEFA0), 0.75),
      );
    }
  }

  void _drawPollen(_SceneRenderContext context) {
    final count = context.qualityCount(low: 120, automatic: 280, high: 500);
    for (var index = 0; index < count; index += 1) {
      final depth = 0.45 + _hashUnit(index + 17) * 0.55;
      var x = (_hashUnit(index * 37 + 5) +
              math.sin(context.time * 0.18 + index * 1.7) * 0.018)
          .remainder(1.0);
      var y = (_hashUnit(index * 59 + 11) +
              math.cos(context.time * 0.13 + index) * 0.012)
          .remainder(1.0);
      if (x < 0) x += 1;
      if (y < 0) y += 1;
      _pollen[index * 2] = x * context.size.width;
      _pollen[index * 2 + 1] = y * context.size.height * 0.86;
      if (depth > 0.72) {
        _pollen[index * 2] += math.sin(context.time + index) * 2;
      }
    }
    context.canvas.drawRawPoints(
      ui.PointMode.points,
      Float32List.sublistView(_pollen, 0, count * 2),
      _paint
        ..shader = null
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = context.settings.pointSize * 0.76
        ..blendMode = ui.BlendMode.plus
        ..color = _alpha(const ui.Color(0xFFFFD45A), 0.36),
    );
  }

  void _drawSwarm(
    _SceneRenderContext context,
    KineticEffectorState hand,
    ui.Offset centre,
  ) {
    final count = context.qualityCount(low: 10, automatic: 18, high: 28);
    for (var index = 0; index < count; index += 1) {
      final orbit = 28 + _hashUnit(index + hand.id.index * 91) * 62;
      final angle =
          context.time * (0.65 + _hashUnit(index + 8) * 0.8) + index * 2.399;
      final point = centre +
          ui.Offset(
            math.cos(angle) * orbit,
            math.sin(angle * 1.18) * orbit * 0.48,
          );
      final wing = math.sin(context.time * 18 + index) * 2.5;
      context.canvas.drawLine(
        point - ui.Offset(wing, 0),
        point + ui.Offset(wing, 0),
        _paint
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1
          ..blendMode = ui.BlendMode.plus
          ..color = _alpha(const ui.Color(0xFFFFE88A), 0.48),
      );
      context.canvas.drawCircle(
        point,
        1.2,
        _paint..color = _alpha(const ui.Color(0xFFFFB92F), 0.76),
      );
    }
  }

  void _drawTrail(ui.Canvas canvas, List<ui.Offset> trail, double energy) {
    if (trail.length < 2) return;
    final path = ui.Path()..moveTo(trail.first.dx, trail.first.dy);
    for (var index = 1; index < trail.length; index += 1) {
      path.lineTo(trail[index].dx, trail[index].dy);
    }
    canvas.drawPath(
      path,
      _paint
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = 1.2 + energy * 1.8
        ..blendMode = ui.BlendMode.plus
        ..color = _alpha(const ui.Color(0xFFFFD45A), 0.16 + energy * 0.26),
    );
  }

  void _drawBee(
    ui.Canvas canvas,
    ui.Offset centre,
    double angle,
    double size,
    double time,
  ) {
    final safeAngle = angle.isFinite ? angle : 0.0;
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(safeAngle);
    final wingLift = math.sin(time * 22) * size * 0.08;
    canvas.drawOval(
      ui.Rect.fromCenter(
        center: ui.Offset(-size * 0.08, -size * 0.34 - wingLift),
        width: size * 0.82,
        height: size * 0.48,
      ),
      _paint
        ..style = ui.PaintingStyle.fill
        ..blendMode = ui.BlendMode.plus
        ..color = _alpha(const ui.Color(0xFFCDEFFF), 0.22),
    );
    canvas.drawOval(
      ui.Rect.fromCenter(
        center: ui.Offset(-size * 0.08, size * 0.34 + wingLift),
        width: size * 0.82,
        height: size * 0.48,
      ),
      _paint..color = _alpha(const ui.Color(0xFFCDEFFF), 0.22),
    );
    canvas.drawOval(
      ui.Rect.fromCenter(
        center: ui.Offset.zero,
        width: size * 1.15,
        height: size * 0.58,
      ),
      _paint..color = _alpha(const ui.Color(0xFFFFC63D), 0.86),
    );
    for (var stripe = -1; stripe <= 1; stripe += 1) {
      canvas.drawLine(
        ui.Offset(stripe * size * 0.22, -size * 0.25),
        ui.Offset(stripe * size * 0.22, size * 0.25),
        _paint
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = size * 0.12
          ..strokeCap = ui.StrokeCap.round
          ..color = _alpha(const ui.Color(0xFF382B12), 0.78),
      );
    }
    _drawGlowDot(
      canvas,
      ui.Offset(size * 0.55, 0),
      size * 0.10,
      const ui.Color(0xFFFFE88A),
      0.82,
    );
    canvas.restore();
  }

  @override
  void reset() => _trails.clear();
}
