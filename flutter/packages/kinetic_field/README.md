# Kinetic Field

A private, reusable Flutter package for rendering a dark motion-responsive
particle vortex. It is deliberately platform-neutral: camera, pose, depth and
sensor integrations stay in the host application and provide normalised
`MotionSample` values to the package.

## Public API

- `MotionSample`: position, velocity, energy, confidence and source timestamp
- `KineticFieldSettings`: force, radius, swirl, turbulence, point size, colour
  speed, quality and calm-motion controls
- `KineticFieldController`: motion, pointer, settings and statistics state
- `KineticFieldView`: responsive `CustomPainter` field with optional pointer
  handling and once-per-second performance reports

## Usage

```dart
final controller = KineticFieldController();

KineticFieldView(
  controller: controller,
  onStats: (stats) {
    debugPrint('${stats.fps} fps, ${stats.particleCount} particles');
  },
)
```

Forward an external motion observation:

```dart
controller.updateMotion(
  const MotionSample(
    x: 0.62,
    y: 0.38,
    vx: 0.04,
    vy: -0.02,
    energy: 0.74,
    confidence: 0.91,
    timestamp: Duration(milliseconds: 1200),
  ),
);
```

Update controls immutably:

```dart
controller.updateSettings(
  controller.settings.copyWith(
    force: 1.4,
    radius: 0.36,
    quality: KineticQuality.high,
    calm: false,
  ),
);
```

`KineticFieldView` handles mouse, stylus and touch input by default. Set
`enablePointer: false` when motion must come exclusively from an external
tracker. The host owns the controller and must dispose it.

## Privacy and platform boundaries

This package contains no camera, microphone, storage, network, analytics or
platform-channel code. It receives numerical motion samples only. Any consent,
permission, frame processing and retention policy belongs to the host app.

This module is private and is protected by the proprietary notice in
`LICENSE`. It is excluded from pub.dev publication with `publish_to: none`.
