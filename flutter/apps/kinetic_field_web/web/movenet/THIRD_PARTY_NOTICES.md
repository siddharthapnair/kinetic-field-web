# Third-party notices

## MoveNet SinglePose Lightning v4

Copyright Google LLC. Licensed under the Apache License 2.0.

The vendored TensorFlow.js graph model is the official Google MoveNet
SinglePose Lightning v4 model. The checked-in files are byte-identical to the
offline model published in the official `tensorflow/tfjs-examples` repository
and to Google’s `google/movenet/tfJs/singlepose-lightning/4` model distribution.

Source:
`https://github.com/tensorflow/tfjs-examples/tree/master/react-native/pose-detection/offline_model`

Model card:
`https://storage.googleapis.com/movenet/MoveNet.SinglePose%20Model%20Card.pdf`

## TensorFlow.js and pose detection

The browser bundle contains `@tensorflow-models/pose-detection`,
`@tensorflow/tfjs-core`, `@tensorflow/tfjs-converter` and
`@tensorflow/tfjs-backend-webgl`. These packages are copyright Google LLC and
licensed under the Apache License 2.0. The generated `.LEGAL.txt` file preserves
notices emitted by the bundle.

TensorFlow.js source: `https://github.com/tensorflow/tfjs`

TensorFlow.js models source: `https://github.com/tensorflow/tfjs-models`

## Build tooling

esbuild is used only to create the local browser bundle and is licensed under
the MIT License. It is not shipped as a runtime dependency.

Apache License 2.0: `https://www.apache.org/licenses/LICENSE-2.0`

MIT License: `https://opensource.org/license/mit`
