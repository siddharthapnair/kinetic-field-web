# Kinetic Field for Flutter

The Flutter implementation is split into three layers so that the visual field,
native embedding and web-specific camera stack remain independent.

- `packages/kinetic_field`: reusable renderer, controller, settings and motion
  model. It has no camera or platform dependency.
- `modules/kinetic_field_module`: Flutter add-to-app entry point for existing
  Android and iOS applications.
- `apps/kinetic_field_web`: deployable Flutter web experience. It owns consent,
  camera lifecycle, responsive controls and the MoveNet bridge.
- `tool`: reproducible, checksum-pinned MoveNet and TensorFlow.js vendoring.

The web app loads TensorFlow.js, the pose-detection code and MoveNet SinglePose
Lightning weights from its own origin. Camera frames are processed in a hidden
local video element and never cross the JavaScript-to-Dart boundary. Flutter
receives only normalised motion observations.

## Production build

```bash
cd apps/kinetic_field_web
flutter pub get
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --csp
```

`--no-web-resources-cdn` keeps Flutter's runtime assets on the same host. The
separate `firebase.flutter.json` deploys this build only to the explicitly bound
`kinetic-field-flutter` Hosting target.
