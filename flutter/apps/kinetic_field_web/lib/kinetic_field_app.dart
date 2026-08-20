import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kinetic_field/kinetic_field.dart';

import 'fullscreen_controller.dart';
import 'pose_source.dart';

const _ink950 = Color(0xFF050810);
const _ink900 = Color(0xFF101722);
const _paper = Color(0xFFF1F5F7);
const _muted = Color(0xFFA7B5C1);
const _dim = Color(0xFF8293A1);
const _cyan = Color(0xFF54E1E6);
const _danger = Color(0xFFFF907E);

enum CameraLifecycleState {
  idle,
  requesting,
  active,
  denied,
  unavailable,
  failed,
}

typedef PresentationModeCallback = FutureOr<void> Function(bool enabled);

class KineticFieldApp extends StatelessWidget {
  const KineticFieldApp({
    required this.poseSourceFactory,
    this.controller,
    this.fullscreenController,
    this.onPresentationModeChanged,
    super.key,
  });

  final PoseSourceFactory poseSourceFactory;
  final KineticFieldController? controller;
  final FullscreenController? fullscreenController;
  final PresentationModeCallback? onPresentationModeChanged;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kinetic Field',
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      home: KineticFieldExperience(
        poseSourceFactory: poseSourceFactory,
        controller: controller,
        fullscreenController: fullscreenController,
        onPresentationModeChanged: onPresentationModeChanged,
      ),
    );
  }
}

class KineticFieldExperience extends StatefulWidget {
  const KineticFieldExperience({
    required this.poseSourceFactory,
    this.controller,
    this.fullscreenController,
    this.onPresentationModeChanged,
    super.key,
  });

  final PoseSourceFactory poseSourceFactory;
  final KineticFieldController? controller;
  final FullscreenController? fullscreenController;
  final PresentationModeCallback? onPresentationModeChanged;

  @override
  State<KineticFieldExperience> createState() => _KineticFieldExperienceState();
}

class _KineticFieldExperienceState extends State<KineticFieldExperience> {
  late final PoseSource _poseSource;
  late final KineticFieldController _controller;
  late final bool _ownsController;
  late final StreamSubscription<PoseObservation> _poseSubscription;
  late final FullscreenController _fullscreenController;
  late final StreamSubscription<bool> _fullscreenSubscription;

  CameraLifecycleState _cameraState = CameraLifecycleState.idle;
  KineticFieldStats _stats = KineticFieldStats.zero;
  Timer? _hideTimer;
  int _cameraOperation = 0;
  bool _introVisible = true;
  bool _settingsOpen = false;
  bool _interfaceVisible = true;
  bool _presentationMode = false;
  bool _mirrorCamera = true;
  bool _reducedMotionApplied = false;

  bool get _cameraActive => _cameraState == CameraLifecycleState.active;
  KineticFieldSettings get _settings => _controller.settings;

