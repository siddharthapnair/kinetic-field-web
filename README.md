# Kinetic Field

Kinetic Field is a movement-driven Flutter play experience for children,
adults and older participants. A normal laptop webcam detects both wrists with
MoveNet, then turns position, speed, separation and stillness into layered
particle depth, trails, flowers, swarms, constellations, koi and calm sound.

The public test build is hosted in its own Firebase project:

<https://kinetic-field-play.web.app>

## Four play worlds

- **Bloom**: move each hand through flowers, pollen and opening petals.
- **Honeybees**: guide one or two gentle swarms around a meadow.
- **Fireflies**: gather lights and hold still to build a constellation.
- **Moon Pond**: guide luminous koi, create ripples and settle the water.

The shared particle field has three procedural depth layers, perspective,
bilateral vortices and reactive motion echoes. Each world adds its own renderer
and interaction strategy, rather than changing only the colour palette.

## Privacy and sound

- Camera frames, TensorFlow.js and MoveNet inference stay in the browser.
- Only six normalised pose landmarks cross into Flutter. No images are stored
  or uploaded.
- Video is requested without microphone access.
- Hiding or leaving the page releases the camera and audio graph.
- MoveNet, its model, interface fonts and Flutter rendering assets are served
  from the same origin. No runtime CDN is required.
- Sound is optional, off by default and procedurally generated. The app contains
  no sampled or streamed music, so there is no third-party music licence.

## Architecture

The Flutter code uses replaceable input, processing and output boundaries:

```text
MoveNet, pointer, touch or native host
                 ↓
          KineticInputFrame
                 ↓
       KineticMotionProcessor
     filter, prediction, pair events
            ↙              ↘
   scene strategies      soundscape
            ↓              ↓
  CustomPainter output   Web Audio
```

Important directories:

- `flutter/packages/kinetic_field`: platform-neutral input models, motion
  processor, scene strategies and Canvas output.
- `flutter/apps/kinetic_field_web`: camera lifecycle, world selector,
  soundscape adapter, responsive UI and Firebase web host.
- `flutter/modules/kinetic_field_module`: Android/iOS add-to-app module and
  versioned native method-channel input.
- `flutter/tool`: checksum-pinned MoveNet vendoring and JavaScript contracts.

See `flutter/ARCHITECTURE.md` for extension points and data contracts.

## Run the Flutter web app

```bash
cd flutter/apps/kinetic_field_web
flutter pub get
flutter run -d chrome
```

Production verification:

```bash
cd flutter/packages/kinetic_field
flutter analyze
flutter test

cd ../../apps/kinetic_field_web
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --csp
```

Verify the locally pinned MoveNet and soundscape bridges:

```bash
cd flutter/tool
npm ci
npm run vendor:movenet
npm test
npm audit
```

## Firebase release

The dedicated Firebase project is `kinetic-field-play`; its Hosting target is
`kinetic-field`. The previous Cortexz Hosting site remains separately mapped
and is not touched by this release command.

```bash
cd flutter/apps/kinetic_field_web
flutter build web --release --no-web-resources-cdn --csp

cd ../../..
firebase deploy --config firebase.kinetic-field.json \
  --only hosting:kinetic-field --project kinetic-field-play
```

Firebase supplies HTTPS, which is required for webcam access outside localhost.
The Hosting configuration disables microphone access and applies a same-origin
Content Security Policy.

## Controls

- `1` to `4`: choose Bloom, Honeybees, Fireflies or Moon Pond.
- `C`: enable or disable the camera.
- `F`: enter or leave fullscreen.
- `R`: reset the current world.
- `Escape`: close the open panel or leave presentation mode.

Camera interaction uses wrists, elbows and shoulders from MoveNet Lightning.
MoveNet does not detect individual fingers and does not measure real depth.
Depth in this experience is deliberately generated from movement, separation,
energy and the scene physics.
