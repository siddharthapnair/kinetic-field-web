import * as poseDetection from "@tensorflow-models/pose-detection";
import "@tensorflow/tfjs-backend-webgl";
import * as tf from "@tensorflow/tfjs-core";

const MODEL_PATH = "movenet/model/model.json";
const MODEL_NAME = "MoveNet.SinglePose.Lightning.v4";
const INFERENCE_INTERVAL_MS = 1000 / 24;
const NOMINAL_FRAME_MS = 1000 / 60;
const MIN_KEYPOINT_SCORE = 0.35;
const MIN_KEYPOINTS = 4;

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

const bodyWeights = {
  nose: 0.45,
  left_eye: 0.2,
  right_eye: 0.2,
  left_ear: 0.25,
  right_ear: 0.25,
  left_shoulder: 1.15,
  right_shoulder: 1.15,
  left_elbow: 1.4,
  right_elbow: 1.4,
  left_wrist: 1.8,
  right_wrist: 1.8,
  left_hip: 1,
  right_hip: 1,
  left_knee: 0.8,
  right_knee: 0.8,
  left_ankle: 0.75,
  right_ankle: 0.75,
};

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
  previousPoints: new Map(),
  previousTimestamp: 0,
  lastSample: {
    x: 0.5,
    y: 0.5,
    vx: 0,
    vy: 0,
    energy: 0,
    confidence: 0,
    timestampMs: 0,
  },
};

tf.enableProdMode();

function clamp(value, minimum = 0, maximum = 1) {
  return Math.min(maximum, Math.max(minimum, value));
}

function mix(current, target, amount) {
  return current + (target - current) * amount;
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
    lastSampleAt: runtime.lastSample.timestampMs,
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

function resetTracking() {
  runtime.previousPoints.clear();
  runtime.previousTimestamp = 0;
  runtime.lastSample = {
    x: 0.5,
    y: 0.5,
    vx: 0,
    vy: 0,
    energy: 0,
    confidence: 0,
    timestampMs: 0,
  };
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

function releaseMedia() {
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
      height: { ideal: 360 },
      frameRate: { ideal: 24, max: 30 },
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
    enableSmoothing: true,
    modelUrl: modelUrl.href,
  });
}

function normaliseKeypoints(pose, width, height) {
  if (!pose?.keypoints || width <= 0 || height <= 0) return [];

  return pose.keypoints.flatMap((keypoint, index) => {
    const score = Number(keypoint.score ?? 0);
    const x = Number(keypoint.x);
    const y = Number(keypoint.y);
    if (score < MIN_KEYPOINT_SCORE || !Number.isFinite(x) || !Number.isFinite(y)) {
      return [];
    }

    const name = keypoint.name ?? keypointNames[index] ?? `keypoint_${index}`;
    return [{
      name,
      score,
      x: clamp(x / width),
      y: clamp(y / height),
      weight: bodyWeights[name] ?? 0.5,
    }];
  });
}

function decayedSample(timestampMs) {
  const previous = runtime.lastSample;
  const sample = {
    x: previous.x,
    y: previous.y,
    vx: previous.vx * 0.68,
    vy: previous.vy * 0.68,
    energy: previous.energy * 0.72,
    confidence: 0,
    timestampMs,
  };
  runtime.lastSample = sample;
  if (timestampMs - runtime.previousTimestamp > 300) {
    runtime.previousPoints.clear();
    runtime.previousTimestamp = 0;
  }
  return sample;
}

