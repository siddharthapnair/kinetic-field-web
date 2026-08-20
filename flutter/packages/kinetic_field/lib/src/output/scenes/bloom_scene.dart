part of '../../../kinetic_field.dart';

class _BloomSceneRenderer implements _KineticSceneRenderer {
  final Float32List _pollen = Float32List(900 * 2);
  final ui.Paint _paint = ui.Paint()..isAntiAlias = true;

  @override
  void paint(_SceneRenderContext context) {
    _drawGarden(context);
    _drawPollen(context);
    for (final point in context.motion.visibleEffectors) {
      final centre = context.screenFor(point);
      final openness = (0.45 + point.energy * 0.55).clamp(0.0, 1.0);
      _drawFlower(
        context.canvas,
        centre,
        28 + point.energy * 34,
        openness,
        point.id == KineticLandmarkId.rightWrist
            ? const ui.Color(0xFFFFC85F)
            : const ui.Color(0xFFFF70B5),
        context.time,
      );
      context.canvas.drawCircle(
        centre,
        (24 + point.energy * 52) * context.scale.clamp(0.65, 1.3),
        _paint
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..blendMode = ui.BlendMode.plus
          ..color = _alpha(const ui.Color(0xFFFFD6E8), 0.22),
      );
    }
    _drawEffectorBridge(
      context,
      colour: const ui.Color(0xFFFF91C7),
      amplitude: 0.35 + context.frame.tension * 0.65,
    );
  }

  void _drawGarden(_SceneRenderContext context) {
    final canvas = context.canvas;
    final height = context.size.height;
    final width = context.size.width;
    for (var index = 0; index < 9; index += 1) {
      final fraction = (index + 0.5) / 9;
      final base = ui.Offset(width * fraction, height * 1.04);
      final restTop = ui.Offset(
        width * fraction + math.sin(index * 2.7) * 16,
        height * (0.66 + _hashUnit(index + 91) * 0.22),
      );
      var top = restTop;
      var openness = 0.18 + context.frame.tension * 0.22;
      for (final hand in context.motion.visibleEffectors) {
        final handPosition = context.screenFor(hand);
        final distance = (handPosition - restTop).distance;
        final influence =
            (1 - distance / (context.size.shortestSide * 0.42)).clamp(0.0, 1.0);
        top += (handPosition - restTop) * influence * 0.16;
        openness += influence * (0.56 + hand.energy * 0.3);
      }
      final sway = context.settings.calm
          ? 0.0
          : math.sin(context.time * 0.7 + index) * 7;
      final stem = ui.Path()
        ..moveTo(base.dx, base.dy)
        ..cubicTo(
          base.dx + sway,
          height * 0.90,
          top.dx - sway * 0.5,
          top.dy + 38,
          top.dx,
          top.dy,
        );
      canvas.drawPath(
        stem,
        _paint
          ..style = ui.PaintingStyle.stroke
          ..strokeCap = ui.StrokeCap.round
          ..strokeWidth = 1.2 + _hashUnit(index) * 1.4
          ..blendMode = ui.BlendMode.srcOver
          ..color = _alpha(const ui.Color(0xFF78C78B), 0.32),
      );
      if (index.isEven) {
        final leafCentre = ui.Offset.lerp(base, top, 0.56)!;
        canvas.save();
        canvas.translate(leafCentre.dx, leafCentre.dy);
        canvas.rotate(index.isEven ? -0.55 : 0.55);
        canvas.drawOval(
          ui.Rect.fromCenter(
            center: ui.Offset.zero,
            width: 24,
            height: 9,
          ),
          _paint
            ..style = ui.PaintingStyle.fill
            ..color = _alpha(const ui.Color(0xFF7DD69A), 0.24),
        );
        canvas.restore();
      }
      final colour = index % 3 == 0
          ? const ui.Color(0xFFFF70B5)
          : index % 3 == 1
              ? const ui.Color(0xFFFFC85F)
              : const ui.Color(0xFF8BE3D4);
      _drawFlower(
        canvas,
        top,
        11 + _hashUnit(index + 22) * 8,
        openness.clamp(0.12, 1.0),
        colour,
        context.time + index,
      );
    }
  }

  void _drawPollen(_SceneRenderContext context) {
    final count = context.qualityCount(low: 180, automatic: 420, high: 780);
    for (var index = 0; index < count; index += 1) {
      final depth = _hashUnit(index * 13 + 7);
      var x = (_hashUnit(index * 47 + 3) +
              math.sin(context.time * (0.035 + depth * 0.06) + index) * 0.035)
          .remainder(1.0);
      var y =
          (_hashUnit(index * 31 + 9) - context.time * (0.004 + depth * 0.009))
              .remainder(1.0);
      if (x < 0) x += 1;
      if (y < 0) y += 1;
      for (final hand in context.motion.visibleEffectors) {
        final dx = hand.x - x;
        final dy = hand.y - y;
        final influence = (1 - (dx * dx + dy * dy) / 0.12).clamp(0.0, 1.0);
        x += dx * influence * 0.11;
        y += dy * influence * 0.11;
      }
      _pollen[index * 2] = x * context.size.width;
      _pollen[index * 2 + 1] = y * context.size.height;
    }
    final points = Float32List.sublistView(_pollen, 0, count * 2);
    context.canvas.drawRawPoints(
      ui.PointMode.points,
      points,
      _paint
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = context.settings.pointSize * 0.8
        ..strokeCap = ui.StrokeCap.round
        ..blendMode = ui.BlendMode.plus
        ..color = _alpha(const ui.Color(0xFFFFD36B), 0.34),
    );
  }

  void _drawFlower(
    ui.Canvas canvas,
    ui.Offset centre,
    double radius,
    double openness,
    ui.Color colour,
    double time,
  ) {
    final petalCount = 10;
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(time * 0.035);
    for (var index = 0; index < petalCount; index += 1) {
      canvas.save();
      canvas.rotate(index * math.pi * 2 / petalCount);
      final petalLength = radius * (0.48 + openness * 0.72);
      final petalWidth = radius * (0.18 + openness * 0.24);
      canvas.drawOval(
        ui.Rect.fromCenter(
          center: ui.Offset(petalLength * 0.56, 0),
          width: petalLength,
          height: petalWidth,
        ),
        _paint
          ..style = ui.PaintingStyle.fill
          ..blendMode = ui.BlendMode.plus
          ..color = _alpha(colour, 0.20 + openness * 0.22),
      );
      canvas.restore();
    }
    _drawGlowDot(
      canvas,
      ui.Offset.zero,
      math.max(2, radius * 0.13),
      const ui.Color(0xFFFFE07A),
      0.72,
    );
    canvas.restore();
  }

  @override
  void reset() {}
}
