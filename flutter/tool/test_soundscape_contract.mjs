import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

class FakeAudioParam {
  constructor(value = 0) {
    this.value = value;
  }

  cancelScheduledValues() {}
  setValueAtTime(value) { this.value = value; }
  linearRampToValueAtTime(value) { this.value = value; }
  exponentialRampToValueAtTime(value) { this.value = value; }
}

class FakeNode {
  connect(target) { return target; }
  disconnect() {}
}

class FakeOscillator extends FakeNode {
  constructor(context) {
    super();
    this.context = context;
    this.frequency = new FakeAudioParam(220);
    this.type = "sine";
    this.onended = null;
    this.active = false;
  }

  start() {
    if (this.active) return;
    this.active = true;
    this.context.activeOscillators += 1;
    this.context.peakOscillators = Math.max(
      this.context.peakOscillators,
      this.context.activeOscillators,
    );
  }

  stop(when) {
    if (when == null) this.finish();
  }

  finish() {
    if (!this.active) return;
    this.active = false;
    this.context.activeOscillators -= 1;
    this.onended?.();
  }
}

class FakeGain extends FakeNode {
  constructor() {
    super();
    this.gain = new FakeAudioParam();
  }
}

class FakePanner extends FakeNode {
  constructor() {
    super();
    this.pan = new FakeAudioParam();
  }
}

class FakeCompressor extends FakeNode {
  constructor() {
    super();
    this.threshold = new FakeAudioParam();
    this.knee = new FakeAudioParam();
    this.ratio = new FakeAudioParam();
    this.attack = new FakeAudioParam();
    this.release = new FakeAudioParam();
  }
}

class FakeWaveShaper extends FakeNode {
  curve = null;
  oversample = "none";
}

const contexts = [];
class FakeAudioContext {
  constructor() {
    this.state = "suspended";
    this.currentTime = 1;
    this.destination = new FakeNode();
    this.oscillators = [];
    this.activeOscillators = 0;
    this.peakOscillators = 0;
    contexts.push(this);
  }

  createOscillator() {
    const oscillator = new FakeOscillator(this);
    this.oscillators.push(oscillator);
    return oscillator;
  }

  createGain() { return new FakeGain(); }
  createStereoPanner() { return new FakePanner(); }
  createDynamicsCompressor() { return new FakeCompressor(); }
  createWaveShaper() { return new FakeWaveShaper(); }
  async resume() { this.state = "running"; }
  async suspend() { this.state = "suspended"; }
  async close() { this.state = "closed"; }
}

function eventTarget() {
  const listeners = new Map();
  return {
    addEventListener(type, listener) {
      const values = listeners.get(type) ?? [];
      values.push(listener);
      listeners.set(type, values);
    },
    removeEventListener(type, listener) {
      listeners.set(
        type,
        (listeners.get(type) ?? []).filter((value) => value !== listener),
      );
    },
    dispatch(type) {
      for (const listener of listeners.get(type) ?? []) listener();
    },
  };
}

const windowEvents = eventTarget();
const documentEvents = eventTarget();
const windowObject = {
  ...windowEvents,
  AudioContext: FakeAudioContext,
  setTimeout,
};
const documentObject = {
  ...documentEvents,
  hidden: false,
};
const context = vm.createContext({
  window: windowObject,
  document: documentObject,
  Float32Array,
  Math,
  Number,
  Object,
  Promise,
  String,
  Boolean,
});

const toolDirectory = path.dirname(fileURLToPath(import.meta.url));
const sourcePath = path.join(
  toolDirectory,
  "../apps/kinetic_field_web/web/soundscape/kinetic_field_soundscape.js",
);
const source = fs.readFileSync(sourcePath, "utf8");
vm.runInContext(source, context, { filename: sourcePath });

const bridge = windowObject.kineticFieldSoundscape;
assert.equal(typeof bridge.enable, "function");
assert.equal(typeof bridge.disable, "function");
assert.equal(typeof bridge.update, "function");
assert.equal(bridge.getState().enabled, false);
assert.equal(bridge.getState().volume, 0.2);
assert.doesNotMatch(source, /\bfetch\s*\(/);
assert.doesNotMatch(source, /new\s+Audio\s*\(/);

bridge.setVolume(4);
assert.equal(bridge.getState().volume, 1);
documentObject.hidden = true;
assert.equal(await bridge.enable(), false);
assert.equal(contexts.length, 0);
documentObject.hidden = false;
assert.equal(await bridge.enable(), true);
assert.equal(contexts.length, 1);
assert.equal(contexts[0].oscillators.length, 3);

bridge.update("firefly-stars", 0.8, 2, 0.2, 0.4, 0.8, 0.6, false);
assert.equal(bridge.getState().sceneId, "fireflies");
assert.equal(bridge.getState().voiceCount, 4);
bridge.update("firefly-stars", 0.9, 2, 0.2, 0.4, 0.8, 0.6, false);
assert.equal(bridge.getState().voiceCount, 4);
assert.equal(contexts[0].oscillators.length, 4);
assert.equal(contexts[0].peakOscillators, 4);

contexts[0].oscillators[3].finish();
contexts[0].currentTime = 2;
bridge.update("firefly-stars", 0.2, 2, 0.2, 0.4, 0.8, 0.6, false);
bridge.update("firefly-stars", 0.8, 2, 0.2, 0.4, 0.8, 0.6, false);
assert.equal(bridge.getState().voiceCount, 4);
assert.equal(contexts[0].activeOscillators, 4);
assert.equal(contexts[0].peakOscillators, 4);

assert.equal(await bridge.disable(), true);
assert.equal(bridge.getState().enabled, false);
assert.equal(bridge.getState().contextState, "suspended");

await bridge.enable();
documentObject.hidden = true;
documentObject.dispatch("visibilitychange");
await new Promise((resolve) => setTimeout(resolve, 140));
assert.equal(bridge.getState().enabled, false);
assert.equal(bridge.getState().contextState, "suspended");

windowObject.dispatch("pagehide");
await new Promise((resolve) => setTimeout(resolve, 0));
assert.equal(bridge.getState().voiceCount, 0);
assert.equal(bridge.getState().contextState, "closed");

documentObject.hidden = false;
assert.equal(await bridge.enable(), true);
assert.equal(contexts.length, 2);
assert.equal(bridge.getState().voiceCount, 3);
await bridge.dispose();
assert.equal(bridge.getState().voiceCount, 0);
assert.equal(await bridge.enable(), true);
assert.equal(contexts.length, 3);
assert.equal(bridge.getState().voiceCount, 3);
await bridge.dispose();
console.log("Soundscape bridge contract checks passed.");
