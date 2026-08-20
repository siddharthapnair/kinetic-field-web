# Kinetic Field native module

This is the Flutter add-to-app entry point for embedding Kinetic Field in an
existing Android or iOS application. The reusable field itself lives in
`../../packages/kinetic_field`; this module supplies a minimal full-screen route
that native hosts can present with a `FlutterEngine`.

The module deliberately has no camera dependency. A Flutter host can inject a
`KineticFieldController`. An Android or iOS host can send `updateMotion` and
`resetMotion` calls over the `ai.zeuron.kinetic_field/motion` method channel.
`updateMotion` accepts normalised numeric `x`, `y`, `vx`, `vy`, `energy`,
`confidence` and `timestampMs` values. The package clamps unsafe values before
rendering.

## Verify

```bash
flutter pub get
flutter analyze
flutter test
```

See Flutter's add-to-app documentation for the Android and iOS host integration
steps: <https://docs.flutter.dev/add-to-app>.
