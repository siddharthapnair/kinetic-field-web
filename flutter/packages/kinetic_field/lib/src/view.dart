part of '../kinetic_field.dart';

/// A continuously animated, motion-responsive particle vortex.
///
/// The view does not own [controller]. The caller must dispose the controller
/// when it is no longer required.
class KineticFieldView extends StatefulWidget {
  /// Creates a field driven by [controller].
  const KineticFieldView({
    super.key,
    required this.controller,
    this.onStats,
    this.enablePointer = true,
    this.backgroundColor = const ui.Color(0xFF050810),
    this.semanticLabel = 'Motion-responsive particle field',
  });

  /// Motion and settings source for the field.
  final KineticFieldController controller;

  /// Receives an approximate performance report once per second.
  final ValueChanged<KineticFieldStats>? onStats;

  /// Whether pointer, mouse, stylus and touch movement should update motion.
  final bool enablePointer;

  /// Opaque background drawn below the particle field.
  final ui.Color backgroundColor;

  /// Accessible description of this non-text visual.
  final String semanticLabel;

  @override
  State<KineticFieldView> createState() => _KineticFieldViewState();
}

class _KineticFieldViewState extends State<KineticFieldView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<Duration> _elapsed =
      ValueNotifier<Duration>(Duration.zero);
  Duration _statsWindowStartedAt = Duration.zero;
  Duration _previousFrameAt = Duration.zero;
  var _frameCount = 0;
  var _frameTimeMicros = 0;
  var _particleCount = 0;
  var _slowWindows = 0;
  var _fastWindows = 0;
  var _automaticQualityScale = 1.0;
  _KineticFieldPainter? _painter;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_handleTick)..start();
  }

  void _handleTick(Duration elapsed) {
    final frameDelta = elapsed - _previousFrameAt;
    _previousFrameAt = elapsed;
    _elapsed.value = elapsed;
    _frameCount += 1;
    if (!frameDelta.isNegative) {
      _frameTimeMicros += frameDelta.inMicroseconds;
    }

    final window = elapsed - _statsWindowStartedAt;
    if (window < const Duration(seconds: 1)) return;

    final fps = window.inMicroseconds == 0
        ? 0
        : (_frameCount * Duration.microsecondsPerSecond / window.inMicroseconds)
            .round();
    final averageFrameTime = _frameCount == 0
        ? Duration.zero
        : Duration(microseconds: _frameTimeMicros ~/ _frameCount);
    final stats = KineticFieldStats(
      fps: fps,
      particleCount: _particleCount,
      averageFrameTime: averageFrameTime,
    );
    widget.controller._updateStats(stats);
    widget.onStats?.call(stats);
    _adaptAutomaticQuality(fps);
    _statsWindowStartedAt = elapsed;
    _frameCount = 0;
    _frameTimeMicros = 0;
  }

  void _adaptAutomaticQuality(int fps) {
    if (widget.controller.settings.quality != KineticQuality.automatic) {
      _slowWindows = 0;
      _fastWindows = 0;
      return;
    }
    if (fps < 45) {
      _slowWindows += 1;
      _fastWindows = 0;
    } else if (fps > 57) {
      _fastWindows += 1;
      _slowWindows = 0;
    } else {
      _slowWindows = 0;
      _fastWindows = 0;
    }
    var next = _automaticQualityScale;
    if (_slowWindows >= 3) {
      next = math.max(0.55, _automaticQualityScale - 0.18);
      _slowWindows = 0;
    } else if (_fastWindows >= 10) {
      next = math.min(1.0, _automaticQualityScale + 0.10);
      _fastWindows = 0;
    }
    if (next == _automaticQualityScale || !mounted) return;
    setState(() => _automaticQualityScale = next);
  }

  void _updatePointer(PointerEvent event, ui.Size size) {
    if (!widget.enablePointer || size.isEmpty) return;
    widget.controller.updatePointer(
      x: event.localPosition.dx / size.width,
      y: event.localPosition.dy / size.height,
      timestamp: event.timeStamp,
      pointerId: event.pointer,
    );
  }

  void _recordParticleCount(int count) {
    _particleCount = count;
  }

  _KineticFieldPainter _resolvePainter() {
    final existing = _painter;
    if (existing != null &&
        identical(existing.controller, widget.controller) &&
        existing.backgroundColor == widget.backgroundColor &&
        existing.automaticQualityScale == _automaticQualityScale) {
      return existing;
    }
    return _painter = _KineticFieldPainter(
      controller: widget.controller,
      elapsed: _elapsed,
      backgroundColor: widget.backgroundColor,
      onParticleCount: _recordParticleCount,
      automaticQualityScale: _automaticQualityScale,
    );
  }

  void _removePointer(PointerEvent event) {
    if (!widget.enablePointer) return;
    widget.controller.removePointer(
      event.pointer,
      timestamp: event.timeStamp,
    );
  }

  @override
  void didUpdateWidget(covariant KineticFieldView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _statsWindowStartedAt = _elapsed.value;
      _frameCount = 0;
      _frameTimeMicros = 0;
      _particleCount = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      image: true,
      label: widget.semanticLabel,
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = ui.Size(
              constraints.hasBoundedWidth
                  ? math.max(1, constraints.maxWidth)
                  : 300,
              constraints.hasBoundedHeight
                  ? math.max(1, constraints.maxHeight)
                  : 300,
            );
            final field = CustomPaint(
              size: size,
              painter: _resolvePainter(),
            );

            if (!widget.enablePointer) return field;
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) => _updatePointer(event, size),
              onPointerMove: (event) => _updatePointer(event, size),
              onPointerHover: (event) => _updatePointer(event, size),
              onPointerUp: _removePointer,
              onPointerCancel: _removePointer,
              child: field,
            );
          },
        ),
      ),
    );
  }
}