function motionSample(pose, video, timestampMs) {
  const points = normaliseKeypoints(pose, video.videoWidth, video.videoHeight);
  if (points.length < MIN_KEYPOINTS) return decayedSample(timestampMs);

  const elapsedMs = timestampMs - runtime.previousTimestamp;
  const canMeasureVelocity =
    runtime.previousTimestamp > 0 && elapsedMs >= 8 && elapsedMs <= 300;
  const frameScale = canMeasureVelocity
    ? NOMINAL_FRAME_MS / Math.max(elapsedMs, 8)
    : 0;

  let positionWeight = 0;
  let positionX = 0;
  let positionY = 0;
  let velocityWeight = 0;
  let velocityX = 0;
  let velocityY = 0;
  let movement = 0;
  let confidenceWeight = 0;
  let confidence = 0;
  const nextPoints = new Map();

  for (const point of points) {
    nextPoints.set(point.name, point);
    const baseWeight = point.weight * point.score;
    const previous = runtime.previousPoints.get(point.name);
    const vx = previous && canMeasureVelocity
      ? (point.x - previous.x) * frameScale
      : 0;
    const vy = previous && canMeasureVelocity
      ? (point.y - previous.y) * frameScale
      : 0;
    const speed = Math.hypot(vx, vy);
    const activeWeight = baseWeight * (0.22 + Math.min(speed * 18, 1.8));

    positionX += point.x * activeWeight;
    positionY += point.y * activeWeight;
    positionWeight += activeWeight;
    velocityX += vx * activeWeight;
    velocityY += vy * activeWeight;
    velocityWeight += activeWeight;
    movement += speed * baseWeight;
    confidence += point.score * point.weight;
    confidenceWeight += point.weight;
  }

  runtime.previousPoints = nextPoints;
  runtime.previousTimestamp = timestampMs;

  const targetX = positionWeight > 0 ? positionX / positionWeight : 0.5;
  const targetY = positionWeight > 0 ? positionY / positionWeight : 0.5;
  const targetVx = velocityWeight > 0 ? velocityX / velocityWeight : 0;
  const targetVy = velocityWeight > 0 ? velocityY / velocityWeight : 0;
  const meanMovement = confidenceWeight > 0 ? movement / confidenceWeight : 0;
  const targetEnergy = clamp(
    meanMovement * 11 + Math.hypot(targetVx, targetVy) * 3.5,
  );
  const previous = runtime.lastSample;
  const energyResponse = targetEnergy > previous.energy ? 0.42 : 0.14;

  const sample = {
    x: clamp(mix(previous.x, targetX, 0.48)),
    y: clamp(mix(previous.y, targetY, 0.48)),
    vx: clamp(mix(previous.vx, targetVx, 0.38), -1, 1),
    vy: clamp(mix(previous.vy, targetVy, 0.38), -1, 1),
    energy: clamp(mix(previous.energy, targetEnergy, energyResponse)),
    confidence: clamp(confidenceWeight > 0 ? confidence / confidenceWeight : 0),
    timestampMs,
  };
  runtime.lastSample = sample;
  return sample;
}

function emitSample(sample) {
  const callback = runtime.callback;
  if (typeof callback !== "function") return;
  try {
    callback(
      sample.x,
      sample.y,
      sample.vx,
      sample.vy,
      sample.energy,
      sample.confidence,
      sample.timestampMs,
    );
  } catch (error) {
    console.error("Kinetic Field MoveNet callback failed", error);
  }
}

function delay(milliseconds) {
  return new Promise((resolve) => window.setTimeout(resolve, milliseconds));
}

async function inferenceLoop(generation) {
  while (generation === runtime.generation && runtime.state === "running") {
    if (document.hidden) {
      stopForPrivacy("Camera stopped because the page was hidden.");
      break;
    }

    const startedAt = performance.now();
    try {
      if (runtime.video?.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
        const poses = await runtime.detector.estimatePoses(
          runtime.video,
          { maxPoses: 1 },
          startedAt,
        );
        if (generation !== runtime.generation || runtime.state !== "running") break;
        emitSample(motionSample(poses[0], runtime.video, performance.now()));
      }
    } catch (error) {
      failRuntime(error, generation);
      break;
    }

    const elapsed = performance.now() - startedAt;
    await delay(Math.max(0, INFERENCE_INTERVAL_MS - elapsed));
  }
}

async function startInternal(onPose, onError, generation) {
  transition("starting");
  resetTracking();
  runtime.callback = onPose;
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

function start(onPose, onError) {
  if (typeof onPose !== "function") {
    return Promise.reject(new TypeError("MoveNet start requires a pose callback."));
  }
  if (onError != null && typeof onError !== "function") {
    return Promise.reject(new TypeError("MoveNet onError must be a function."));
  }
  const errorCallback = typeof onError === "function" ? onError : null;
  if (runtime.state === "running") {
    runtime.callback = onPose;
    runtime.errorCallback = errorCallback;
    return Promise.resolve();
  }
  if (runtime.startPromise) {
    runtime.callback = onPose;
    runtime.errorCallback = errorCallback;
    return runtime.startPromise;
  }
  if (runtime.stopPromise) {
    return runtime.stopPromise.then(() => start(onPose, errorCallback));
  }

  const begin = async () => {
    if (runtime.state === "error") {
      if (runtime.loopPromise) await runtime.loopPromise;
      disposeDetector();
      releaseMedia();
      clearCallbacks();
      runtime.backend = null;
      resetTracking();
    }
    const generation = runtime.generation + 1;
    runtime.generation = generation;
    await startInternal(onPose, errorCallback, generation);
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
    resetTracking();
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
