import * as poseDetection from "@tensorflow-models/pose-detection";
import "@tensorflow/tfjs-backend-webgl";
import * as tf from "@tensorflow/tfjs-core";

const MODEL_PATH = "movenet/model/model.json";
const MODEL_NAME = "MoveNet.SinglePose.Lightning.v4";
const TARGET_FPS = 30;
const FRAME_INTERVAL_MS = 1000 / TARGET_FPS;

const keypointNames = [
  "nose",
  "left_eye",
  "right_eye",
  "left_ear",
  "right_ear",
  "left_shoulder",
  "right_shoulder",
  "left_elbow",
  "right_elbow",
  "left_wrist",
  "right_wrist",
  "left_hip",
  "right_hip",
  "left_knee",
  "right_knee",
  "left_ankle",
  "right_ankle",
];

const landmarkIds = Object.freeze({
  left_wrist: "leftWrist",
  right_wrist: "rightWrist",
  left_elbow: "leftElbow",
  right_elbow: "rightElbow",
  left_shoulder: "leftShoulder",
  right_shoulder: "rightShoulder",
});

const runtime = {
  state: "idle",
  error: null,
  backend: null,
  detector: null,
  stream: null,
  video: null,
  callback: null,
  errorCallback: null,
  generation: 0,
  startPromise: null,
  stopPromise: null,
  loopPromise: null,
  frameWaitCancel: null,
  sequence: 0,
  lastCaptureAt: 0,
  lastFrameAt: 0,
};

tf.enableProdMode();

function clamp(value, minimum = 0, maximum = 1) {
  return Math.min(maximum, Math.max(minimum, value));
}

function errorText(error) {
  if (error instanceof DOMException) return `${error.name}: ${error.message}`;
  if (error instanceof Error) return `${error.name}: ${error.message}`;
  return String(error);
}

function statusSnapshot() {
  return {
    state: runtime.state,
    error: runtime.error,
    backend: runtime.backend,
    model: MODEL_NAME,
    lastFrameAt: runtime.lastFrameAt,
  };
}

function transition(state, error = null) {
  runtime.state = state;
  runtime.error = error;
  window.dispatchEvent(
    new CustomEvent("kinetic-field-movenet-state", {
      detail: statusSnapshot(),
    }),
  );
}

function resetFrameState() {
  runtime.sequence = 0;
  runtime.lastCaptureAt = 0;
  runtime.lastFrameAt = 0;
}

function createVideoSurface() {
  const video = document.createElement("video");
  video.autoplay = true;
  video.muted = true;
  video.playsInline = true;
  video.setAttribute("aria-hidden", "true");
  video.style.cssText = [
    "position:fixed",
    "left:-2px",
    "top:-2px",
    "width:1px",
    "height:1px",
    "opacity:0",
    "pointer-events:none",
  ].join(";");
  document.body.append(video);
  return video;
}

function cancelFrameWait() {
  const cancel = runtime.frameWaitCancel;
  runtime.frameWaitCancel = null;
  if (cancel) cancel();
}

function releaseMedia() {
  cancelFrameWait();

  const stream = runtime.stream;
  runtime.stream = null;
  if (stream) {
    for (const track of stream.getTracks()) {
      try {
        track.stop();
      } catch (error) {
        console.error("Kinetic Field camera track cleanup failed", error);
      }
    }
  }

  const video = runtime.video;
  runtime.video = null;
  if (video) {
    try {
      video.pause();
      video.srcObject = null;
      video.remove();
    } catch (error) {
      console.error("Kinetic Field camera surface cleanup failed", error);
    }
  }
}

function disposeDetector() {
  const detector = runtime.detector;
  runtime.detector = null;
  if (detector) detector.dispose();
}

function clearCallbacks() {
  runtime.callback = null;
  runtime.errorCallback = null;
}

function failRuntime(error, generation = runtime.generation) {
  if (generation !== runtime.generation) return;

  const message = errorText(error);
  const onError = runtime.errorCallback;
  runtime.generation += 1;
  transition("error", message);

  try {
    disposeDetector();
  } catch (cleanupError) {
    console.error("Kinetic Field MoveNet detector cleanup failed", cleanupError);
  }
  releaseMedia();
  runtime.backend = null;
  clearCallbacks();

  if (typeof onError === "function") {
    try {
      onError(message);
    } catch (callbackError) {
      console.error("Kinetic Field MoveNet error callback failed", callbackError);
    }
  }
}

function stopForPrivacy(reason) {
  if (runtime.state !== "starting" && runtime.state !== "running") return;
  failRuntime(new DOMException(reason, "AbortError"));
}