  @override
  void initState() {
    super.initState();
    _poseSource = widget.poseSourceFactory();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? KineticFieldController();
    _fullscreenController =
        widget.fullscreenController ?? const UnsupportedFullscreenController();
    _poseSubscription = _poseSource.observations.listen(
      _applyPose,
      onError: _handlePoseError,
    );
    _fullscreenSubscription = _fullscreenController.changes.listen(
      _applyPresentationState,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && !_reducedMotionApplied) {
      _reducedMotionApplied = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_settings.calm) {
          _setSettings(_settings.copyWith(calm: true));
        }
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    unawaited(_poseSubscription.cancel());
    unawaited(_poseSource.dispose());
    unawaited(_fullscreenSubscription.cancel());
    unawaited(_releaseFullscreen());
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _releaseFullscreen() async {
    if (_presentationMode) {
      await _fullscreenController.setEnabled(false);
    }
    await _fullscreenController.dispose();
  }

  void _applyPose(PoseObservation pose) {
    if (!_cameraActive) return;
    _controller.updateMotion(
      MotionSample(
        x: _mirrorCamera ? 1 - pose.x : pose.x,
        y: pose.y,
        vx: _mirrorCamera ? -pose.vx : pose.vx,
        vy: pose.vy,
        energy: pose.energy,
        confidence: pose.confidence,
        timestamp: pose.timestamp,
      ),
    );
  }

  void _handlePoseError(Object error, StackTrace stackTrace) {
    if (!mounted ||
        (_cameraState != CameraLifecycleState.active &&
            _cameraState != CameraLifecycleState.requesting)) {
      return;
    }
    ++_cameraOperation;
    _hideTimer?.cancel();
    _controller.resetMotion();
    setState(() {
      _cameraState = switch (error) {
        PoseSourceException(failure: PoseSourceFailure.denied) =>
          CameraLifecycleState.denied,
        PoseSourceException(failure: PoseSourceFailure.unavailable) =>
          CameraLifecycleState.unavailable,
        _ => CameraLifecycleState.failed,
      };
      _interfaceVisible = true;
    });
  }

  Future<void> _startCamera() async {
    if (_cameraActive || _cameraState == CameraLifecycleState.requesting) {
      return;
    }
    final operation = ++_cameraOperation;
    setState(() {
      _cameraState = CameraLifecycleState.requesting;
      _interfaceVisible = true;
    });
    try {
      await _poseSource.start();
      if (!mounted || operation != _cameraOperation) {
        await _poseSource.stop();
        return;
      }
      setState(() {
        _cameraState = CameraLifecycleState.active;
        _introVisible = false;
      });
      _scheduleHide();
    } on PoseSourceException catch (error) {
      if (!mounted || operation != _cameraOperation) return;
      setState(() {
        _cameraState = switch (error.failure) {
          PoseSourceFailure.denied => CameraLifecycleState.denied,
          PoseSourceFailure.unavailable => CameraLifecycleState.unavailable,
          PoseSourceFailure.failed => CameraLifecycleState.failed,
        };
      });
    } catch (_) {
      if (mounted && operation == _cameraOperation) {
        setState(() => _cameraState = CameraLifecycleState.failed);
      }
    }
  }

  Future<void> _stopCamera() async {
    ++_cameraOperation;
    _hideTimer?.cancel();
    await _poseSource.stop();
    _controller.resetMotion();
    if (mounted) {
      setState(() {
        _cameraState = CameraLifecycleState.idle;
        _interfaceVisible = true;
      });
    }
  }

  void _toggleCamera() {
    if (_cameraState == CameraLifecycleState.requesting) return;
    unawaited(_cameraActive ? _stopCamera() : _startCamera());
  }

  void _reveal() {
    if (_presentationMode) return;
    if (!_interfaceVisible) setState(() => _interfaceVisible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_cameraActive || _introVisible || _settingsOpen) return;
    _hideTimer = Timer(const Duration(milliseconds: 4200), () {
      if (mounted && !_introVisible && !_settingsOpen) {
        setState(() => _interfaceVisible = false);
      }
    });
  }

  void _setSettings(KineticFieldSettings value) {
    _controller.updateSettings(value);
    setState(() {});
  }

  void _reset() {
    _controller.updateSettings(
      KineticFieldSettings(calm: MediaQuery.disableAnimationsOf(context)),
    );
    _controller.resetMotion();
    setState(() => _mirrorCamera = true);
  }

  void _toggleSettings() {
    _hideTimer?.cancel();
    setState(() {
      _settingsOpen = !_settingsOpen;
      _interfaceVisible = true;
    });
    if (!_settingsOpen) _scheduleHide();
  }

  Future<void> _togglePresentation() async {
    final enabled = await _fullscreenController.setEnabled(!_presentationMode);
    _applyPresentationState(enabled);
  }

  void _applyPresentationState(bool enabled) {
    if (!mounted || enabled == _presentationMode) return;
    setState(() {
      _presentationMode = enabled;
      if (enabled) {
        _introVisible = false;
        _settingsOpen = false;
      }
      _interfaceVisible = !enabled;
    });
    final callback = widget.onPresentationModeChanged;
    if (callback != null) unawaited(Future<void>.sync(() => callback(enabled)));
  }

  void _dismissUi() {
    if (_presentationMode) {
      unawaited(_togglePresentation());
      return;
    }
    setState(() {
      _introVisible = false;
      _settingsOpen = false;
      _interfaceVisible = true;
    });
    _scheduleHide();
  }

  String get _cameraMessage => switch (_cameraState) {
    CameraLifecycleState.idle => 'Pointer motion active',
    CameraLifecycleState.requesting => 'Waiting for camera permission',
    CameraLifecycleState.active => 'Camera pose active',
    CameraLifecycleState.denied =>
      'Camera access was declined. Pointer mode remains active.',
    CameraLifecycleState.unavailable =>
      'MoveNet is unavailable. Pointer mode remains active.',
    CameraLifecycleState.failed =>
      'The camera could not continue. Pointer mode remains active.',
  };

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyC): _toggleCamera,
        const SingleActivator(LogicalKeyboardKey.keyF): () =>
            unawaited(_togglePresentation()),
        const SingleActivator(LogicalKeyboardKey.keyR): _reset,
        const SingleActivator(LogicalKeyboardKey.escape): _dismissUi,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: _ink950,
          body: MouseRegion(
            onHover: (_) => _reveal(),
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _reveal(),
              onPointerMove: (_) => _reveal(),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  KineticFieldView(
                    controller: _controller,
                    enablePointer: !_cameraActive,
                    backgroundColor: _ink950,
                    semanticLabel:
                        'A particle field shaped by camera or pointer motion',
                    onStats: (stats) => setState(() => _stats = stats),
                  ),
                  const _Vignette(),
                  SafeArea(
                    minimum: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                    child: LayoutBuilder(
                      builder: (context, constraints) => _Interface(
                        size: constraints.biggest,
                        cameraState: _cameraState,
                        cameraMessage: _cameraMessage,
                        introVisible: _introVisible,
                        interfaceVisible:
                            _interfaceVisible || _introVisible || _settingsOpen,
                        settingsOpen: _settingsOpen,
                        presentationMode: _presentationMode,
                        settings: _settings,
                        stats: _stats,
                        mirrorCamera: _mirrorCamera,
                        reduceMotion: reduceMotion,
                        onWordmark: () => setState(() {
                          _introVisible = true;
                          _interfaceVisible = true;
                        }),
                        onStartCamera: _startCamera,
                        onPointerMode: () => setState(() {
                          _introVisible = false;
                          _interfaceVisible = true;
                        }),
                        onToggleCamera: _toggleCamera,
                        onToggleSettings: _toggleSettings,
                        onTogglePresentation: () =>
                            unawaited(_togglePresentation()),
                        onCloseSettings: _toggleSettings,
                        onSettingsChanged: _setSettings,
                        onMirrorChanged: (value) =>
                            setState(() => _mirrorCamera = value),
                        onReset: _reset,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Interface extends StatelessWidget {
  const _Interface({
    required this.size,
    required this.cameraState,
    required this.cameraMessage,
    required this.introVisible,
    required this.interfaceVisible,
    required this.settingsOpen,
    required this.presentationMode,
    required this.settings,
    required this.stats,
    required this.mirrorCamera,
    required this.reduceMotion,
    required this.onWordmark,
    required this.onStartCamera,
    required this.onPointerMode,
    required this.onToggleCamera,
    required this.onToggleSettings,
    required this.onTogglePresentation,
    required this.onCloseSettings,
    required this.onSettingsChanged,
    required this.onMirrorChanged,
    required this.onReset,
  });

  final Size size;
  final CameraLifecycleState cameraState;
  final String cameraMessage;
  final bool introVisible;
  final bool interfaceVisible;
  final bool settingsOpen;
  final bool presentationMode;
  final KineticFieldSettings settings;
  final KineticFieldStats stats;
  final bool mirrorCamera;
  final bool reduceMotion;
  final VoidCallback onWordmark;
  final Future<void> Function() onStartCamera;
  final VoidCallback onPointerMode;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleSettings;
  final VoidCallback onTogglePresentation;
  final VoidCallback onCloseSettings;
  final ValueChanged<KineticFieldSettings> onSettingsChanged;
  final ValueChanged<bool> onMirrorChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final compact = size.width < 620;
    final short = size.height < 640;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Stack(
      children: <Widget>[
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _FadeControls(
            visible: interfaceVisible,
            duration: duration,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                TextButton.icon(
                  onPressed: onWordmark,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    foregroundColor: _paper,
                  ),
                  icon: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _cyan),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: _cyan.withValues(alpha: 0.45),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                  ),
                  label: const Text(
                    'KINETIC FIELD',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                if (!compact) ...<Widget>[
                  const SizedBox(width: 16),
                  Flexible(
                    child: Semantics(
                      liveRegion: true,
                      label: cameraMessage,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cameraState == CameraLifecycleState.active
                                  ? _cyan
                                  : _dim,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              cameraMessage.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Positioned(
          top: short ? 48 : 68,
          bottom: short ? 64 : 80,
          left: 0,
          right: 0,
          child: _Intro(
            visible: introVisible,
            compact: compact,
            short: short,
            cameraState: cameraState,
            cameraMessage: cameraMessage,
            duration: duration,
            onStartCamera: onStartCamera,
            onPointerMode: onPointerMode,
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _FadeControls(
            visible: interfaceVisible,
            duration: duration,
            child: Center(
              child: _Dock(
                compact: compact,
                cameraState: cameraState,
                settingsOpen: settingsOpen,
                presentationMode: presentationMode,
                onCamera: onToggleCamera,
                onSettings: onToggleSettings,
                onPresentation: onTogglePresentation,
              ),
            ),
          ),
        ),
        if (settingsOpen)
          _SettingsPosition(
            size: size,
            child: _SettingsPanel(
              settings: settings,
              stats: stats,
              mirrorCamera: mirrorCamera,
              onClose: onCloseSettings,
              onChanged: onSettingsChanged,
              onMirrorChanged: onMirrorChanged,
              onReset: onReset,
            ),
          ),
      ],
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({
    required this.visible,
    required this.compact,
    required this.short,
    required this.cameraState,
    required this.cameraMessage,
    required this.duration,
    required this.onStartCamera,
    required this.onPointerMode,
  });

  final bool visible;
  final bool compact;
  final bool short;
  final CameraLifecycleState cameraState;
  final String cameraMessage;
  final Duration duration;
  final Future<void> Function() onStartCamera;
  final VoidCallback onPointerMode;

  @override
  Widget build(BuildContext context) {
    final error =
        cameraState == CameraLifecycleState.denied ||
        cameraState == CameraLifecycleState.unavailable ||
        cameraState == CameraLifecycleState.failed;
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = short
        ? 40.0
        : (width * (compact ? 0.13 : 0.074)).clamp(48.0, 108.0);
    return ExcludeSemantics(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: duration,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text(
                    'YOUR MOVEMENT BECOMES FORCE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(height: short ? 8 : 16),
                  Text(
                    'Shape motion\ninto light.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _paper,
                      fontSize: titleSize,
                      height: 0.88,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -titleSize * 0.052,
                    ),
                  ),
                  SizedBox(height: short ? 12 : 22),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 650),
                    child: const Text(
                      'A living particle field follows the movement seen by your '
                      'laptop camera. Frames stay on this device and are never uploaded.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _muted,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ),
                  SizedBox(height: short ? 14 : 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed:
                            cameraState == CameraLifecycleState.requesting
                            ? null
                            : () => unawaited(onStartCamera()),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(156, 48),
                          backgroundColor: _paper,
                          foregroundColor: _ink950,
                          shape: const StadiumBorder(),
                        ),
                        icon: const Icon(Icons.videocam_outlined, size: 19),
                        label: Text(
                          cameraState == CameraLifecycleState.requesting
                              ? 'Connecting camera'
                              : 'Enable camera',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: onPointerMode,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(170, 48),
                          foregroundColor: _muted,
                          side: BorderSide(color: _dim.withValues(alpha: 0.5)),
                          shape: const StadiumBorder(),
                        ),
                        icon: const Icon(Icons.mouse_outlined, size: 18),
                        label: const Text('Continue with pointer'),
                      ),
                    ],
                  ),
                  if (error) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      cameraMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _danger, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({
    required this.compact,
    required this.cameraState,
    required this.settingsOpen,
    required this.presentationMode,
    required this.onCamera,
    required this.onSettings,
    required this.onPresentation,
  });

  final bool compact;
  final CameraLifecycleState cameraState;
  final bool settingsOpen;
  final bool presentationMode;
  final VoidCallback onCamera;
  final VoidCallback onSettings;
  final VoidCallback onPresentation;

  @override
  Widget build(BuildContext context) {
    final active = cameraState == CameraLifecycleState.active;
    final requesting = cameraState == CameraLifecycleState.requesting;
    return Material(
      color: _ink900.withValues(alpha: 0.97),
      elevation: 12,
      shadowColor: _ink950,
      shape: StadiumBorder(
        side: BorderSide(color: _dim.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Tooltip(
              message: active ? 'Disable camera' : 'Enable camera',
              child: TextButton.icon(
                onPressed: requesting ? null : onCamera,
                style: TextButton.styleFrom(
                  minimumSize: Size(compact ? 46 : 138, 46),
                  foregroundColor: active ? _cyan : _muted,
                  backgroundColor: active
                      ? _cyan.withValues(alpha: 0.12)
                      : Colors.transparent,
                  shape: const StadiumBorder(),
                ),
                icon: Icon(
                  active
                      ? Icons.videocam_off_outlined
                      : Icons.videocam_outlined,
                  size: 19,
                ),
                label: compact
                    ? const SizedBox.shrink()
                    : Text(active ? 'Disable camera' : 'Enable camera'),
              ),
            ),
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              color: _dim.withValues(alpha: 0.3),
            ),
            _DockButton(
              tooltip: 'Field controls',
              selected: settingsOpen,
              icon: Icons.tune_rounded,
              onPressed: onSettings,
            ),
            _DockButton(
              tooltip: presentationMode
                  ? 'Exit presentation mode'
                  : 'Enter presentation mode',
              selected: presentationMode,
              icon: presentationMode
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              onPressed: onPresentation,
            ),
          ],
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.tooltip,
    required this.selected,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final bool selected;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        color: selected ? _cyan : _muted,
        style: IconButton.styleFrom(
          minimumSize: const Size(46, 46),
          backgroundColor: selected
              ? _cyan.withValues(alpha: 0.12)
              : Colors.transparent,
        ),
      ),
    );
  }
}

class _SettingsPosition extends StatelessWidget {
  const _SettingsPosition({required this.size, required this.child});

  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (size.width < 720) {
      final height = size.height < 420
          ? size.height
          : (size.height * 0.8).clamp(340.0, 680.0);
      return Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: height,
        child: child,
      );
    }
    return Positioned(top: 0, right: 0, bottom: 0, width: 384, child: child);
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.settings,
    required this.stats,
    required this.mirrorCamera,
    required this.onClose,
    required this.onChanged,
    required this.onMirrorChanged,
    required this.onReset,
  });

  final KineticFieldSettings settings;
  final KineticFieldStats stats;
  final bool mirrorCamera;
  final VoidCallback onClose;
  final ValueChanged<KineticFieldSettings> onChanged;
  final ValueChanged<bool> onMirrorChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _ink900,
      elevation: 20,
      shadowColor: _ink950,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _dim.withValues(alpha: 0.32)),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'FIELD CONTROLS',
                        style: TextStyle(
                          color: _cyan,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Shape the response',
                        style: TextStyle(
                          color: _paper,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close controls',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                  color: _muted,
                  style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: _dim.withValues(alpha: 0.25)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Range(
                    'Force',
                    settings.force,
                    0.35,
                    2.2,
                    (v) => onChanged(settings.copyWith(force: v)),
                  ),
                  _Range(
                    'Radius',
                    settings.radius,
                    0.12,
                    0.55,
                    (v) => onChanged(settings.copyWith(radius: v)),
                  ),
                  _Range(
                    'Swirl',
                    settings.swirl,
                    0,
                    2.4,
                    (v) => onChanged(settings.copyWith(swirl: v)),
                  ),
                  _Range(
                    'Turbulence',
                    settings.turbulence,
                    0,
                    1.6,
                    (v) => onChanged(settings.copyWith(turbulence: v)),
                  ),
                  _Range(
                    'Point glow',
                    settings.pointSize,
                    0.7,
                    3,
                    (v) => onChanged(settings.copyWith(pointSize: v)),
                  ),
                  _Range(
                    'Colour drift',
                    settings.colourSpeed,
                    0,
                    1.8,
                    (v) => onChanged(settings.copyWith(colourSpeed: v)),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Render quality',
                    style: TextStyle(
                      color: _paper,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 9),
                  SegmentedButton<KineticQuality>(
                    segments: const <ButtonSegment<KineticQuality>>[
                      ButtonSegment(
                        value: KineticQuality.low,
                        label: Text('LOW'),
                      ),
                      ButtonSegment(
                        value: KineticQuality.automatic,
                        label: Text('AUTO'),
                      ),
                      ButtonSegment(
                        value: KineticQuality.high,
                        label: Text('HIGH'),
                      ),
                    ],
                    selected: <KineticQuality>{settings.quality},
                    showSelectedIcon: false,
                    onSelectionChanged: (value) =>
                        onChanged(settings.copyWith(quality: value.first)),
                  ),
                  const SizedBox(height: 10),
                  _SettingSwitch(
                    title: 'Mirror camera',
                    subtitle: 'Match your movement on screen',
                    value: mirrorCamera,
                    onChanged: onMirrorChanged,
                  ),
                  _SettingSwitch(
                    title: 'Calm motion',
                    subtitle: 'Lower autonomous movement and intensity',
                    value: settings.calm,
                    onChanged: (value) =>
                        onChanged(settings.copyWith(calm: value)),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Camera frames and MoveNet inference remain in this browser.',
                    style: TextStyle(color: _dim, fontSize: 11.5, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: _dim.withValues(alpha: 0.25)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${stats.fps} FPS  ·  ${stats.particleCount} PARTICLES',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _dim,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Reset field'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    foregroundColor: _muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Range extends StatelessWidget {
  const _Range(this.label, this.value, this.min, this.max, this.onChanged);

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(
                  color: _paper,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(color: _dim, fontSize: 10.5),
              ),
            ],
          ),
          Semantics(
            label: label,
            value: value.toStringAsFixed(2),
            slider: true,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 56,
      title: Text(
        title,
        style: const TextStyle(
          color: _paper,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: _dim, fontSize: 11.5),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _FadeControls extends StatelessWidget {
  const _FadeControls({
    required this.visible,
    required this.duration,
    required this.child,
  });

  final bool visible;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: child,
        ),
      ),
    );
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 0.9,
            colors: <Color>[
              Colors.transparent,
              _ink950.withValues(alpha: 0.12),
              _ink950.withValues(alpha: 0.68),
            ],
            stops: const <double>[0.34, 0.72, 1],
          ),
        ),
      ),
    );
  }
}

ThemeData _theme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: _cyan,
    brightness: Brightness.dark,
    surface: _ink900,
    onSurface: _paper,
    error: _danger,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Roboto',
    colorScheme: scheme,
    scaffoldBackgroundColor: _ink950,
    sliderTheme: SliderThemeData(
      activeTrackColor: _cyan,
      inactiveTrackColor: _dim.withValues(alpha: 0.35),
      thumbColor: _cyan,
      overlayColor: _cyan.withValues(alpha: 0.14),
      trackHeight: 3,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? _cyan : _muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? _cyan.withValues(alpha: 0.28)
            : _ink950,
      ),
    ),
  );
}
