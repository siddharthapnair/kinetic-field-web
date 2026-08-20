import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_field_web/soundscape_platform.dart';

void main() {
  test('stub soundscape is off, bounded and safe to call', () async {
    final controller = createPlatformSoundscapeController();

    expect(controller.isSupported, isFalse);
    expect(controller.isEnabled, isFalse);
    expect(controller.volume, 0.2);
    expect(await controller.enable(), isFalse);

    controller.setVolume(2);
    expect(controller.volume, 1);
    controller.setVolume(-1);
    expect(controller.volume, 0);
    controller.setVolume(double.nan);
    expect(controller.volume, 0);

    controller.update(
      sceneId: 'fireflies',
      energy: 0.8,
      handCount: 2,
      leftX: 0.2,
      leftY: 0.4,
      rightX: 0.8,
      rightY: 0.6,
      calm: true,
    );
    expect(await controller.disable(), isTrue);
    await controller.dispose();
  });
}
