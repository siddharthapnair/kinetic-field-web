import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_field/kinetic_field.dart';
import 'package:kinetic_field_module/main.dart';
import 'package:kinetic_field_module/native_input_channel.dart';

Map<String, Object> _frame({
  int version = 1,
  int sequence = 1,
  Object? landmarks,
}) {
  return <String, Object>{
    'version': version,
    'sequence': sequence,
    'capturedAtMs': 100.25,
    'receivedAtMs': 108.5,
    'landmarks':
        landmarks ??
        <Object>[
          <String, Object>{
            'id': 'leftWrist',
            'x': 0.22,
            'y': 0.42,
            'confidence': 0.92,
          },
          <String, Object>{
            'id': 'rightWrist',
            'x': 0.78,
            'y': 0.46,
            'confidence': 0.88,
          },
        ],
  };
}

Matcher _platformError(String code) =>
    isA<PlatformException>().having((error) => error.code, 'code', code);

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

  test('versioned frame preserves two independent hands', () async {
    final controller = KineticFieldController();
    addTearDown(controller.dispose);
    final input = NativeKineticFieldInputChannel(controller: controller);

    await input.handleMethodCall(MethodCall('updateFrame', _frame()));

    expect(controller.motionState.visibleEffectorCount, 2);
    expect(controller.motionState.left.x, closeTo(0.22, 0.0001));
    expect(controller.motionState.left.y, closeTo(0.42, 0.0001));
    expect(controller.motionState.right.x, closeTo(0.78, 0.0001));
    expect(controller.motionState.right.y, closeTo(0.46, 0.0001));
    expect(controller.motionState.left.confidence, closeTo(0.92, 0.0001));
    expect(controller.motionState.right.confidence, closeTo(0.88, 0.0001));
    expect(controller.motionState.separation, greaterThan(0.5));
    expect(controller.motion.timestamp.inMicroseconds, 100250);
  });

  test('versioned frame accepts every supported landmark id', () async {
    final controller = KineticFieldController();
    addTearDown(controller.dispose);
    final input = NativeKineticFieldInputChannel(controller: controller);
    final ids = <String>[
      'leftWrist',
      'rightWrist',
      'leftElbow',
      'rightElbow',
      'leftShoulder',
      'rightShoulder',
      'primaryPointer',
      'secondaryPointer',
    ];

    await input.handleMethodCall(
      MethodCall(
        'updateFrame',
        _frame(
          landmarks: <Object>[
            for (var index = 0; index < ids.length; index += 1)
              <String, Object>{
                'id': ids[index],
                'x': 0.1 + index * 0.08,
                'y': 0.2 + index * 0.05,
                'confidence': 0.9,
              },
          ],
        ),
      ),
    );

    expect(controller.motionState.visibleEffectorCount, 2);
    expect(controller.motionState.shoulderSpan, greaterThan(0.08));
  });

  test('invalid versioned payloads return typed platform errors', () async {
    final controller = KineticFieldController();
    addTearDown(controller.dispose);
    final input = NativeKineticFieldInputChannel(controller: controller);

    await expectLater(
      input.handleMethodCall(MethodCall('updateFrame', _frame(version: 2))),
      throwsA(_platformError('unsupported_frame_version')),
    );
    await expectLater(
      input.handleMethodCall(
        MethodCall(
          'updateFrame',
          _frame(
            landmarks: <Object>[
              <String, Object>{
                'id': 'leftHand',
                'x': 0.2,
                'y': 0.3,
                'confidence': 0.9,
              },
            ],
          ),
        ),
      ),
      throwsA(_platformError('unsupported_landmark')),
    );
    await expectLater(
      input.handleMethodCall(
        MethodCall('updateFrame', <String, Object>{
          ..._frame(),
          'landmarks': 7,
        }),
      ),
      throwsA(_platformError('invalid_frame')),
    );
    await expectLater(
      input.handleMethodCall(
        MethodCall(
          'updateFrame',
          _frame(
            landmarks: <Object>[
              <String, Object>{'id': 'leftWrist', 'x': 0.2, 'y': 0.3},
              <String, Object>{'id': 'leftWrist', 'x': 0.4, 'y': 0.5},
            ],
          ),
        ),
      ),
      throwsA(_platformError('invalid_frame')),
    );
  });

  test('legacy updateMotion and resetMotion remain compatible', () async {
    final controller = KineticFieldController();
    addTearDown(controller.dispose);
    final input = NativeKineticFieldInputChannel(controller: controller);

    await input.handleMethodCall(
      const MethodCall('updateMotion', <String, Object>{
        'x': 0.24,
        'y': 0.68,
        'vx': 0.1,
        'vy': -0.04,
        'energy': 0.7,
        'confidence': 0.9,
        'timestampMs': 32,
      }),
    );
    expect(controller.motion.x, 0.24);
    expect(controller.motion.y, 0.68);
    expect(controller.motion.energy, 0.7);

    await input.handleMethodCall(const MethodCall('resetMotion'));
    expect(controller.motion.energy, 0);
    expect(controller.motionState, KineticMotionState.idle);
  });

  test('setScene selects every supported play world', () async {
    final controller = KineticFieldController();
    addTearDown(controller.dispose);
    final input = NativeKineticFieldInputChannel(controller: controller);
    final scenes = <String, KineticScene>{
      'bloom': KineticScene.bloom,
      'honeybees': KineticScene.honeybees,
      'fireflies': KineticScene.fireflies,
      'moonPond': KineticScene.moonPond,
    };

    for (final entry in scenes.entries) {
      await input.handleMethodCall(MethodCall('setScene', entry.key));
      expect(controller.settings.scene, entry.value);
    }
    await expectLater(
      input.handleMethodCall(const MethodCall('setScene', 'ocean')),
      throwsA(_platformError('invalid_scene')),
    );
  });

  testWidgets('module attaches the native channel handler', (tester) async {
    final controller = KineticFieldController();
    await tester.pumpWidget(KineticFieldModuleApp(controller: controller));

    final response = Completer<ByteData?>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          kineticFieldMotionChannel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('setScene', 'fireflies'),
          ),
          response.complete,
        );
    final encodedResponse = await response.future;
    const StandardMethodCodec().decodeEnvelope(encodedResponse!);

    expect(controller.settings.scene, KineticScene.fireflies);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
