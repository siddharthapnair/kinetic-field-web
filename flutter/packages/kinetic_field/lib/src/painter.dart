part of '../kinetic_field.dart';

class _GridSpec {
  const _GridSpec(this.columns, this.rows);

  final int columns;
  final int rows;

  int get particleCount => columns * rows;
}

class _KineticFieldPainter extends CustomPainter {
  _KineticFieldPainter({
    required this.controller,
    required this.elapsed,
    required this.backgroundColor,
    required this.onParticleCount,
  }) : super(repaint: Listenable.merge(<Listenable>[controller, elapsed]));

  final KineticFieldController controller;
  final ValueListenable<Duration> elapsed;
  final ui.Color backgroundColor;
  final ValueChanged<int> onParticleCount;

  static const _paletteSize = 8;
  final List<List<ui.Offset>> _palettePoints = List<List<ui.Offset>>.generate(
    _paletteSize,
    (_) => <ui.Offset>[],
  );
  final List<ui.Offset> _reactivePoints = <ui.Offset>[];
  final ui.Paint _paint = ui.Paint()
    ..isAntiAlias = true
    ..strokeCap = ui.StrokeCap.round;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    if (size.isEmpty) return;

    final settings = controller.settings;
    final time = elapsed.value.inMicroseconds / Duration.microsecondsPerSecond;
    final motion = _resolvedMotion(time, settings);
    final grid = _gridFor(size, settings.quality);
    onParticleCount(grid.particleCount);

    canvas.drawRect(ui.Offset.zero & size, _paint..color = backgroundColor);
    final glow = ui.Gradient.radial(
      size.center(ui.Offset.zero),
      size.shortestSide * 0.62,
      <ui.Color>[
        const ui.Color(0x33243A66),
        const ui.Color(0x00050810),
      ],
    );
    canvas.drawRect(
      ui.Offset.zero & size,
      _paint
        ..shader = glow
        ..blendMode = ui.BlendMode.srcOver,
    );
    _paint.shader = null;

    for (final points in _palettePoints) {
      points.clear();
    }
    _reactivePoints.clear();

    final aspect = size.width / math.max(size.height, 1);
    final pointerWorldX = (motion.x - 0.5) * 2 * aspect;
    final pointerWorldY = (0.5 - motion.y) * 2;
    final confidence = motion.confidence;
    final speed = math.min(
        1.0, math.sqrt(motion.vx * motion.vx + motion.vy * motion.vy) * 9);
    final energyResponse = settings.calm ? 0.42 : 1.0;
    final activeEnergy = math.max(
      motion.energy * confidence * energyResponse,
      speed * confidence * 0.75,
    );
    final motionGate = settings.calm ? math.min(1.0, activeEnergy * 8) : 1.0;

    for (var row = 0; row < grid.rows; row += 1) {
      final rowProgress = row / math.max(grid.rows - 1, 1);
      for (var column = 0; column < grid.columns; column += 1) {
        final columnProgress = column / math.max(grid.columns - 1, 1);
        var worldX = (columnProgress - 0.5) * 2 * aspect;
        var worldY = (0.5 - rowProgress) * 2;
        final deltaX = worldX - pointerWorldX;
        final deltaY = worldY - pointerWorldY;
        final distance = math.sqrt(deltaX * deltaX + deltaY * deltaY) + 0.0001;
        final influence = math.exp(
          -(distance * distance) /
              math.max(0.025, settings.radius * settings.radius),
        );
        final trustedInfluence = influence * confidence;
        final tangentX = -deltaY / distance;
        final tangentY = deltaX / distance;
        final radialX = deltaX / distance;
        final radialY = deltaY / distance;

        final quietNoise =
            _fieldNoise(worldX, worldY, time) * 0.008 * (settings.calm ? 0 : 1);
        worldX += quietNoise;
        worldY -= quietNoise * 0.72;

        final rotatingWave =
            math.sin(distance * 24 - time * 3.4 + activeEnergy * 2);
        final swirlForce = trustedInfluence *
            settings.swirl *
            settings.force *
            motionGate *
            (0.035 + activeEnergy * 0.135);
        final radialForce = trustedInfluence *
            rotatingWave *
            settings.force *
            motionGate *
            (0.012 + activeEnergy * 0.052);
        worldX += tangentX * swirlForce + radialX * radialForce;
        worldY += tangentY * swirlForce + radialY * radialForce;
        worldX += motion.vx * aspect * trustedInfluence * settings.force * 0.58;
        worldY -= motion.vy * trustedInfluence * settings.force * 0.58;

        final turbulence = _fieldNoise(worldX * 1.8, worldY * 1.8, time * 1.3) *
            settings.turbulence *
            trustedInfluence *
            motionGate *
            0.007;
        worldX += turbulence;
        worldY -= turbulence * 0.72;

        final screenX = (worldX / aspect + 1) * 0.5 * size.width;
        final screenY = (1 - worldY) * 0.5 * size.height;
        if (screenX < -8 ||
            screenX > size.width + 8 ||
            screenY < -8 ||
            screenY > size.height + 8) {
          continue;
        }

        final colourPhase = columnProgress * 1.6 +
            rowProgress * 4.2 +
            time * settings.colourSpeed * 0.11 * (settings.calm ? 0 : 1) +
            trustedInfluence * 2.4;
        final paletteIndex = (colourPhase.floor() % _paletteSize).abs();
        final point = ui.Offset(screenX, screenY);
        _palettePoints[paletteIndex].add(point);
        if (trustedInfluence * motionGate > 0.035) {
          _reactivePoints.add(point);
        }
      }
    }

