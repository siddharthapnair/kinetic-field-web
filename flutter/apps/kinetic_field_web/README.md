# Kinetic Field Flutter web host

Flutter web shell for the reusable `kinetic_field` package. It provides the
camera consent flow, MoveNet pose-source boundary, pointer fallback, responsive
controls and presentation mode.

## Run

```bash
flutter pub get
flutter run -d chrome
```

## Verify

```bash
flutter analyze
flutter test
flutter build web --release
```

The web bridge is expected at `window.kineticFieldMoveNet`, with asynchronous
`start(onPose)` and `stop()` methods. Model files and related MoveNet assets must
be served from the same origin as the app. Camera frames remain in the browser;
only normalised pose observations cross into Flutter, and no frames are stored
or uploaded. The interface typeface is bundled under `assets/fonts`, so text
rendering also has no runtime CDN dependency.