async function acquireCamera() {
  if (!window.isSecureContext) {
    throw new DOMException(
      "Camera permission requires HTTPS or a trusted localhost origin.",
      "NotAllowedError",
    );
  }
  if (!navigator.mediaDevices?.getUserMedia) {
    throw new DOMException(
      "A usable browser camera is unavailable.",
      "NotFoundError",
    );
  }

  return navigator.mediaDevices.getUserMedia({
    video: {
      facingMode: "user",
      width: { ideal: 640 },
      height: { ideal: 480 },
      frameRate: { ideal: TARGET_FPS, max: TARGET_FPS },
    },
    audio: false,
  });
}

async function createLocalDetector() {
  const backendReady = await tf.setBackend("webgl");
  if (!backendReady) throw new Error("The TensorFlow.js WebGL backend is unavailable.");
  await tf.ready();
  runtime.backend = tf.getBackend();

  const modelUrl = new URL(MODEL_PATH, document.baseURI);
  if (modelUrl.origin !== window.location.origin) {
    throw new Error("The MoveNet model must be loaded from this app's origin.");
  }

  return poseDetection.createDetector(poseDetection.SupportedModels.MoveNet, {
    modelType: poseDetection.movenet.modelType.SINGLEPOSE_LIGHTNING,
    enableSmoothing: false,
    modelUrl: modelUrl.href,
  });
}

function rawLandmarks(pose, video) {
  const width = video.videoWidth;
  const height = video.videoHeight;
  if (!pose?.keypoints || width <= 0 || height <= 0) return [];

  return pose.keypoints.flatMap((keypoint, index) => {
    const name = keypoint.name ?? keypointNames[index];
    const id = landmarkIds[name];
    const x = Number(keypoint.x);
    const y = Number(keypoint.y);
    if (!id || !Number.isFinite(x) || !Number.isFinite(y)) return [];

    const rawConfidence = Number(keypoint.score ?? 0);
    return [{
      id,
      x: clamp(x / width),
      y: clamp(y / height),
      confidence: Number.isFinite(rawConfidence) ? clamp(rawConfidence) : 0,
    }];
  });
}

function framePacket(pose, video, capturedAtMs, completedAtMs) {
  runtime.sequence += 1;
  runtime.lastFrameAt = completedAtMs;
  return {
    version: 1,
    sequence: runtime.sequence,
    capturedAtMs,
    completedAtMs,
    landmarks: rawLandmarks(pose, video),
  };
}

function emitFrame(packet) {
  const callback = runtime.callback;
  if (typeof callback !== "function") return;
  try {
    callback(packet);
  } catch (error) {
    console.error("Kinetic Field MoveNet frame callback failed", error);
  }
}

function waitForVideoFrame(generation) {
  const video = runtime.video;
  if (!video || generation !== runtime.generation) return Promise.resolve(null);

  return new Promise((resolve) => {
    let settled = false;
    let frameCallbackId = null;
    let timerId = null;

    const finish = (capturedAtMs) => {
      if (settled) return;
      settled = true;
      if (timerId !== null) window.clearTimeout(timerId);
      if (
        frameCallbackId !== null &&
        typeof video.cancelVideoFrameCallback === "function"
      ) {
        try {
          video.cancelVideoFrameCallback(frameCallbackId);
        } catch (error) {
          console.error("Kinetic Field video-frame cleanup failed", error);
        }
      }
      if (runtime.frameWaitCancel === cancel) runtime.frameWaitCancel = null;
      resolve(capturedAtMs);
    };
    const cancel = () => finish(null);
    runtime.frameWaitCancel = cancel;

    if (typeof video.requestVideoFrameCallback === "function") {
      try {
        frameCallbackId = video.requestVideoFrameCallback((now, metadata) => {
          frameCallbackId = null;
          const presentationTime = Number(metadata?.presentationTime);
          finish(Number.isFinite(presentationTime) ? presentationTime : now);
        });
        timerId = window.setTimeout(
          () => finish(performance.now()),
          FRAME_INTERVAL_MS * 2,
        );
      } catch {
        timerId = window.setTimeout(
          () => finish(performance.now()),
          FRAME_INTERVAL_MS,
        );
      }
    } else {
      timerId = window.setTimeout(
        () => finish(performance.now()),
        FRAME_INTERVAL_MS,
      );
    }
  });
}