    final baseAlpha = settings.calm ? 0.33 : 0.46;
    for (var index = 0; index < _palettePoints.length; index += 1) {
      final points = _palettePoints[index];
      if (points.isEmpty) continue;
      final hue = (188 +
              index * 18 +
              time * settings.colourSpeed * 3 * (settings.calm ? 0 : 1)) %
          360;
      final colour = HSVColor.fromAHSV(baseAlpha, hue, 0.78, 0.92).toColor();
      canvas.drawPoints(
        ui.PointMode.points,
        points,
        _paint
          ..blendMode = ui.BlendMode.plus
          ..color = colour
          ..strokeWidth = settings.pointSize,
      );
    }

    if (_reactivePoints.isNotEmpty) {
      final reactiveHue = (202 +
              time * settings.colourSpeed * 18 * (settings.calm ? 0 : 1) +
              activeEnergy * 118) %
          360;
      canvas.drawPoints(
        ui.PointMode.points,
        _reactivePoints,
        _paint
          ..blendMode = ui.BlendMode.plus
          ..color = HSVColor.fromAHSV(
            math.min(0.9, 0.36 + activeEnergy * 0.5),
            reactiveHue,
            0.96,
            1,
          ).toColor()
          ..strokeWidth = settings.pointSize * (1.35 + activeEnergy * 1.4),
      );
    }

    final vignette = ui.Gradient.radial(
      size.center(ui.Offset.zero),
      math.max(size.width, size.height) * 0.72,
      const <ui.Color>[
        ui.Color(0x00050810),
        ui.Color(0xB8050810),
      ],
      const <double>[0.48, 1],
    );
    canvas.drawRect(
      ui.Offset.zero & size,
      _paint
        ..blendMode = ui.BlendMode.srcOver
        ..shader = vignette,
    );
    _paint.shader = null;
  }

  MotionSample _resolvedMotion(double time, KineticFieldSettings settings) {
    final ageMillis = controller._motionAge.inMicroseconds / 1000;
    if (ageMillis > 1800) {
      if (settings.calm) {
        return MotionSample(
          x: 0.5,
          y: 0.5,
          energy: 0,
          timestamp: elapsed.value,
        );
      }

      return MotionSample(
        x: 0.5 + math.sin(time * 0.29) * 0.2,
        y: 0.5 + math.cos(time * 0.23) * 0.13,
        vx: math.cos(time * 0.29) * 0.003,
        vy: -math.sin(time * 0.23) * 0.002,
        energy: 0.2,
        timestamp: elapsed.value,
      );
    }

    final decay = math.exp(-ageMillis / 240);
    return controller.motion.copyWith(
      vx: controller.motion.vx * decay,
      vy: controller.motion.vy * decay,
      energy: controller.motion.energy * decay,
    );
  }

  _GridSpec _gridFor(ui.Size size, KineticQuality quality) {
    final budget = switch (quality) {
      KineticQuality.low => 1800,
      KineticQuality.automatic => 4200,
      KineticQuality.high => 8200,
    };
    final safeAspect = (size.width / math.max(size.height, 1)).clamp(0.35, 3.2);
    final columns = math.max(20, math.sqrt(budget * safeAspect).round());
    final rows = math.max(20, (budget / columns).round());
    return _GridSpec(columns, rows);
  }

  double _fieldNoise(double x, double y, double time) {
    return math.sin(x * 8.3 + time * 0.71) * math.cos(y * 7.1 - time * 0.63) +
        math.sin((x + y) * 13.7 - time * 0.39) * 0.45;
  }

  @override
  bool shouldRepaint(covariant _KineticFieldPainter oldDelegate) {
    return oldDelegate.controller != controller ||
        oldDelegate.elapsed != elapsed ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
