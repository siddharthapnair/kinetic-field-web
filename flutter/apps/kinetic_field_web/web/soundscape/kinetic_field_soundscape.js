(() => {
  "use strict";

  const DEFAULT_VOLUME = 0.2;
  const MAX_VOICES = 4;
  const PENTATONIC_STEPS = [0, 2, 4, 7, 9];
  const AudioContextClass = window.AudioContext || window.webkitAudioContext;

  const sceneProfiles = Object.freeze({
    bloom: { root: 220, interval: 4 },
    honeybee: { root: 164.81, interval: 7 },
    fireflies: { root: 261.63, interval: 9 },
    pond: { root: 146.83, interval: 2 },
  });

  const state = {
    context: null,
    master: null,
    compressor: null,
    limiter: null,
    voices: [],
    chime: null,
    enabled: false,
    disposed: false,
    volume: DEFAULT_VOLUME,
    generation: 0,
    sceneId: "bloom",
    energy: 0,
    handCount: 0,
    leftX: null,
    leftY: null,
    rightX: null,
    rightY: null,
    calm: false,
    chimeArmed: true,
    lastChimeAt: Number.NEGATIVE_INFINITY,
    lifecycleAttached: false,
  };

  function clamp(value, minimum = 0, maximum = 1) {
    const number = Number(value);
    if (!Number.isFinite(number)) return minimum;
    return Math.min(maximum, Math.max(minimum, number));
  }

  function optionalUnit(value) {
    if (value == null || !Number.isFinite(Number(value))) return null;
    return clamp(value);
  }

  function profileFor(sceneId) {
    const value = String(sceneId || "").trim().toLowerCase();
    if (value.includes("bee")) return ["honeybee", sceneProfiles.honeybee];
    if (value.includes("fire") || value.includes("star")) {
      return ["fireflies", sceneProfiles.fireflies];
    }
    if (value.includes("pond") || value.includes("moon")) {
      return ["pond", sceneProfiles.pond];
    }
    return ["bloom", sceneProfiles.bloom];
  }

  function setParam(parameter, value, seconds = 0.12) {
    const context = state.context;
    if (!context || !parameter) return;
    const now = context.currentTime;
    parameter.cancelScheduledValues(now);
    parameter.setValueAtTime(parameter.value, now);
    parameter.linearRampToValueAtTime(value, now + seconds);
  }

  function setFrequency(parameter, value) {
    const context = state.context;
    if (!context || !parameter) return;
    const now = context.currentTime;
    parameter.cancelScheduledValues(now);
    parameter.setValueAtTime(Math.max(1, parameter.value), now);
    parameter.exponentialRampToValueAtTime(Math.max(1, value), now + 0.25);
  }

  function hardLimitCurve() {
    const curve = new Float32Array(1024);
    for (let index = 0; index < curve.length; index += 1) {
      const input = (index / (curve.length - 1)) * 2 - 1;
      curve[index] = Math.min(0.9, Math.max(-0.9, input));
    }
    return curve;
  }

  function createVoice(kind, pan) {
    const context = state.context;
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    const panner = typeof context.createStereoPanner === "function"
      ? context.createStereoPanner()
      : null;

    oscillator.type = "sine";
    oscillator.frequency.value = kind === "pad" ? 110 : 220;
    gain.gain.value = 0;
    if (panner) panner.pan.value = pan;

    oscillator.connect(gain);
    if (panner) {
      gain.connect(panner);
      panner.connect(state.master);
    } else {
      gain.connect(state.master);
    }
    oscillator.start();
    return { oscillator, gain, panner, kind };
  }

  function createGraph() {
    if (!AudioContextClass || state.context) return Boolean(state.context);

    const context = new AudioContextClass({ latencyHint: "interactive" });
    const master = context.createGain();
    const compressor = context.createDynamicsCompressor();
    const limiter = context.createWaveShaper();

    master.gain.value = 0;
    compressor.threshold.value = -18;
    compressor.knee.value = 4;
    compressor.ratio.value = 16;
    compressor.attack.value = 0.003;
    compressor.release.value = 0.2;
    limiter.curve = hardLimitCurve();
    limiter.oversample = "4x";

    master.connect(compressor);
    compressor.connect(limiter);
    limiter.connect(context.destination);

    state.context = context;
    state.master = master;
    state.compressor = compressor;
    state.limiter = limiter;
    state.voices = [
      createVoice("pad", 0),
      createVoice("hand", -0.35),
      createVoice("hand", 0.35),
    ];
    return true;
  }

  function noteFrequency(root, y, offset = 0) {
    const vertical = 1 - clamp(y == null ? 0.5 : y);
    const scalePosition = Math.round(vertical * (PENTATONIC_STEPS.length - 1));
    const semitones = PENTATONIC_STEPS[scalePosition] + offset;
    return root * Math.pow(2, semitones / 12);
  }

  function updateVoice(voice, active, x, y, energy, profile, offset) {
    const calmFactor = state.calm ? 0.48 : 1;
    setFrequency(voice.oscillator.frequency, noteFrequency(profile.root, y, offset));
    setParam(
      voice.gain.gain,
      active ? (0.012 + energy * 0.035) * calmFactor : 0,
    );
    if (voice.panner) setParam(voice.panner.pan, (clamp(x ?? 0.5) * 2 - 1) * 0.55);
  }

  function triggerChime(profile) {
    const context = state.context;
    if (!context || state.chime || state.voices.length >= MAX_VOICES) return;
    const minimumGap = state.calm ? 1.2 : 0.65;
    if (context.currentTime - state.lastChimeAt < minimumGap) return;

    const oscillator = context.createOscillator();
    const gain = context.createGain();
    const panner = typeof context.createStereoPanner === "function"
      ? context.createStereoPanner()
      : null;
    const now = context.currentTime;
    const centreX = state.leftX != null && state.rightX != null
      ? (state.leftX + state.rightX) * 0.5
      : state.leftX ?? state.rightX ?? 0.5;

    oscillator.type = "sine";
    oscillator.frequency.value = profile.root * 2;
    gain.gain.setValueAtTime(0.0001, now);
    gain.gain.linearRampToValueAtTime(state.calm ? 0.025 : 0.045, now + 0.018);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.52);
    if (panner) panner.pan.value = (centreX * 2 - 1) * 0.45;

    oscillator.connect(gain);
    if (panner) {
      gain.connect(panner);
      panner.connect(state.master);
    } else {
      gain.connect(state.master);
    }

    state.chime = { oscillator, gain, panner };
    state.lastChimeAt = now;
    oscillator.onended = () => {
      oscillator.disconnect();
      gain.disconnect();
      if (panner) panner.disconnect();
      if (state.chime?.oscillator === oscillator) state.chime = null;
    };
    oscillator.start(now);
    oscillator.stop(now + 0.56);
  }

  function applyUpdate() {
    if (!state.context || state.voices.length !== 3) return;
    const [, profile] = profileFor(state.sceneId);
    const energy = state.energy;
    const calmFactor = state.calm ? 0.5 : 1;
    const pad = state.voices[0];
    const left = state.voices[1];
    const right = state.voices[2];
    const hasLeft = state.leftX != null && state.leftY != null;
    const leftActive = state.handCount >= 2 || (state.handCount === 1 && hasLeft);
    const rightActive = state.handCount >= 2 || (state.handCount === 1 && !hasLeft);

    setFrequency(pad.oscillator.frequency, profile.root * 0.5);
    setParam(
      pad.gain.gain,
      state.enabled ? (0.006 + energy * 0.008) * calmFactor : 0,
      0.2,
    );
    updateVoice(
      left,
      state.enabled && leftActive,
      state.leftX ?? 0.42,
      state.leftY ?? 0.5,
      energy,
      profile,
      0,
    );
    updateVoice(
      right,
      state.enabled && rightActive,
      state.rightX ?? 0.58,
      state.rightY ?? 0.5,
      energy,
      profile,
      profile.interval,
    );

    const threshold = state.calm ? 0.78 : 0.64;
    if (state.chimeArmed && state.enabled && state.handCount > 0 && energy >= threshold) {
      state.chimeArmed = false;
      triggerChime(profile);
    } else if (energy <= 0.36) {
      state.chimeArmed = true;
    }
  }

  async function enable() {
    if (state.disposed) {
      state.disposed = false;
      attachLifecycle();
    }
    if (document.hidden) return false;
    try {
      if (!createGraph()) return false;
    } catch (_) {
      return false;
    }
    const generation = ++state.generation;
    try {
      await state.context.resume();
    } catch (_) {
      return false;
    }
    if (state.disposed || generation !== state.generation) return false;
    state.enabled = state.context.state === "running";
    if (!state.enabled) return false;
    setParam(state.master.gain, state.volume, 0.22);
    applyUpdate();
    return true;
  }

  async function disable() {
    if (state.disposed) return true;
    const generation = ++state.generation;
    state.enabled = false;
    applyUpdate();
    if (!state.context || state.context.state !== "running") return true;
    setParam(state.master.gain, 0, 0.1);
    await new Promise((resolve) => window.setTimeout(resolve, 120));
    if (generation !== state.generation || state.disposed) return true;
    try {
      await state.context.suspend();
    } catch (_) {
      return false;
    }
    return state.context.state !== "running";
  }

  function setVolume(value) {
    if (state.disposed || !Number.isFinite(Number(value))) return state.volume;
    state.volume = clamp(value);
    if (state.enabled && state.master) setParam(state.master.gain, state.volume, 0.1);
    return state.volume;
  }

  function update(
    sceneId,
    energy,
    handCount,
    leftX,
    leftY,
    rightX,
    rightY,
    calm,
  ) {
    if (state.disposed) return;
    const [normalisedScene] = profileFor(sceneId);
    state.sceneId = normalisedScene;
    state.energy = clamp(energy);
    state.handCount = Math.round(clamp(handCount, 0, 2));
    state.leftX = optionalUnit(leftX);
    state.leftY = optionalUnit(leftY);
    state.rightX = optionalUnit(rightX);
    state.rightY = optionalUnit(rightY);
    state.calm = Boolean(calm);
    applyUpdate();
  }

  function stopNodes() {
    for (const voice of state.voices) {
      try {
        voice.oscillator.stop();
      } catch (_) {}
      voice.oscillator.disconnect();
      voice.gain.disconnect();
      if (voice.panner) voice.panner.disconnect();
    }
    state.voices = [];
    const chime = state.chime;
    state.chime = null;
    if (chime) {
      try {
        chime.oscillator.stop();
      } catch (_) {}
      chime.oscillator.disconnect();
      chime.gain.disconnect();
      if (chime.panner) chime.panner.disconnect();
    }
  }

  async function releaseGraph() {
    state.generation += 1;
    state.enabled = false;
    stopNodes();
    const context = state.context;
    state.context = null;
    state.master = null;
    state.compressor = null;
    state.limiter = null;
    state.energy = 0;
    state.handCount = 0;
    state.leftX = null;
    state.leftY = null;
    state.rightX = null;
    state.rightY = null;
    state.chimeArmed = true;
    state.lastChimeAt = Number.NEGATIVE_INFINITY;
    if (context && context.state !== "closed") {
      try {
        await context.close();
      } catch (_) {}
    }
  }

  async function dispose() {
    if (state.disposed) return;
    state.disposed = true;
    detachLifecycle();
    await releaseGraph();
  }

  function onVisibilityChange() {
    if (document.hidden) void disable();
  }

  function onPageHide() {
    void releaseGraph();
  }

  function attachLifecycle() {
    if (state.lifecycleAttached) return;
    state.lifecycleAttached = true;
    document.addEventListener("visibilitychange", onVisibilityChange);
    window.addEventListener("pagehide", onPageHide);
  }

  function detachLifecycle() {
    if (!state.lifecycleAttached) return;
    state.lifecycleAttached = false;
    document.removeEventListener("visibilitychange", onVisibilityChange);
    window.removeEventListener("pagehide", onPageHide);
  }

  function getState() {
    return Object.freeze({
      supported: Boolean(AudioContextClass),
      enabled: state.enabled,
      volume: state.volume,
      sceneId: state.sceneId,
      voiceCount: state.voices.length + (state.chime ? 1 : 0),
      contextState: state.context?.state ?? "closed",
    });
  }

  attachLifecycle();
  window.kineticFieldSoundscape = Object.freeze({
    get supported() { return Boolean(AudioContextClass); },
    get enabled() { return state.enabled; },
    get volume() { return state.volume; },
    enable,
    disable,
    setVolume,
    update,
    dispose,
    getState,
  });
})();
