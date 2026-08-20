part of '../kinetic_field.dart';

class _ParticleFieldBuffer {
  _ParticleFieldBuffer({
    required this.size,
    required this.count,
  })  : homeX = Float32List(count),
        homeY = Float32List(count),
        depth = Float32List(count),
        phase = Float32List(count),
        colourSeed = Float32List(count),
        pointBins = List<Float32List>.generate(
          24,
          (_) => Float32List(count * 2),
        ),
        trailBins = List<Float32List>.generate(
          8,
          (_) => Float32List(count * 4),
        ),
        pointCounts = List<int>.filled(24, 0),
        trailCounts = List<int>.filled(8, 0) {
    final aspect = size.width / math.max(size.height, 1);
    final columns = math.max(18, math.sqrt(count * aspect).round());
    final rows = math.max(18, (count / columns).ceil());
    for (var index = 0; index < count; index += 1) {
      final column = index % columns;
      final row = index ~/ columns;
      final jitterX = (_hashUnit(index * 47 + 5) - 0.5) / columns * 0.38;
      final jitterY = (_hashUnit(index * 31 + 9) - 0.5) / rows * 0.38;
      homeX[index] =
          ((column / math.max(columns - 1, 1) - 0.5) * 2 + jitterX) * aspect;
      homeY[index] = (0.5 - row / math.max(rows - 1, 1)) * 2 + jitterY;
      depth[index] = _hashUnit(index * 83 + 17) * 2 - 1;
      phase[index] = _hashUnit(index * 61 + 23) * math.pi * 2;
      colourSeed[index] = _hashUnit(index * 97 + 29);
    }
  }

  final ui.Size size;
  final int count;
  final Float32List homeX;
  final Float32List homeY;
  final Float32List depth;
  final Float32List phase;
  final Float32List colourSeed;
  final List<Float32List> pointBins;
  final List<Float32List> trailBins;
  final List<int> pointCounts;
  final List<int> trailCounts;

  void clearDrawBuffers() {
    pointCounts.fillRange(0, pointCounts.length, 0);
    trailCounts.fillRange(0, trailCounts.length, 0);
  }
}

class _KineticFieldPainter extends CustomPainter {
  _KineticFieldPainter({
    required this.controller,
    required this.elapsed,
    required this.backgroundColor,
    required this.onParticleCount,
    required this.automaticQualityScale,
  }) : super(repaint: Listenable.merge(<Listenable>[controller, elapsed]));

  final KineticFieldController controller;
  final ValueListenable<Duration> elapsed;
  final ui.Color backgroundColor;
  final ValueChanged<int> onParticleCount;
  final double automaticQualityScale;
  final _SceneRendererRegistry _sceneRenderers = _SceneRendererRegistry();
  final ui.Paint _paint = ui.Paint()
    ..isAntiAlias = true
    ..strokeCap = ui.StrokeCap.round;
  _ParticleFieldBuffer? _buffer;
  Duration _previousElapsed = Duration.zero;
  int _lastEventSequence = 0;
  double _burstEnvelope = 0;
  double _burstX = 0.5;
  double _burstY = 0.5;

  @visibleForTesting
  double get debugAutonomousTime {
    if (controller.settings.calm) return 0;
    return elapsed.value.inMicroseconds / Duration.microsecondsPerSecond;
  }

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    if (size.isEmpty) return;
    final settings = controller.settings;
    final sceneTime = debugAutonomousTime;
    final sceneElapsed = settings.calm ? Duration.zero : elapsed.value;
    final deltaSeconds = ((elapsed.value - _previousElapsed).inMicroseconds /
            Duration.microsecondsPerSecond)
        .clamp(1 / 120, 1 / 20);
    _previousElapsed = elapsed.value;
    final motion = controller._sampleMotion(elapsed.value);
    final sceneFrame = _strategyFor(settings.scene).evaluate(
      motion,
      settings,
      sceneElapsed,
    );
    _updateBurstEnvelope(
      motion,
      sceneFrame,
      deltaSeconds,
      settings.calm,
    );
    final budget = _particleBudget(settings.quality, automaticQualityScale);
    final existing = _buffer;
    if (existing == null || existing.size != size || existing.count != budget) {
      _buffer = _ParticleFieldBuffer(size: size, count: budget);
    }
    final buffer = _buffer!;
    onParticleCount(buffer.count);

