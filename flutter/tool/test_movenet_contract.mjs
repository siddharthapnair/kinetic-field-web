import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolDirectory = path.dirname(fileURLToPath(import.meta.url));
const source = await readFile(
  path.join(toolDirectory, "movenet_bridge_entry.js"),
  "utf8",
);
const bundle = await readFile(
  path.join(
    toolDirectory,
    "../apps/kinetic_field_web/web/movenet/kinetic_field_movenet.js",
  ),
  "utf8",
);
const dartAdapter = await readFile(
  path.join(
    toolDirectory,
    "../apps/kinetic_field_web/lib/pose_source_web.dart",
  ),
  "utf8",
);

assert.doesNotMatch(
  source,
  /flipHorizontal\s*:\s*true/,
  "Dart's Mirror camera setting must be the only horizontal transform.",
);
assert.doesNotMatch(source, /MIN_KEYPOINT|motionSample|decayedSample|emitSample/);
assert.doesNotMatch(source, /\b(?:vx|vy|energy|centroid)\b/);
assert.match(source, /const TARGET_FPS = 30/);
assert.match(source, /width: \{ ideal: 640 \}/);
assert.match(source, /height: \{ ideal: 480 \}/);
assert.match(source, /enableSmoothing: false/);
assert.match(source, /requestVideoFrameCallback/);
assert.match(source, /function start\(onFrame, onError\)/);
assert.match(source, /onError\(message\)/);
assert.match(source, /document\.addEventListener\("visibilitychange"/);
assert.match(source, /window\.addEventListener\("pagehide"/);
assert.match(source, /function failRuntime[\s\S]*disposeDetector\(\)[\s\S]*releaseMedia\(\)/);

for (const id of [
  "leftWrist",
  "rightWrist",
  "leftElbow",
  "rightElbow",
  "leftShoulder",
  "rightShoulder",
]) {
  assert.ok(source.includes(`"${id}"`), `Bridge source is missing landmark: ${id}`);
  assert.ok(
    dartAdapter.includes(`'${id}' => KineticLandmarkId.${id}`),
    `Dart adapter is missing landmark: ${id}`,
  );
}

assert.ok(dartAdapter.includes("kind: KineticInputKind.pose"));
assert.ok(dartAdapter.includes("capturedAt: _milliseconds(capturedAtMs)"));
assert.ok(dartAdapter.includes("receivedAt: _milliseconds(completedAtMs)"));

for (const field of [
  "version: 1",
  "sequence: runtime.sequence",
  "capturedAtMs",
  "completedAtMs",
  "landmarks: rawLandmarks",
]) {
  assert.ok(source.includes(field), `Bridge source is missing packet field: ${field}`);
}

for (const required of [
  "kineticFieldMoveNet",
  "movenet/model/model.json",
  "visibilitychange",
  "pagehide",
  "leftWrist",
  "rightWrist",
  "capturedAtMs",
  "completedAtMs",
  "MoveNet onError must be a function.",
]) {
  assert.ok(bundle.includes(required), `Generated bundle is missing: ${required}`);
}

console.log("[movenet] browser bridge contract verified");
