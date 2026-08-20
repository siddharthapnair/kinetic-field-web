# Kinetic Field Flutter web host

The browser host for Kinetic Field, designed for children, adults and elders.
It connects a normal laptop webcam to four play worlds, while
retaining mouse, stylus and one or two touch points as a complete fallback.

- **Bloom**: open flowers and release pollen.
- **Honeybees**: guide one or two gentle swarms.
- **Fireflies**: gather lights and build a constellation.
- **Moon Pond**: guide luminous koi and settle the water.

These are play interactions, not clinical or developmental assessments.

## Run locally

From this directory:

```bash
flutter pub get
flutter run -d chrome
```

The browser will ask for camera permission only after an explicit action.
Localhost is accepted by browsers as a secure camera context.

## Input, processing and output

The local MoveNet bridge produces version 1 frames containing separate left
and right wrist, elbow and shoulder observations. It performs no smoothing,
velocity inference or hand averaging. Flutter mirrors coordinates once when
the preview mirror setting is active, then sends the raw frame through the
package's shared motion processor.

The processor applies independent One Euro filtering, confidence handling and
prediction capped at 50 milliseconds. Its bilateral state drives both the
selected visual world and the optional soundscape. Pointer position bypasses
filtering and prediction for direct fallback response.

MoveNet Lightning estimates body landmarks. It does not detect individual
fingers or measure real depth. Visual depth is procedural and derives from
movement, separation, energy and scene physics.

## Privacy and local sound

- Camera frames remain in the hidden browser video element and never cross the
  Dart bridge. Only normalised numeric landmarks enter Flutter.
- No image is uploaded or stored, and the app does not request microphone
  access.
- MoveNet, its model, fonts and rendering assets are served from the same
  origin. There is no runtime CDN dependency.
- The optional procedural soundscape is off by default at a master volume of
  0.2. It uses local Web Audio tones, no samples or streamed music.
- Hiding or leaving the page releases the camera and suspends or cleans up the
  audio graph. Camera use requires an explicit restart on return.

## Accessibility and performance

The interface provides a visible world selector, keyboard shortcuts, camera
status and pointer fallback. The operating system's reduced-motion preference
enables calm rendering, which reduces autonomous motion and intensity while
retaining direct response. Sound remains optional.

Low, Automatic and High quality modes control particle density. Automatic mode
adapts only after sustained frame-rate evidence, reducing the field after slow
windows and restoring density after a longer stable period.

Keyboard controls:

- `1` to `4`: choose Bloom, Honeybees, Fireflies or Moon Pond.
- `C`: enable or disable the camera.
- `F`: enter or leave fullscreen presentation mode.
- `R`: reset the current world.
- `Escape`: close an open panel or leave presentation mode.

## Verify locally

Run these commands from the repository root.

```bash
cd flutter/tool
npm ci
npm run vendor:movenet
npm test
npm audit

cd ../packages/kinetic_field
flutter pub get
flutter analyze
flutter test

cd ../../apps/kinetic_field_web
flutter pub get
flutter analyze
flutter test
flutter test --platform chrome test/soundscape_web_test.dart
flutter build web --release --no-web-resources-cdn --csp
```

`npm run vendor:movenet` verifies the checksum-pinned local model and rebuilds
the local bridge bundle. It downloads only missing pinned assets unless the
refresh option is requested.

## Deploy to Firebase Hosting

The dedicated Firebase project is `kinetic-field-play`; the Hosting target is
`kinetic-field`. From the repository root:

```bash
cd flutter/apps/kinetic_field_web
flutter build web --release --no-web-resources-cdn --csp

cd ../../..
firebase deploy --config firebase.kinetic-field.json \
  --only hosting:kinetic-field --project kinetic-field-play
```

Firebase Hosting supplies the HTTPS context required for camera access outside
localhost. The dedicated configuration disables microphone access and applies
a same-origin Content Security Policy.
