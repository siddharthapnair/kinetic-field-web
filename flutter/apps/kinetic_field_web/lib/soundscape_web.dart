import 'dart:js_interop';

import 'soundscape_controller.dart';
import 'soundscape_stub.dart' show UnsupportedSoundscapeController;

@JS('kineticFieldSoundscape')
external _SoundscapeBridge? get _soundscapeBridge;

extension type _SoundscapeBridge(JSObject _) implements JSObject {
  external JSBoolean get supported;
  external JSBoolean get enabled;
  external JSNumber get volume;
  external JSPromise<JSBoolean> enable();
  external JSPromise<JSBoolean> disable();
  external void setVolume(JSNumber value);
  external void update(
    JSString sceneId,
    JSNumber energy,
    JSNumber handCount,
    JSNumber? leftX,
    JSNumber? leftY,
    JSNumber? rightX,
    JSNumber? rightY,
    JSBoolean calm,
  );
  external JSPromise<JSAny?> dispose();
}

class WebSoundscapeController implements SoundscapeController {
  WebSoundscapeController._(this._bridge);

  final _SoundscapeBridge _bridge;
  bool _isDisposed = false;

  @override
  bool get isSupported => !_isDisposed && _bridge.supported.toDart;

  @override
  bool get isEnabled => !_isDisposed && _bridge.enabled.toDart;

  @override
  double get volume =>
      _isDisposed ? defaultSoundscapeVolume : _bridge.volume.toDartDouble;

  @override
  Future<bool> enable() async {
    if (_isDisposed) return false;
    try {
      return (await _bridge.enable().toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> disable() async {
    if (_isDisposed) return true;
    try {
      return (await _bridge.disable().toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  void setVolume(double value) {
    if (_isDisposed || !value.isFinite) return;
    _bridge.setVolume(value.clamp(0.0, 1.0).toJS);
  }

  @override
  void update({
    required String sceneId,
    required double energy,
    required int handCount,
    double? leftX,
    double? leftY,
    double? rightX,
    double? rightY,
    bool calm = false,
  }) {
    if (_isDisposed) return;
    _bridge.update(
      (sceneId.trim().isEmpty ? 'bloom' : sceneId.trim()).toJS,
      _unit(energy).toJS,
      handCount.clamp(0, 2).toJS,
      _optionalUnit(leftX)?.toJS,
      _optionalUnit(leftY)?.toJS,
      _optionalUnit(rightX)?.toJS,
      _optionalUnit(rightY)?.toJS,
      calm.toJS,
    );
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    try {
      await _bridge.dispose().toDart;
    } catch (_) {
      // The page may already be unloading or its audio context may be closed.
    }
  }
}

double _unit(double value) => value.isFinite ? value.clamp(0.0, 1.0) : 0;

double? _optionalUnit(double? value) {
  if (value == null || !value.isFinite) return null;
  return value.clamp(0.0, 1.0);
}

SoundscapeController createPlatformSoundscapeController() {
  final bridge = _soundscapeBridge;
  if (bridge == null) return UnsupportedSoundscapeController();
  return WebSoundscapeController._(bridge);
}
