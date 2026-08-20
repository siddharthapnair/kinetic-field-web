import 'package:flutter/services.dart';
import 'package:kinetic_field/kinetic_field.dart';

/// Native channel used by Android and iOS hosts to control Kinetic Field.
const kineticFieldMotionChannel = MethodChannel(
  'ai.zeuron.kinetic_field/motion',
);

/// Decodes the native module protocol and forwards validated input to Flutter.
///
/// Version 1 accepts raw landmark frames. The processor in `kinetic_field`
/// remains responsible for filtering, velocity, prediction and bilateral
/// features, keeping the native and web input paths consistent.
class NativeKineticFieldInputChannel {
  NativeKineticFieldInputChannel({
    required this.controller,
    this.channel = kineticFieldMotionChannel,
  });

  final KineticFieldController controller;
  final MethodChannel channel;

  bool _attached = false;

  /// Installs this decoder as the method handler for [channel].
  void attach() {
    if (_attached) return;
    _attached = true;
    channel.setMethodCallHandler(handleMethodCall);
  }

  /// Removes this decoder from [channel].
  void detach() {
    if (!_attached) return;
    _attached = false;
    channel.setMethodCallHandler(null);
  }

  /// Handles one native protocol message.
  Future<Object?> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'updateFrame':
        _updateFrame(call.arguments);
      case 'updateMotion':
        _updateLegacyMotion(call.arguments);
      case 'resetMotion':
        controller.resetMotion();
      case 'setScene':
        _setScene(call.arguments);
      default:
        throw MissingPluginException('Unknown method ${call.method}');
    }
    return null;
  }

  void _updateFrame(Object? arguments) {
    final frame = _map(arguments, method: 'updateFrame', code: 'invalid_frame');
    final version = _integer(
      frame,
      'version',
      method: 'updateFrame',
      code: 'invalid_frame',
    );
    if (version != 1) {
      throw PlatformException(
        code: 'unsupported_frame_version',
        message: 'updateFrame supports version 1, received $version.',
      );
    }

    final sequence = _integer(
      frame,
      'sequence',
      method: 'updateFrame',
      code: 'invalid_frame',
    );
    if (sequence < 0) {
      throw PlatformException(
        code: 'invalid_frame',
        message: 'updateFrame sequence must not be negative.',
      );
    }

    final capturedAtMs = _finiteNumber(
      frame,
      'capturedAtMs',
      method: 'updateFrame',
      code: 'invalid_frame',
    );
    final receivedAtMs = _finiteNumber(
      frame,
      'receivedAtMs',
      method: 'updateFrame',
      code: 'invalid_frame',
    );
    if (capturedAtMs < 0 || receivedAtMs < capturedAtMs) {
      throw PlatformException(
        code: 'invalid_frame',
        message:
            'updateFrame timestamps must be non-negative and receivedAtMs '
            'must not precede capturedAtMs.',
      );
    }

    final rawLandmarks = frame['landmarks'];
    if (rawLandmarks is! List) {
      throw PlatformException(
        code: 'invalid_frame',
        message: 'updateFrame landmarks must be a list.',
      );
    }

    final ids = <KineticLandmarkId>{};
    final landmarks = <KineticLandmarkObservation>[];
    for (var index = 0; index < rawLandmarks.length; index += 1) {
      final rawLandmark = _map(
        rawLandmarks[index],
        method: 'updateFrame landmark $index',
        code: 'invalid_frame',
      );
      final rawId = rawLandmark['id'];
      if (rawId is! String) {
        throw PlatformException(
          code: 'invalid_frame',
          message: 'updateFrame landmark $index id must be a string.',
        );
      }
      final id = _landmarkId(rawId);
      if (!ids.add(id)) {
        throw PlatformException(
          code: 'invalid_frame',
          message: 'updateFrame contains duplicate landmark id $rawId.',
        );
      }
      landmarks.add(
        KineticLandmarkObservation(
          id: id,
          x: _finiteNumber(
            rawLandmark,
            'x',
            method: 'updateFrame landmark $index',
            code: 'invalid_frame',
          ),
          y: _finiteNumber(
            rawLandmark,
            'y',
            method: 'updateFrame landmark $index',
            code: 'invalid_frame',
          ),
          confidence: _finiteNumber(
            rawLandmark,
            'confidence',
            method: 'updateFrame landmark $index',
            code: 'invalid_frame',
            fallback: 1,
          ),
        ),
      );
    }

    controller.ingestFrame(
      KineticInputFrame(
        version: version,
        sequence: sequence,
        capturedAt: _milliseconds(capturedAtMs),
        receivedAt: _milliseconds(receivedAtMs),
        kind: KineticInputKind.native,
        landmarks: landmarks,
      ),
    );
  }

  void _updateLegacyMotion(Object? arguments) {
    final motion = _map(
      arguments,
      method: 'updateMotion',
      code: 'invalid_motion',
    );
    controller.updateMotion(
      MotionSample(
        x: _number(
          motion,
          'x',
          method: 'updateMotion',
          code: 'invalid_motion',
          required: true,
        ),
        y: _number(
          motion,
          'y',
          method: 'updateMotion',
          code: 'invalid_motion',
          required: true,
        ),
        vx: _number(
          motion,
          'vx',
          method: 'updateMotion',
          code: 'invalid_motion',
        ),
        vy: _number(
          motion,
          'vy',
          method: 'updateMotion',
          code: 'invalid_motion',
        ),
        energy: _number(
          motion,
          'energy',
          method: 'updateMotion',
          code: 'invalid_motion',
        ),
        confidence: _number(
          motion,
          'confidence',
          method: 'updateMotion',
          code: 'invalid_motion',
          fallback: 1,
        ),
        timestamp: Duration(
          milliseconds: _number(
            motion,
            'timestampMs',
            method: 'updateMotion',
            code: 'invalid_motion',
          ).round(),
        ),
      ),
    );
  }

  void _setScene(Object? arguments) {
    if (arguments is! String) {
      throw PlatformException(
        code: 'invalid_scene',
        message: 'setScene expects a scene name string.',
      );
    }
    final scene = switch (arguments) {
      'bloom' => KineticScene.bloom,
      'honeybees' => KineticScene.honeybees,
      'fireflies' => KineticScene.fireflies,
      'moonPond' => KineticScene.moonPond,
      _ => throw PlatformException(
        code: 'invalid_scene',
        message: 'Unknown Kinetic Field scene $arguments.',
      ),
    };
    controller.updateSettings(controller.settings.copyWith(scene: scene));
  }

  KineticLandmarkId _landmarkId(String value) => switch (value) {
    'leftWrist' => KineticLandmarkId.leftWrist,
    'rightWrist' => KineticLandmarkId.rightWrist,
    'leftElbow' => KineticLandmarkId.leftElbow,
    'rightElbow' => KineticLandmarkId.rightElbow,
    'leftShoulder' => KineticLandmarkId.leftShoulder,
    'rightShoulder' => KineticLandmarkId.rightShoulder,
    'primaryPointer' => KineticLandmarkId.primaryPointer,
    'secondaryPointer' => KineticLandmarkId.secondaryPointer,
    _ => throw PlatformException(
      code: 'unsupported_landmark',
      message: 'Unsupported Kinetic Field landmark id $value.',
    ),
  };

  Map<dynamic, dynamic> _map(
    Object? value, {
    required String method,
    required String code,
  }) {
    if (value is Map) return value;
    throw PlatformException(code: code, message: '$method expects a map.');
  }

  int _integer(
    Map<dynamic, dynamic> arguments,
    String key, {
    required String method,
    required String code,
  }) {
    final value = arguments[key];
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    throw PlatformException(
      code: code,
      message: '$method $key must be an integer.',
    );
  }

  double _finiteNumber(
    Map<dynamic, dynamic> arguments,
    String key, {
    required String method,
    required String code,
    double? fallback,
  }) {
    final value = arguments[key];
    if (value is num && value.isFinite) return value.toDouble();
    if (value == null && fallback != null) return fallback;
    throw PlatformException(
      code: code,
      message: '$method $key must be a finite number.',
    );
  }

  double _number(
    Map<dynamic, dynamic> arguments,
    String key, {
    required String method,
    required String code,
    double fallback = 0,
    bool required = false,
  }) {
    final value = arguments[key];
    if (value is num) return value.toDouble();
    if (!required && value == null) return fallback;
    throw PlatformException(
      code: code,
      message: '$method $key must be numeric.',
    );
  }

  Duration _milliseconds(double value) =>
      Duration(microseconds: (value * 1000).round());
}
