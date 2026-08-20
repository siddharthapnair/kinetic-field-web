import type { InteractionSample } from "../types";

const clamp = (value: number, min = 0, max = 1) =>
  Math.min(max, Math.max(min, value));

export type RawMotion = Pick<InteractionSample, "x" | "y" | "energy">;

export function analyseMotionFrames(
  current: Uint8ClampedArray,
  previous: Uint8ClampedArray,
  width: number,
  height: number,
  mirror = true,
): RawMotion | null {
  if (current.length !== previous.length || width <= 0 || height <= 0) return null;

  let weightedX = 0;
  let weightedY = 0;
  let totalWeight = 0;
  let activeSamples = 0;
  let sampledPixels = 0;

  for (let y = 1; y < height - 1; y += 2) {
    for (let x = 1; x < width - 1; x += 2) {
      const index = (y * width + x) * 4;
      const currentLuma =
        current[index] * 0.299 + current[index + 1] * 0.587 + current[index + 2] * 0.114;
      const previousLuma =
        previous[index] * 0.299 + previous[index + 1] * 0.587 + previous[index + 2] * 0.114;
      const difference = Math.abs(currentLuma - previousLuma);
      sampledPixels += 1;

      if (difference < 19) continue;

      const weight = Math.min(72, difference - 18);
      weightedX += x * weight;
      weightedY += y * weight;
      totalWeight += weight;
      activeSamples += 1;
    }
  }

  const coverage = activeSamples / Math.max(sampledPixels, 1);
  if (coverage < 0.006 || coverage > 0.62 || totalWeight === 0) return null;

  const rawX = weightedX / totalWeight / width;
  const rawY = weightedY / totalWeight / height;
  const energy = clamp((coverage - 0.004) / 0.13);

  return {
    x: mirror ? 1 - rawX : rawX,
    y: rawY,
    energy,
  };
}

export function normalisePointerVelocity(
  currentX: number,
  currentY: number,
  previous: InteractionSample,
  timestamp: number,
): Pick<InteractionSample, "vx" | "vy" | "energy"> {
  const elapsed = Math.max(8, timestamp - previous.timestamp);
  const scale = 16.67 / elapsed;
  const vx = (currentX - previous.x) * scale;
  const vy = (currentY - previous.y) * scale;
  const speed = Math.sqrt(vx * vx + vy * vy);

  return {
    vx: clamp(vx, -0.18, 0.18),
    vy: clamp(vy, -0.18, 0.18),
    energy: clamp(speed * 7.5, 0.16, 1),
  };
}

export function qualityGrid(
  quality: "auto" | "low" | "high",
  hardwareConcurrency = 8,
): { columns: number; rows: number; pixelRatio: number } {
  if (quality === "low") return { columns: 96, rows: 54, pixelRatio: 1 };
  if (quality === "high") return { columns: 240, rows: 135, pixelRatio: 1.5 };
  if (hardwareConcurrency < 6) return { columns: 112, rows: 63, pixelRatio: 1 };
  return { columns: 160, rows: 90, pixelRatio: 1.25 };
}
