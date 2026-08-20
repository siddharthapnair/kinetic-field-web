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

assert.doesNotMatch(
  source,
  /flipHorizontal\s*:\s*true/,
  "Dart's Mirror camera setting must be the only horizontal transform.",
);
assert.match(source, /function start\(onPose, onError\)/);
assert.match(source, /onError\(message\)/);
assert.match(source, /document\.addEventListener\("visibilitychange"/);
assert.match(source, /window\.addEventListener\("pagehide"/);
assert.match(source, /function failRuntime[\s\S]*disposeDetector\(\)[\s\S]*releaseMedia\(\)/);

for (const required of [
  "kineticFieldMoveNet",
  "movenet/model/model.json",
  "visibilitychange",
  "pagehide",
  "MoveNet onError must be a function.",
]) {
  assert.ok(bundle.includes(required), `Generated bundle is missing: ${required}`);
}

console.log("[movenet] browser bridge contract verified");
