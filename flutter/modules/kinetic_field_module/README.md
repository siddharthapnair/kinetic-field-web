# Kinetic Field native module

This is the Flutter add-to-app entry point for embedding Kinetic Field in an
existing Android or iOS application. The reusable field itself lives in
`../../packages/kinetic_field`; this module supplies a minimal full-screen route
that native hosts can present with a `FlutterEngine`.

The module deliberately has no camera dependency. A Flutter host can inject a
`KineticFieldController`. Android and iOS hosts send versioned raw landmark
frames over the `ai.zeuron.kinetic_field/motion` method channel. Filtering,
velocity, prediction and bilateral features remain inside the shared package.

## Native channel protocol

`updateFrame` accepts the version 1 payload below. Times use milliseconds from
one monotonic clock. Coordinates and confidence are normalised to `0..1` by the
shared package.

```json
{
  "version": 1,
  "sequence": 42,
  "capturedAtMs": 1200.25,
  "receivedAtMs": 1210.50,
  "landmarks": [
    {"id": "leftWrist", "x": 0.24, "y": 0.45, "confidence": 0.93},
    {"id": "rightWrist", "x": 0.76, "y": 0.43, "confidence": 0.91}
  ]
}
```

Supported landmark identifiers are `leftWrist`, `rightWrist`, `leftElbow`,
`rightElbow`, `leftShoulder`, `rightShoulder`, `primaryPointer` and
`secondaryPointer`. Empty landmark lists are valid and allow existing tracks to
fade naturally.

`setScene` accepts one string: `bloom`, `honeybees`, `fireflies` or `moonPond`.
`resetMotion` takes no arguments.

The legacy `updateMotion` call remains available for existing hosts. It accepts
normalised numeric `x`, `y`, `vx`, `vy`, `energy`, `confidence` and
`timestampMs` values, but new integrations should use `updateFrame` so both
hands remain independent.

## Verify

```bash
flutter pub get
flutter analyze
flutter test
```

See Flutter's add-to-app documentation for the Android and iOS host integration
steps: <https://docs.flutter.dev/add-to-app>.
