const double defaultSoundscapeVolume = 0.2;

abstract interface class SoundscapeController {
  bool get isSupported;

  bool get isEnabled;

  double get volume;

  Future<bool> enable();

  Future<bool> disable();

  void setVolume(double value);

  void update({
    required String sceneId,
    required double energy,
    required int handCount,
    double? leftX,
    double? leftY,
    double? rightX,
    double? rightY,
    bool calm = false,
  });

  Future<void> dispose();
}
