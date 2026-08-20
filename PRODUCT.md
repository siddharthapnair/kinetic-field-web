# Product

## Register

product

## Users

Kinetic Field is designed for children, adults and older people, including
elders who may prefer slower, clearer interaction. It supports individual play
on a laptop as well as shared use with a projector or large display. A parent,
carer, educator or facilitator may help with camera consent and settings.

This is an inclusive play experience. It is not an assessment, therapeutic
intervention or diagnostic tool, and no developmental or clinical outcome is
claimed.

## Product purpose

Turn ordinary movement into immediate, legible feedback without specialist
hardware. A normal laptop webcam can track both wrists independently, while a
mouse, stylus or one or two touch points provide a complete fallback. The
participant should understand the connection between movement and response
before needing to read instructions.

## Four play worlds

- **Bloom**: separate the hands to open flowers and release pollen.
- **Honeybees**: guide one or two gentle swarms through a meadow.
- **Fireflies**: gather lights, then become still to place a constellation.
- **Moon Pond**: guide luminous koi, create ripples and settle the water.

Each world has its own interaction strategy and renderer. They share the same
processed motion state, but do more than change colour.

## Interaction architecture

```text
webcam, pointer, touch or native host
                  ↓
       KineticInputFrame version 1
       raw independent landmarks
                  ↓
        KineticMotionProcessor
 One Euro filtering, prediction, pair events
             ↙              ↘
    visual scene output    optional sound
```

The camera bridge supplies separate wrist, elbow and shoulder observations for
the left and right sides. It does not average the hands into one centroid,
smooth them or infer velocity. The shared processor applies per-axis One Euro
filtering, confidence hysteresis, short occlusion fade and prediction capped at
50 milliseconds. It then derives position, velocity, energy, separation,
rotation and open, gather, lift, settle and crossing events.

Pointer input bypasses positional filtering and prediction for direct response.
One mouse pointer is a complete interaction; two simultaneous touch or stylus
points remain independent effectors.

## Experience principles

1. Movement is the interface. Feedback begins with the first usable hand or
   pointer observation.
2. Two hands should enrich the interaction, not become a requirement.
3. Make causality visible. Position, speed, separation and stillness should
   produce distinct responses.
4. Preserve the canvas. World selection and controls stay clear, compact and
   dismissible.
5. Avoid failure states in play. A denied or unavailable camera falls back to
   pointer input.
6. Privacy and accessibility are architectural constraints, not optional
   polish.

## Privacy and sound

Camera frames and MoveNet inference remain in the browser. Raw video does not
cross into Flutter, and no image is stored or uploaded. Only normalised numeric
landmarks cross the bridge. The app requests no microphone access. Hiding the
page stops the camera and suspends sound; leaving it also cleans up the audio
graph.

The optional soundscape is off by default, begins only after an explicit user
action and uses locally generated tones. It contains no samples, streaming
music or runtime audio CDN. Visual play remains complete with sound disabled.

## Accessibility and performance

- Respect the operating system's reduced-motion preference and retain direct
  hand or pointer response while reducing autonomous motion and intensity.
- Offer a calm setting, keyboard shortcuts, readable status text and pointer or
  touch alternatives to camera input.
- Do not rely on colour alone for camera or control status.
- Keep scene selection usable at compact laptop sizes and short landscape
  heights.
- Provide Low, Automatic and High quality modes. Automatic quality responds to
  measured frame rate, reducing particle density after sustained slow windows
  and restoring it only after sustained stable performance.

## Brand personality

Immersive, responsive and precise. The experience should feel alive, warm and
slightly uncanny, but never chaotic or technically intimidating.

## Anti-references

Do not make this look like an analytics dashboard, generic neon AI product,
crypto interface or control-heavy creative tool. Avoid decorative
glassmorphism, dense permanent panels, gratuitous copy and effects that do not
respond to the participant.