    _drawBackground(canvas, size, settings.scene, sceneTime, settings.calm);
    _drawDepthField(
      canvas,
      size,
      buffer,
      motion,
      sceneFrame,
      settings,
      sceneTime,
    );
    _drawMotionPulse(canvas, size, motion, sceneFrame, settings, sceneTime);
    _drawEmitterHalos(canvas, size, sceneFrame, settings, sceneTime);
    _sceneRenderers.rendererFor(settings.scene).paint(
          _SceneRenderContext(
            canvas: canvas,
            size: size,
            time: sceneTime,
            deltaSeconds: deltaSeconds,
            motion: motion,
            frame: sceneFrame,
            settings: settings,
            automaticQualityScale: automaticQualityScale,
          ),
        );
    _drawVignette(canvas, size, settings.scene);
  }

  void _updateBurstEnvelope(
    KineticMotionState motion,
    KineticSceneFrame frame,
    double deltaSeconds,
    bool calm,
  ) {
    _burstEnvelope *= math.exp(-deltaSeconds * (calm ? 8.2 : 6.2));
    if (_burstEnvelope < 0.002) _burstEnvelope = 0;
    if (motion.eventSequence == _lastEventSequence) return;

    _lastEventSequence = motion.eventSequence;
    if (motion.event == KineticMotionEvent.none) return;
    final response = calm ? 0.48 : 1.0;
    _burstEnvelope = math.max(
      _burstEnvelope,
      frame.burstEnvelope.clamp(0.0, 1.0) * response,
    );
    _burstX = motion.midpointX.clamp(0.0, 1.0);
    _burstY = motion.midpointY.clamp(0.0, 1.0);
  }

  void _drawBackground(
    ui.Canvas canvas,
    ui.Size size,
    KineticScene scene,
    double time,
    bool calm,
  ) {
    final base = _sceneBackground(scene);
    canvas.drawRect(
      ui.Offset.zero & size,
      _paint
        ..style = ui.PaintingStyle.fill
        ..blendMode = ui.BlendMode.srcOver
        ..shader = null
        ..color = base,
    );
    final centre = ui.Offset(
      size.width * (0.5 + (calm ? 0 : math.sin(time * 0.09) * 0.08)),
      size.height * (0.42 + (calm ? 0 : math.cos(time * 0.07) * 0.05)),
    );
    final accent = _sceneAccent(scene);
    canvas.drawRect(
      ui.Offset.zero & size,
      _paint
        ..shader = ui.Gradient.radial(
          centre,
          size.longestSide * 0.72,
          <ui.Color>[
            _alpha(accent, 0.10),
            _alpha(base, 0),
          ],
        )
        ..color = base,
    );
    _paint.shader = null;
  }

  void _drawDepthField(
    ui.Canvas canvas,
    ui.Size size,
    _ParticleFieldBuffer buffer,
    KineticMotionState motion,
    KineticSceneFrame sceneFrame,
    KineticFieldSettings settings,
    double time,
  ) {
    buffer.clearDrawBuffers();
    final aspect = size.width / math.max(size.height, 1);
    final emitters = sceneFrame.activeEmitters.toList(growable: false);
    final leftEmitter = sceneFrame.left;
    final rightEmitter = sceneFrame.right;
    final bothActive = leftEmitter.isActive && rightEmitter.isActive;
    final leftWorldX = (leftEmitter.x - 0.5) * 2 * aspect;
    final leftWorldY = (0.5 - leftEmitter.y) * 2;
    final rightWorldX = (rightEmitter.x - 0.5) * 2 * aspect;
    final rightWorldY = (0.5 - rightEmitter.y) * 2;
    final bridgeDx = rightWorldX - leftWorldX;
    final bridgeDy = rightWorldY - leftWorldY;
    final bridgeLengthSquared = bridgeDx * bridgeDx + bridgeDy * bridgeDy;
    final hasMotion = motion.visibleEffectorCount > 0;
    final burstActive = _burstEnvelope > 0.002;
    final pulseWorldX =
        ((burstActive ? _burstX : motion.midpointX) - 0.5) * 2 * aspect;
    final pulseWorldY = (0.5 - (burstActive ? _burstY : motion.midpointY)) * 2;
    final pulseStrength = hasMotion
        ? ((sceneFrame.depthPulse * 0.62 + _burstEnvelope * 0.92) *
                (settings.calm ? 0.38 : 1.0))
            .clamp(0.0, 1.25)
        : 0.0;
    final pulseRadius = (0.42 + settings.radius * 0.9).clamp(0.42, 1.05);
    final pulseRadiusSquared = pulseRadius * pulseRadius;

    for (var index = 0; index < buffer.count; index += 1) {
      var worldX = buffer.homeX[index];
      var worldY = buffer.homeY[index];
      final autonomous = settings.calm ? 0.0 : 1.0;
      var worldZ = buffer.depth[index] * 0.42 * settings.depth +
          math.sin(buffer.phase[index] + time * 0.24) *
              0.11 *
              settings.depth *
              autonomous;
      var strongestInfluence = 0.0;
      var trailVx = 0.0;
      var trailVy = 0.0;
      var hueShift = 0.0;

      for (var emitterIndex = 0;
          emitterIndex < emitters.length;
          emitterIndex += 1) {
        final emitter = emitters[emitterIndex];
        final emitterX = (emitter.x - 0.5) * 2 * aspect;
        final emitterY = (0.5 - emitter.y) * 2;
        final dx = worldX - emitterX;
        final dy = worldY - emitterY;
        final distanceSquared = dx * dx + dy * dy + 0.00001;
        final radiusSquared = emitter.radius * emitter.radius * 4;
        final q = (1 - distanceSquared / radiusSquared).clamp(0.0, 1.0);
        final influence = q * q * (3 - 2 * q) * emitter.confidence;
        if (influence <= 0) continue;
        final inverseDistance = 1 / math.sqrt(distanceSquared);
        final tangentX = -dy * inverseDistance;
        final tangentY = dx * inverseDistance;
        final radialWave = math.sin(
          distanceSquared * 34 -
              time * (3.2 + emitter.force * 1.7) +
              buffer.phase[index],
        );
        final swirl =
            influence * emitter.spin * (0.035 + emitter.force * 0.045);
        final radial = influence * emitter.force * radialWave * 0.052;
        worldX += tangentX * swirl + dx * inverseDistance * radial;
        worldY += tangentY * swirl + dy * inverseDistance * radial;
        worldX += emitter.vx * influence * 0.035 * aspect;
        worldY -= emitter.vy * influence * 0.035;
        worldZ += influence *
            settings.depth *
            (0.24 + emitter.force * 0.24) *
            math.cos(distanceSquared * 24 - time * 4.1);
        if (influence > strongestInfluence) {
          strongestInfluence = influence;
          trailVx = emitter.vx;
          trailVy = emitter.vy;
          hueShift = emitterIndex * 0.42 + emitter.force * 0.08;
        }
      }

      if (bothActive && bridgeLengthSquared > 0.001) {
        final pointDx = worldX - leftWorldX;
        final pointDy = worldY - leftWorldY;
        final along =
            ((pointDx * bridgeDx + pointDy * bridgeDy) / bridgeLengthSquared)
                .clamp(0.0, 1.0);
        final bridgeX = leftWorldX + bridgeDx * along;
        final bridgeY = leftWorldY + bridgeDy * along;
        final lineDx = worldX - bridgeX;
        final lineDy = worldY - bridgeY;
        final lineDistanceSquared = lineDx * lineDx + lineDy * lineDy;
        final bridgeQ = (1 - lineDistanceSquared / 0.055).clamp(0.0, 1.0);
        final bridgeInfluence = bridgeQ * bridgeQ * (3 - 2 * bridgeQ);
        worldZ += bridgeInfluence *
            sceneFrame.tension *
            settings.depth *
            0.46 *
            math.sin(along * math.pi);
        strongestInfluence =
            math.max(strongestInfluence, bridgeInfluence * 0.7);
      }

      if (pulseStrength > 0.01) {
        final pulseDx = worldX - pulseWorldX;
        final pulseDy = worldY - pulseWorldY;
        final pulseDistanceSquared =
            pulseDx * pulseDx + pulseDy * pulseDy + 0.00001;
        final pulseQ =
            (1 - pulseDistanceSquared / pulseRadiusSquared).clamp(0.0, 1.0);
        if (pulseQ > 0) {
          final pulseInfluence = pulseQ * pulseQ * (3 - 2 * pulseQ);
          final pulseDistance = math.sqrt(pulseDistanceSquared);
          final inversePulseDistance = 1 / pulseDistance;
          final radialWave = math.sin(
            pulseDistance * 13 - time * 7.2 + _burstEnvelope * math.pi,
          );
          final radialAmount = pulseInfluence *
              pulseStrength *
              (0.018 + _burstEnvelope * 0.032) *
              (0.35 + radialWave * 0.65);
          worldX += pulseDx * inversePulseDistance * radialAmount;
          worldY += pulseDy * inversePulseDistance * radialAmount;
          worldZ += pulseInfluence *
              pulseStrength *
              settings.depth *
              (0.18 +
                  0.18 *
                      math.cos(
                        pulseDistance * 11 - time * 6.4,
                      ));
          strongestInfluence = math.max(
            strongestInfluence,
            pulseInfluence * pulseStrength * 0.82,
          );
          hueShift += pulseInfluence * _burstEnvelope * 0.36;
        }
      }

      if (!settings.calm) {
        final turbulence = math.sin(
              worldX * 7.7 + worldY * 5.9 + time * 0.62 + buffer.phase[index],
            ) *
            settings.turbulence *
            (0.002 + strongestInfluence * 0.006);
        worldX += turbulence;
        worldY -= turbulence * 0.72;
      }

      final depth01 = ((worldZ + 1) * 0.5).clamp(0.0, 1.0);
      final perspective = 0.82 + depth01 * 0.36 * settings.depth;
      final screenX =
          size.width * 0.5 + worldX / aspect * size.width * 0.5 * perspective;
      final screenY =
          size.height * 0.5 - worldY * size.height * 0.5 * perspective;
      if (screenX < -12 ||
          screenX > size.width + 12 ||
          screenY < -12 ||
          screenY > size.height + 12) {
        continue;
      }

      final depthLayer = (depth01 * 2.999).floor().clamp(0, 2);
      final palette = ((buffer.colourSeed[index] * 4 +
                  depth01 * 2 +
                  strongestInfluence * 4 +
                  hueShift * 2)
              .floor()) %
          8;
      final bin = depthLayer * 8 + palette;
      final pointOffset = buffer.pointCounts[bin] * 2;
      buffer.pointBins[bin][pointOffset] = screenX;
      buffer.pointBins[bin][pointOffset + 1] = screenY;
      buffer.pointCounts[bin] += 1;

      if (strongestInfluence > 0.12 &&
          settings.trails > 0.04 &&
          index % 4 == 0) {
        final trailIndex = buffer.trailCounts[palette] * 4;
        final trailScale = sceneFrame.trailAmount *
            (0.018 + depth01 * 0.014) *
            (settings.calm ? 0.45 : 1.0);
        final maximumTrail = size.shortestSide * 0.18;
        final trailDx = (trailVx * size.width * trailScale).clamp(
          -maximumTrail,
          maximumTrail,
        );
        final trailDy = (trailVy * size.height * trailScale).clamp(
          -maximumTrail,
          maximumTrail,
        );
        buffer.trailBins[palette][trailIndex] = screenX;
        buffer.trailBins[palette][trailIndex + 1] = screenY;
        buffer.trailBins[palette][trailIndex + 2] = screenX - trailDx;
        buffer.trailBins[palette][trailIndex + 3] = screenY - trailDy;
        buffer.trailCounts[palette] += 1;
      }
    }

    _drawParticleBins(canvas, buffer, settings, sceneFrame, time);
  }

  void _drawParticleBins(
    ui.Canvas canvas,
    _ParticleFieldBuffer buffer,
    KineticFieldSettings settings,
    KineticSceneFrame sceneFrame,
    double time,
  ) {
    final baseHue = switch (settings.scene) {
      KineticScene.bloom => 308.0,
      KineticScene.honeybees => 34.0,
      KineticScene.fireflies => 78.0,
      KineticScene.moonPond => 174.0,
    };
    for (var palette = 0; palette < 8; palette += 1) {
      final trailCount = buffer.trailCounts[palette];
      if (trailCount == 0) continue;
      final hue = (baseHue + palette * 23 + sceneFrame.huePhase * 90) % 360;
      final trailLines = Float32List.sublistView(
        buffer.trailBins[palette],
        0,
        trailCount * 4,
      );
      canvas.drawRawPoints(
        ui.PointMode.lines,
        trailLines,
        _paint
          ..shader = null
          ..style = ui.PaintingStyle.stroke
          ..strokeCap = ui.StrokeCap.round
          ..blendMode = ui.BlendMode.plus
          ..strokeWidth = settings.pointSize * 3.4
          ..color = HSVColor.fromAHSV(
            settings.calm ? 0.055 : 0.095,
            hue,
            0.86,
            0.98,
          ).toColor(),
      );
      canvas.drawRawPoints(
        ui.PointMode.lines,
        trailLines,
        _paint
          ..strokeWidth = settings.pointSize * 1.05
          ..color = HSVColor.fromAHSV(
            settings.calm ? 0.18 : 0.32,
            hue,
            0.72,
            1,
          ).toColor(),
      );
    }

    for (var depth = 0; depth < 3; depth += 1) {
      for (var palette = 0; palette < 8; palette += 1) {
        final bin = depth * 8 + palette;
        final count = buffer.pointCounts[bin];
        if (count == 0) continue;
        final hue = (baseHue +
                palette * 23 +
                depth * 11 +
                sceneFrame.huePhase * 90 +
                time * settings.colourSpeed * (settings.calm ? 0 : 2.2)) %
            360;
        final alpha = 0.20 + depth * 0.12;
        final points = Float32List.sublistView(
          buffer.pointBins[bin],
          0,
          count * 2,
        );
        if (depth == 2) {
          canvas.drawRawPoints(
            ui.PointMode.points,
            points,
            _paint
              ..shader = null
              ..style = ui.PaintingStyle.stroke
              ..strokeCap = ui.StrokeCap.round
              ..blendMode = ui.BlendMode.plus
              ..strokeWidth = settings.pointSize * 3.15
              ..color = HSVColor.fromAHSV(
                settings.calm ? 0.075 : 0.14,
                hue,
                0.72,
                1,
              ).toColor(),
          );
        }
        canvas.drawRawPoints(
          ui.PointMode.points,
          points,
          _paint
            ..shader = null
            ..style = ui.PaintingStyle.stroke
            ..strokeCap = ui.StrokeCap.round
            ..blendMode = ui.BlendMode.plus
            ..strokeWidth = settings.pointSize * (0.62 + depth * 0.42)
            ..color = HSVColor.fromAHSV(
              (alpha + (depth == 2 ? 0.08 : 0)) * (settings.calm ? 0.78 : 1.0),
              hue,
              depth == 2 ? 0.74 : 0.82,
              1,
            ).toColor(),
        );
      }
    }
  }

  void _drawMotionPulse(
    ui.Canvas canvas,
    ui.Size size,
    KineticMotionState motion,
    KineticSceneFrame frame,
    KineticFieldSettings settings,
    double time,
  ) {
    if (motion.visibleEffectorCount == 0) return;
    final response = settings.calm ? 0.38 : 1.0;
    final strength =
        ((frame.depthPulse * 0.58 + _burstEnvelope) * response).clamp(
      0.0,
      1.25,
    );
    if (strength < 0.025) return;

    final burstActive = _burstEnvelope > 0.002;
    final centre = ui.Offset(
      (burstActive ? _burstX : motion.midpointX) * size.width,
      (burstActive ? _burstY : motion.midpointY) * size.height,
    );
    final radius = size.shortestSide *
        (0.09 + frame.depthPulse * 0.12 + _burstEnvelope * 0.07);
    final colour = _sceneAccent(settings.scene);
    canvas.drawCircle(
      centre,
      radius,
      _paint
        ..style = ui.PaintingStyle.fill
        ..blendMode = ui.BlendMode.plus
        ..shader = ui.Gradient.radial(
          centre,
          radius,
          <ui.Color>[
            _alpha(colour, 0.13 * strength),
            _alpha(colour, 0.045 * strength),
            _alpha(colour, 0),
          ],
          const <double>[0, 0.48, 1],
        ),
    );
    _paint.shader = null;

    final ringPhase = 0.72 + math.sin(time * 7.4) * 0.08;
    canvas.drawCircle(
      centre,
      radius * ringPhase,
      _paint
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.0 + settings.pointSize * 0.45
        ..blendMode = ui.BlendMode.plus
        ..color = _alpha(colour, 0.16 * strength),
    );
  }

  void _drawEmitterHalos(
    ui.Canvas canvas,
    ui.Size size,
    KineticSceneFrame frame,
    KineticFieldSettings settings,
    double time,
  ) {
    var index = 0;
    for (final emitter in frame.activeEmitters) {
      final centre = ui.Offset(emitter.x * size.width, emitter.y * size.height);
      final radius = emitter.radius * size.shortestSide * 0.52;
      final hue = (settings.scene.index * 67 + index * 126 + time * 9) % 360;
      final colour = HSVColor.fromAHSV(1, hue, 0.82, 1).toColor();
      canvas.drawCircle(
        centre,
        radius,
        _paint
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..blendMode = ui.BlendMode.plus
          ..color = _alpha(colour, 0.11 + emitter.force * 0.08),
      );
      _drawGlowDot(
        canvas,
        centre,
        2.8 + emitter.force * 2.2,
        colour,
        0.42,
      );
      index += 1;
    }
  }

  void _drawVignette(ui.Canvas canvas, ui.Size size, KineticScene scene) {
    final base = _sceneBackground(scene);
    canvas.drawRect(
      ui.Offset.zero & size,
      _paint
        ..style = ui.PaintingStyle.fill
        ..blendMode = ui.BlendMode.srcOver
        ..shader = ui.Gradient.radial(
          size.center(ui.Offset.zero),
          size.longestSide * 0.72,
          <ui.Color>[_alpha(base, 0), _alpha(base, 0.44)],
          const <double>[0.62, 1],
        ),
    );
    _paint.shader = null;
  }

  int _particleBudget(KineticQuality quality, double automaticScale) {
    return switch (quality) {
      KineticQuality.low => 1600,
      KineticQuality.automatic =>
        (4200 * automaticScale.clamp(0.55, 1.0)).round(),
      KineticQuality.high => 6800,
    };
  }

  @override
  bool shouldRepaint(covariant _KineticFieldPainter oldDelegate) {
    return oldDelegate.controller != controller ||
        oldDelegate.elapsed != elapsed ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.automaticQualityScale != automaticQualityScale;
  }
}
