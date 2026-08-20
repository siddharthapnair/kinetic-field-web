import 'dart:async';
import 'dart:js_interop';

import 'fullscreen_controller.dart';

@JS('document')
external _FullscreenDocument get _document;

extension type _FullscreenDocument(JSObject _) implements JSObject {
  external _FullscreenElement get documentElement;
  external JSObject? get fullscreenElement;

  external JSPromise<JSAny?> exitFullscreen();
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
}

extension type _FullscreenElement(JSObject _) implements JSObject {
  external JSPromise<JSAny?> requestFullscreen();
}

class WebFullscreenController implements FullscreenController {
  WebFullscreenController() {
    _listener = ((JSAny? _) => _reportBrowserState()).toJS;
    _document.addEventListener('fullscreenchange', _listener);
  }

  final StreamController<bool> _changes = StreamController<bool>.broadcast(
    sync: true,
  );
  late final JSFunction _listener;
  bool _disposed = false;

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  Future<bool> setEnabled(bool enabled) async {
    if (_disposed) return false;

    try {
      if (enabled && _document.fullscreenElement == null) {
        await _document.documentElement.requestFullscreen().toDart;
      } else if (!enabled && _document.fullscreenElement != null) {
        await _document.exitFullscreen().toDart;
      }
    } catch (_) {
      // Fullscreen can be declined by the browser or platform policy.
    }

    return _document.fullscreenElement != null;
  }

  void _reportBrowserState() {
    if (!_disposed) {
      _changes.add(_document.fullscreenElement != null);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _document.removeEventListener('fullscreenchange', _listener);
    await _changes.close();
  }
}

FullscreenController createPlatformFullscreenController() =>
    WebFullscreenController();