async function inferenceLoop(generation) {
  while (generation === runtime.generation && runtime.state === "running") {
    if (document.hidden) {
      stopForPrivacy("Camera stopped because the page was hidden.");
      break;
    }

    const capturedAtMs = await waitForVideoFrame(generation);
    if (
      capturedAtMs === null ||
      generation !== runtime.generation ||
      runtime.state !== "running"
    ) {
      break;
    }

    if (capturedAtMs - runtime.lastCaptureAt < FRAME_INTERVAL_MS * 0.9) {
      continue;
    }
    runtime.lastCaptureAt = capturedAtMs;

    try {
      if (runtime.video?.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
        const poses = await runtime.detector.estimatePoses(
          runtime.video,
          { maxPoses: 1 },
          capturedAtMs,
        );
        if (generation !== runtime.generation || runtime.state !== "running") break;
        const completedAtMs = performance.now();
        emitFrame(
          framePacket(poses[0], runtime.video, capturedAtMs, completedAtMs),
        );
      }
    } catch (error) {
      failRuntime(error, generation);
      break;
    }
  }
}

async function startInternal(onFrame, onError, generation) {
  transition("starting");
  resetFrameState();
  runtime.callback = onFrame;
  runtime.errorCallback = onError;

  try {
    if (document.hidden) {
      throw new DOMException(
        "Camera cannot start while the page is hidden.",
        "NotAllowedError",
      );
    }
    runtime.stream = await acquireCamera();
    if (generation !== runtime.generation) {
      releaseMedia();
      return;
    }

    runtime.video = createVideoSurface();
    runtime.video.srcObject = runtime.stream;
    await runtime.video.play();
    if (generation !== runtime.generation) {
      releaseMedia();
      return;
    }

    runtime.detector = await createLocalDetector();
    if (generation !== runtime.generation) {
      disposeDetector();
      releaseMedia();
      return;
    }

    transition("running");
    runtime.loopPromise = inferenceLoop(generation).finally(() => {
      runtime.loopPromise = null;
    });
  } catch (error) {
    disposeDetector();
    releaseMedia();
    if (generation !== runtime.generation) return;
    transition("error", errorText(error));
    clearCallbacks();
    throw error;
  }
}

function start(onFrame, onError) {
  if (typeof onFrame !== "function") {
    return Promise.reject(new TypeError("MoveNet start requires a frame callback."));
  }
  if (onError != null && typeof onError !== "function") {
    return Promise.reject(new TypeError("MoveNet onError must be a function."));
  }
  const errorCallback = typeof onError === "function" ? onError : null;
  if (runtime.state === "running") {
    runtime.callback = onFrame;
    runtime.errorCallback = errorCallback;
    return Promise.resolve();
  }
  if (runtime.startPromise) {
    runtime.callback = onFrame;
    runtime.errorCallback = errorCallback;
    return runtime.startPromise;
  }
  if (runtime.stopPromise) {
    return runtime.stopPromise.then(() => start(onFrame, errorCallback));
  }

  const begin = async () => {
    if (runtime.state === "error") {
      if (runtime.loopPromise) await runtime.loopPromise;
      disposeDetector();
      releaseMedia();
      clearCallbacks();
      runtime.backend = null;
      resetFrameState();
    }
    const generation = runtime.generation + 1;
    runtime.generation = generation;
    await startInternal(onFrame, errorCallback, generation);
  };

  runtime.startPromise = begin().finally(() => {
    runtime.startPromise = null;
  });
  return runtime.startPromise;
}

function stop() {
  if (runtime.stopPromise) return runtime.stopPromise;

  runtime.stopPromise = (async () => {
    runtime.generation += 1;
    if (runtime.state !== "idle") transition("stopping");
    releaseMedia();

    if (runtime.startPromise) {
      try {
        await runtime.startPromise;
      } catch {
        // A failed or cancelled start is fully cleaned below.
      }
    }
    if (runtime.loopPromise) await runtime.loopPromise;

    disposeDetector();
    clearCallbacks();
    runtime.backend = null;
    resetFrameState();
    transition("idle");
  })().finally(() => {
    runtime.stopPromise = null;
  });

  return runtime.stopPromise;
}

const bridge = {
  start,
  stop,
  status: statusSnapshot,
};

Object.defineProperties(bridge, {
  state: { enumerable: true, get: () => runtime.state },
  error: { enumerable: true, get: () => runtime.error },
});

window.kineticFieldMoveNet = Object.freeze(bridge);

document.addEventListener("visibilitychange", () => {
  if (document.hidden) {
    stopForPrivacy("Camera stopped because the page was hidden.");
  }
});

window.addEventListener("pagehide", () => {
  stopForPrivacy("Camera stopped because the page was left.");
});
