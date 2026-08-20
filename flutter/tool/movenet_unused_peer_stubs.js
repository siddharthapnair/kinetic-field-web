// The pose-detection package publishes every detector through one ESM entry.
// That entry imports MediaPipe Pose and WebGPU even when only MoveNet with the
// TensorFlow.js WebGL runtime is used. These unreachable stubs keep those two
// optional engines out of the browser bundle without leaving external imports.
export class Pose {}
export class WebGPUBackend {}
export const webgpu_util = Object.freeze({});
