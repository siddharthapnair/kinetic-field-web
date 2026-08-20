# Local MoveNet runtime

This directory is a self-contained browser runtime for the Flutter host. It
contains a single esbuild bundle plus the TensorFlow.js graph model and its two
weight shards. Nothing is loaded from a CDN at runtime.

The bridge exposed to Dart is:

```text
window.kineticFieldMoveNet.start(onPose, onError?) -> Promise<void>
window.kineticFieldMoveNet.stop()                  -> Promise<void>
```

`onPose` receives `x, y, vx, vy, energy, confidence, timestampMs` at no more
than 24 Hz. Coordinates remain in the camera's unmirrored frame and within
`0..1`; the Flutter host's Mirror camera switch owns the horizontal transform.
Velocity is measured in normalised viewport units per nominal 60 Hz frame.
Energy and confidence remain within `0..1`; the timestamp uses the page's
monotonic performance clock.

The optional `onError` callback receives a human-readable string if inference
fails after `start` has resolved. The bridge disposes the detector and releases
all camera tracks before notifying it. Calling `start(onPose)` remains valid for
non-Flutter hosts that do not need asynchronous failure reporting.

For privacy, the bridge also releases the camera and detector when the document
becomes hidden or receives `pagehide`. This is reported through `onError`; the
host must require an explicit user action before starting the camera again.

`status()` and the read-only `state` and `error` properties are available for
diagnostics. State transitions also emit the `kinetic-field-movenet-state`
window event.

To verify the model checksums and rebuild the local bundle:

```bash
cd flutter/tool
npm ci
npm run vendor:movenet
node test_movenet_contract.mjs
```

Add `-- --refresh-model` to download fresh copies from the official TensorFlow
examples repository. Downloads happen only during this explicit build step.
