@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_field_web/soundscape_platform.dart';

void main() {
  test(
    'web controller maps promises, bounds and optional coordinates',
    () async {
      final bridge = JSObject();
      var enabled = false;
      var volume = 0.2;
      final updates = <List<JSAny?>>[];

      void exposeState() {
        bridge.setProperty('supported'.toJS, true.toJS);
        bridge.setProperty('enabled'.toJS, enabled.toJS);
        bridge.setProperty('volume'.toJS, volume.toJS);
      }

      exposeState();
      bridge.setProperty(
        'enable'.toJS,
        (() {
          enabled = true;
          exposeState();
          return Future<JSBoolean>.value(true.toJS).toJS;
        }).toJS,
      );
      bridge.setProperty(
        'disable'.toJS,
        (() {
          enabled = false;
          exposeState();
          return Future<JSBoolean>.value(true.toJS).toJS;
        }).toJS,
      );
      bridge.setProperty(
        'setVolume'.toJS,
        ((JSNumber value) {
          volume = value.toDartDouble;
          exposeState();
        }).toJS,
      );
      bridge.setProperty(
        'update'.toJS,
        ((
              JSString sceneId,
              JSNumber energy,
              JSNumber handCount,
              JSNumber? leftX,
              JSNumber? leftY,
              JSNumber? rightX,
              JSNumber? rightY,
              JSBoolean calm,
            ) {
              updates.add(<JSAny?>[
                sceneId,
                energy,
                handCount,
                leftX,
                leftY,
                rightX,
                rightY,
                calm,
              ]);
            })
            .toJS,
      );
      bridge.setProperty(
        'dispose'.toJS,
        (() => Future<JSAny?>.value(null).toJS).toJS,
      );
      globalContext.setProperty('kineticFieldSoundscape'.toJS, bridge);

      final controller = createPlatformSoundscapeController();
      expect(controller.isSupported, isTrue);
      expect(controller.isEnabled, isFalse);
      expect(controller.volume, 0.2);
      expect(await controller.enable(), isTrue);
      expect(controller.isEnabled, isTrue);

      controller.setVolume(4);
      expect(controller.volume, 1);
      controller.update(
        sceneId: ' stars ',
        energy: 2,
        handCount: 4,
        leftX: -1,
        leftY: 0.4,
        rightX: double.nan,
        rightY: 2,
        calm: true,
      );

      expect(updates, hasLength(1));
      final update = updates.single;
      expect((update[0]! as JSString).toDart, 'stars');
      expect((update[1]! as JSNumber).toDartDouble, 1);
      expect((update[2]! as JSNumber).toDartDouble, 2);
      expect((update[3]! as JSNumber).toDartDouble, 0);
      expect((update[4]! as JSNumber).toDartDouble, 0.4);
      expect(update[5], isNull);
      expect((update[6]! as JSNumber).toDartDouble, 1);
      expect((update[7]! as JSBoolean).toDart, isTrue);

      expect(await controller.disable(), isTrue);
      expect(controller.isEnabled, isFalse);
      await controller.dispose();
      globalContext.delete('kineticFieldSoundscape'.toJS);
    },
  );
}
