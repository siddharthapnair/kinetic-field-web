# Kinetic Field

A private, platform-neutral Flutter package for movement-responsive play. It
contains versioned input models, bilateral motion processing, four scene
strategies and a responsive `CustomPainter` renderer. Camera, consent, Web
Audio, storage and platform channels remain in host applications.

## Architecture

```text
platform adapter
      ↓
KineticInputFrame version 1
      ↓
KineticMotionProcessor
      ↓
KineticMotionState
      ├── KineticSceneStrategy → KineticFieldView
      └── optional host output, such as a soundscape
```

Input adapters provide raw, normalised observations. They must not mirror,
smooth, infer velocity or render. `KineticMotionProcessor` is the single shared
processing stage, so visual and optional audio outputs can read the same motion
state.

## Four worlds

- `KineticScene.bloom`: flowers, petals and pollen.
- `KineticScene.honeybees`: a meadow with one or two guided swarms.
- `KineticScene.fireflies`: gathered lights and constellations.
- `KineticScene.moonPond`: ripples, luminous koi and lilies.

Each world has its own `KineticSceneStrategy` and renderer rather than being a
colour preset for one effect.

## Public API

- `KineticInputFrame`, `KineticInputKind` and
  `KineticLandmarkObservation`: versioned raw input with independent landmarks.
- `KineticMotionProcessor`, `KineticMotionState` and
  `KineticEffectorState`: filtered bilateral motion, pair features and events.
- `KineticScene`, `KineticFieldSettings` and `KineticQuality`: world, visual,
  calm-motion and particle-budget controls.
- `KineticFieldController`: input, processed motion, settings and performance
  state.
- `KineticFieldView`: responsive scene output with optional pointer handling
  and once-per-second performance reports.
- `MotionSample`: backwards-compatible single-effector input for older hosts.

## Usage

```dart
final controller = KineticFieldController(
  settings: const KineticFieldSettings(
    scene: KineticScene.bloom,
    quality: KineticQuality.automatic,
  ),
);

final field = KineticFieldView(
  controller: controller,
  onStats: (stats) {
    debugPrint('${stats.fps} fps, ${stats.particleCount} particles');
  },
);
```

Forward a raw two-hand camera frame without combining the hands:

```dart
controller.ingestFrame(
  KineticInputFrame(
    version: 1,
    sequence: 42,
    capturedAt: const Duration(milliseconds: 1200),
    receivedAt: const Duration(milliseconds: 1216),
    kind: KineticInputKind.pose,
    landmarks: const [
      KineticLandmarkObservation(
        id: KineticLandmarkId.leftWrist,
        x: 0.32,
        y: 0.48,
        confidence: 0.91,
      ),
      KineticLandmarkObservation(
        id: KineticLandmarkId.rightWrist,
        x: 0.68,
        y: 0.44,
        confidence: 0.89,
      ),
    ],
  ),
);
```

`KineticFieldView` handles mouse, stylus and touch by default. One mouse pointer
is sufficient for full play; two concurrent touch or stylus pointers remain
independent. Set `enablePointer: false` when input must come exclusively from an
external adapter. The host owns the controller and must dispose it.

## Motion processing

The processor applies independent per-axis One Euro filters to pose and native
landmarks, then adds confidence hysteresis, a short occlusion fade and
prediction capped at 50 milliseconds. It derives velocity, acceleration,
energy, shoulder-relative separation, angular velocity and open, gather, lift,
settle and crossing events. Pointer position bypasses the One Euro filter and
prediction for direct response.

Input timestamps must use a consistent monotonic epoch. Coordinates and
confidence are normalised to `0..1`. MoveNet hosts may provide wrists, elbows
and shoulders, but the package does not assume that every adapter supplies
every landmark.

## Reduced motion and performance

Set `KineticFieldSettings.calm` when the host detects a reduced-motion
preference. Calm mode reduces autonomous motion and response intensity while
preserving direct movement feedback.

Low quality uses 1,600 particles, Automatic starts at 4,200 and High uses
6,800. Automatic quality reduces its scale after three one-second windows below
45 fps and raises it after ten windows above 57 fps. Hosts can inspect
`KineticFieldStats` without coupling platform input to rendering.

## Privacy and platform boundaries

This package contains no camera, microphone, network, analytics, storage or
platform-channel code. It receives numerical observations only. Consent,
permissions, frame processing, retention and optional procedural sound belong
to the host.

The package is private, protected by the proprietary notice in `LICENSE`, and
excluded from pub.dev publication with `publish_to: none`.

## Verify

From this directory:

```bash
flutter pub get
flutter analyze
flutter test
```
