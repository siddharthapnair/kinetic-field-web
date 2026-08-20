part of '../../../kinetic_field.dart';

class _MoonPondSceneRenderer implements _KineticSceneRenderer {
  final Map<KineticLandmarkId, List<ui.Offset>> _koiTrails =
      <KineticLandmarkId, List<ui.Offset>>{};
  final Float32List _motes = Float32List(660 * 2);
  final ui.Paint _paint = ui.Paint()..isAntiAlias = true;

  @override
  void paint(_SceneRenderContext context) {
    _drawMoonReflection(context);
    _drawMotes(context);
    _drawLilyPads(context);
    for (final hand in context.motion.visibleEffectors) {
      final position = context.screenFor(hand);
      _updateKoiTrail(hand.id, position);
      _drawRipple(context, position, hand.energy);
      _drawKoi(
        context,
        _koiTrails[hand.id]!,
        hand.id == KineticLandmarkId.rightWrist
            ? const ui.Color(0xFFFFC877)
            : const ui.Color(0xFF78E0EA),
      );
    }
    _drawEffectorBridge(
      context,
      colour: const ui.Color(0xFF83E4F0),
      amplitude: 0.18 + context.motion.energy * 0.25,
    );
  }

  void _drawMoonReflection(_SceneRenderContext context) {
    final canvas = context.canvas;
    final size = context.size;
    final stillness = (1 - context.motion.energy * 2.4).clamp(0.0, 1.0);
    final moon = ui.Offset(size.width * 0.78, size.height * 0.17);
    _drawGlowDot(
      canvas,
      moon,
      size.shortestSide * 0.025,
      const ui.Color(0xFFD8F4F4),
      0.34 + stillness * 0.26,
    );
    final path = ui.Path();
    final startY = size.height * 0.24;
    for (var index = 0; index < 24; index += 1) {
      final progress = index / 23;
      final y = startY + progress * size.height * 0.68;
      final width =
          (12 + progress * size.width * 0.10) * (0.72 + stillness * 0.28);
      final wave = math.sin(context.time * 0.7 + index * 1.8) *
          (context.settings.calm ? 1.2 : 3.8) *
          (1 - stillness * 0.65);
      path
        ..moveTo(moon.dx - width + wave, y)
        ..lineTo(moon.dx + width + wave, y);
    }
    canvas.drawPath(
      path,
      _paint
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = 1.1
        ..blendMode = ui.BlendMode.plus
        ..color = _alpha(const ui.Color(0xFFBEEAEC), 0.12 + stillness * 0.19),
    );
  }

  void _drawMotes(_SceneRenderContext context) {
    final count = context.qualityCount(low: 140, automatic: 340, high: 620);
    for (var index = 0; index < count; index += 1) {
      final depth = _hashUnit(index * 29 + 4);
      var x = _hashUnit(index * 71 + 2) +
          math.sin(context.time * (0.025 + depth * 0.04) + index) * 0.012;
      var y = _hashUnit(index * 53 + 12) +
          math.cos(context.time * 0.035 + index * 1.4) * 0.008;
      x = x.remainder(1.0);
      y = y.remainder(1.0);
      if (x < 0) x += 1;
      if (y < 0) y += 1;
      _motes[index * 2] = x * context.size.width;
      _motes[index * 2 + 1] = y * context.size.height;
    }
    context.canvas.drawRawPoints(
      ui.PointMode.points,
      Float32List.sublistView(_motes, 0, count * 2),
      _paint
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = context.settings.pointSize * 0.72
        ..blendMode = ui.BlendMode.plus
        ..color = _alpha(const ui.Color(0xFF78D6E2), 0.28),
    );
  }

  void _drawLilyPads(_SceneRenderContext context) {
    final canvas = context.canvas;
    final size = context.size;
    for (var index = 0; index < 7; index += 1) {
      final centre = ui.Offset(
        size.width * (0.08 + _hashUnit(index * 17 + 6) * 0.84),
        size.height * (0.62 + _hashUnit(index * 31 + 5) * 0.28),
      );
      final radius = 12 + _hashUnit(index + 9) * 20;
      final start = -0.15 + math.sin(index * 2.2) * 0.3;
      canvas.drawArc(
        ui.Rect.fromCircle(center: centre, radius: radius),
        start,
        math.pi * 1.78,
        true,
        _paint
          ..style = ui.PaintingStyle.fill
          ..blendMode = ui.BlendMode.srcOver
          ..color = _alpha(const ui.Color(0xFF3C836E), 0.24),
      );
      canvas.drawArc(
        ui.Rect.fromCircle(center: centre, radius: radius),
        start,
        math.pi * 1.78,
        false,
        _paint
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = _alpha(const ui.Color(0xFF79C9A9), 0.24),
      );
    }
  }

  void _updateKoiTrail(KineticLandmarkId id, ui.Offset position) {
    final trail = _koiTrails.putIfAbsent(id, () => <ui.Offset>[]);
    if (trail.isEmpty || (trail.last - position).distance > 1.4) {
      trail.add(position);
    }
    while (trail.length > 30) {
      trail.removeAt(0);
    }
  }

  void _drawRipple(
    _SceneRenderContext context,
    ui.Offset centre,
    double energy,
  ) {
    for (var ring = 0; ring < 3; ring += 1) {
      final phase =
          (context.time * (0.36 + energy * 0.4) + ring / 3).remainder(1.0);
      final radius = 16 + phase * (54 + energy * 72);
      context.canvas.drawOval(
        ui.Rect.fromCenter(
          center: centre,
          width: radius * 2,
          height: radius * 0.58,
        ),
        _paint
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..blendMode = ui.BlendMode.plus
          ..color = _alpha(const ui.Color(0xFF8AE6EF), (1 - phase) * 0.22),
      );
    }
  }

  void _drawKoi(
    _SceneRenderContext context,
    List<ui.Offset> trail,
    ui.Color colour,
  ) {
    if (trail.isEmpty) return;
    for (var index = 1; index < trail.length; index += 1) {
      final progress = index / trail.length;
      context.canvas.drawLine(
        trail[index - 1],
        trail[index],
        _paint
          ..style = ui.PaintingStyle.stroke
          ..strokeCap = ui.StrokeCap.round
          ..strokeWidth = 1.2 + progress * 8
          ..blendMode = ui.BlendMode.plus
          ..color = _alpha(colour, 0.04 + progress * 0.30),
      );
    }
    final head = trail.last;
    final previous = trail.length > 1 ? trail[trail.length - 2] : head;
    final angle = math.atan2(head.dy - previous.dy, head.dx - previous.dx);
    context.canvas.save();
    context.canvas.translate(head.dx, head.dy);
    context.canvas.rotate(angle);
    context.canvas.drawOval(
      ui.Rect.fromCenter(center: ui.Offset.zero, width: 26, height: 12),
      _paint
        ..style = ui.PaintingStyle.fill
        ..blendMode = ui.BlendMode.plus
        ..color = _alpha(colour, 0.56),
    );
    context.canvas.drawCircle(
      const ui.Offset(8, -2),
      1.4,
      _paint..color = _alpha(const ui.Color(0xFFE9FCF7), 0.82),
    );
    context.canvas.restore();
  }

  @override
  void reset() => _koiTrails.clear();
}
