part of '../../../kinetic_field.dart';

class _FireflySceneRenderer implements _KineticSceneRenderer {
  final Float32List _lights = Float32List(900 * 2);
  final List<ui.Offset> _pinnedStars = <ui.Offset>[];
  final ui.Paint _paint = ui.Paint()..isAntiAlias = true;
  int _lastEventSequence = 0;

  @override
  void paint(_SceneRenderContext context) {
    _captureSettledStar(context);
    _drawNightSky(context);
    _drawFireflies(context);
    _drawConstellation(context);
    for (final hand in context.motion.visibleEffectors) {
      final position = context.screenFor(hand);
      _drawGlowDot(
        context.canvas,
        position,
        5 + hand.energy * 5,
        const ui.Color(0xFFB9FF72),
        0.72,
      );
    }
    _drawEffectorBridge(
      context,
      colour: const ui.Color(0xFF9FD8FF),
      amplitude: 0.52 + context.frame.tension * 0.38,
    );
  }

  void _captureSettledStar(_SceneRenderContext context) {
    final motion = context.motion;
    if (motion.eventSequence == _lastEventSequence) return;
    _lastEventSequence = motion.eventSequence;
    if (motion.event != KineticMotionEvent.settle ||
        motion.visibleEffectorCount == 0) {
      return;
    }
    _pinnedStars.add(
      ui.Offset(
        motion.midpointX * context.size.width,
        motion.midpointY * context.size.height,
      ),
    );
    while (_pinnedStars.length > 12) {
      _pinnedStars.removeAt(0);
    }
  }

  void _drawNightSky(_SceneRenderContext context) {
    final count = context.qualityCount(low: 42, automatic: 78, high: 78);
    for (var index = 0; index < count; index += 1) {
      final point = ui.Offset(
        _hashUnit(index * 73 + 9) * context.size.width,
        _hashUnit(index * 41 + 27) * context.size.height * 0.84,
      );
      final pulse = context.settings.calm
          ? 0.45
          : 0.32 + math.sin(context.time * 0.8 + index) * 0.13;
      context.canvas.drawCircle(
        point,
        0.45 + _hashUnit(index + 3) * 0.85,
        _paint
          ..style = ui.PaintingStyle.fill
          ..blendMode = ui.BlendMode.plus
          ..color = _alpha(const ui.Color(0xFFB8D8FF), pulse),
      );
    }
  }

  void _drawFireflies(_SceneRenderContext context) {
    final count = context.qualityCount(low: 180, automatic: 430, high: 820);
    var linkBudget = context.qualityCount(low: 8, automatic: 18, high: 30);
    for (var index = 0; index < count; index += 1) {
      final depth = _hashUnit(index * 19 + 1);
      var x = _hashUnit(index * 67 + 5) +
          math.sin(context.time * (0.035 + depth * 0.08) + index * 1.3) *
              (0.012 + depth * 0.016);
      var y = _hashUnit(index * 43 + 17) +
          math.cos(context.time * (0.04 + depth * 0.06) + index) *
              (0.008 + depth * 0.018);
      for (final hand in context.motion.visibleEffectors) {
        final dx = hand.x - x;
        final dy = hand.y - y;
        final distanceSquared = dx * dx + dy * dy;
        final influence = (1 - distanceSquared / 0.09).clamp(0.0, 1.0);
        final attraction = influence * influence * (0.18 + hand.energy * 0.16);
        x += dx * attraction;
        y += dy * attraction;
        if (linkBudget > 0 && influence > 0.62 && index % 4 == 0) {
          linkBudget -= 1;
          context.canvas.drawLine(
            ui.Offset(x * context.size.width, y * context.size.height),
            context.screenFor(hand),
            _paint
              ..style = ui.PaintingStyle.stroke
              ..strokeWidth = 0.65
              ..blendMode = ui.BlendMode.plus
              ..color = _alpha(const ui.Color(0xFFA8E8FF), 0.10),
          );
        }
      }
      x = x.remainder(1.0);
      y = y.remainder(1.0);
      if (x < 0) x += 1;
      if (y < 0) y += 1;
      _lights[index * 2] = x * context.size.width;
      _lights[index * 2 + 1] = y * context.size.height;
    }
    context.canvas.drawRawPoints(
      ui.PointMode.points,
      Float32List.sublistView(_lights, 0, count * 2),
      _paint
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = context.settings.pointSize * 1.08
        ..blendMode = ui.BlendMode.plus
        ..color = _alpha(const ui.Color(0xFFB9FF72), 0.48),
    );
  }

  void _drawConstellation(_SceneRenderContext context) {
    if (_pinnedStars.isEmpty) return;
    final path = ui.Path()
      ..moveTo(_pinnedStars.first.dx, _pinnedStars.first.dy);
    for (var index = 1; index < _pinnedStars.length; index += 1) {
      path.lineTo(_pinnedStars[index].dx, _pinnedStars[index].dy);
    }
    context.canvas.drawPath(
      path,
      _paint
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..blendMode = ui.BlendMode.plus
        ..color = _alpha(const ui.Color(0xFF9FD8FF), 0.28),
    );
    for (var index = 0; index < _pinnedStars.length; index += 1) {
      final star = _pinnedStars[index];
      _drawGlowDot(
        context.canvas,
        star,
        2.5 + (index % 3),
        const ui.Color(0xFFD9F7FF),
        0.62,
      );
    }
  }

  @override
  void reset() {
    _pinnedStars.clear();
    _lastEventSequence = 0;
  }
}
