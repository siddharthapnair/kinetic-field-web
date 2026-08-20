import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_field/kinetic_field.dart';
import 'package:kinetic_field_module/main.dart';

void main() {
  testWidgets('module renders the reusable kinetic field', (tester) async {
    await tester.pumpWidget(const KineticFieldModuleApp());
    await tester.pump();

    expect(find.byType(KineticFieldView), findsOneWidget);
    expect(
      find.bySemanticsLabel('A particle field shaped by pointer movement'),
      findsOneWidget,
    );
  });

  testWidgets('native channel forwards normalised motion', (tester) async {
    final controller = KineticFieldController();
    await tester.pumpWidget(KineticFieldModuleApp(controller: controller));

    final response = Completer<ByteData?>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          kineticFieldMotionChannel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('updateMotion', <String, Object>{
              'x': 0.24,
              'y': 0.68,
              'vx': 0.1,
              'vy': -0.04,
              'energy': 0.7,
              'confidence': 0.9,
              'timestampMs': 32,
            }),
          ),
          response.complete,
        );
    await response.future;

    expect(controller.motion.x, 0.24);
    expect(controller.motion.y, 0.68);
    expect(controller.motion.energy, 0.7);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
