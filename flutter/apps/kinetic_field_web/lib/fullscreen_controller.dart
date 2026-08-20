abstract interface class FullscreenController {
  Stream<bool> get changes;

  Future<bool> setEnabled(bool enabled);

  Future<void> dispose();
}

class UnsupportedFullscreenController implements FullscreenController {
  const UnsupportedFullscreenController();

  @override
  Stream<bool> get changes => const Stream<bool>.empty();

  @override
  Future<bool> setEnabled(bool enabled) async => false;

  @override
  Future<void> dispose() async {}
}
