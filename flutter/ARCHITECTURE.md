# Kinetic Field Flutter architecture

This repository separates **input**, **processing** and **output** so a team can
change one layer without rewriting the others.

## 1. Input

`KineticInputFrame` is the only data type accepted by the motion processor. It
contains a version, sequence number, capture time, receive time, input kind and
a list of raw normalised landmarks.

Built-in adapters:

- Web MoveNet: wrists, elbows and shoulders.
- Flutter pointer and multi-touch: one or two independent pointers.
- Native Android/iOS method channel: versioned landmark maps.
- Legacy `MotionSample`: retained as a compatibility adapter.

Input adapters must not mirror, smooth, infer velocity or render. The web host
mirrors coordinates once, immediately before ingesting the frame.

To add another input, such as MediaPipe, an accelerometer or a remote stream,
produce `KineticInputFrame` values and call `controller.ingestFrame(frame)`.

## 2. Processing

`KineticMotionProcessor` owns the common motion logic:

- Independent left and right wrist acquisition.
- One Euro filtering for slow precision and fast response.
- Confidence hysteresis and short occlusion fade.
- Velocity, speed and acceleration in viewport units per second.
- Prediction capped at 50 ms.
- Shoulder-relative hand separation.
- Open, gather, lift, settle and crossing events with cooldown.

Its output is `KineticMotionState`. Visual and audio outputs read the same state,
so they cannot disagree about which hand moved or when an event occurred.

## 3. Visual output

Every `KineticSceneStrategy` maps motion into a compact `KineticSceneFrame` with
two force emitters, tension, depth pulse, trail amount, hue phase and burst
envelope.

The portable Flutter renderer then draws:

- A deterministic particle buffer stored in typed arrays.
- Three stable procedural depth layers with perspective.
- Two independent local force fields and an optional bilateral bridge.
- Bounded glow-and-core line streaks for only the reactive particle subset.
- A world-specific renderer for Bloom, Honeybees, Fireflies or Moon Pond.

To add a world:

1. Add a `KineticScene` value.
2. Implement `KineticSceneStrategy`.
3. Implement the small scene renderer under `src/output/scenes/`.
4. Add its label, prompt and icon to the web host's `play_world.dart`.
5. Add deterministic processor, scene and widget tests.

## 4. Audio output

`SoundscapeController` is injected into the web host. Its Web Audio adapter uses
three persistent sine voices, a pooled chime, a compressor and a hard limiter.
It receives only scene ID, processed energy and hand positions.

Audio is off until the participant explicitly enables it. There are no sampled
music files, network requests or external audio licences. A native application
can replace this adapter while retaining the same processed motion input.

When reduced motion enables Calm mode, autonomous scene time is frozen. Direct
hand, pointer and touch updates still repaint immediately, so accessibility
does not remove agency from the participant.

## Performance rules

- Automatic quality begins at 4,200 field particles and adapts down after three
  slow one-second windows. It restores quality only after ten stable windows.
- Low mode uses 1,600 particles; High mode caps the field at 6,800.
- The renderer precomputes particle home positions, depth, phase and colour.
- Particle influence uses a polynomial falloff instead of a Gaussian.
- Trails are limited to no more than one quarter of the field.
- Automatic quality scales both the shared depth field and world-specific
  particle groups.
- Full-canvas blur, image filters and repeated save-layer operations are
  intentionally avoided.

MoveNet and CanvasKit can contend for the same integrated GPU. Any future WebGL
output should be benchmarked with camera inference active, not in isolation.
