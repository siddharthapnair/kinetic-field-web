import 'soundscape_controller.dart';

class UnsupportedSoundscapeController implements SoundscapeController {
  double _volume = defaultSoundscapeVolume;

  @override
  bool get isSupported => false;

  @override
  bool get isEnabled => false;

  @override
  double get volume => _volume;

  @override
  Future<bool> enable() async => false;

  @override
  Future<bool> disable() async => true;

  @override
  void setVolume(double value) {
    if (value.isFinite) _volume = value.clamp(0.0, 1.0);
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
  }) {}

  @override
  Future<void> dispose() async {}
}

SoundscapeController createPlatformSoundscapeController() =>
    UnsupportedSoundscapeController();
