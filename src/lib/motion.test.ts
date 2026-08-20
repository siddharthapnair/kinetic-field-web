import { describe, expect, it } from "vitest";
import { analyseMotionFrames, normalisePointerVelocity, qualityGrid } from "./motion";

function frame(width: number, height: number, value = 0) {
  const pixels = new Uint8ClampedArray(width * height * 4);
  for (let index = 0; index < pixels.length; index += 4) {
    pixels[index] = value;
    pixels[index + 1] = value;
    pixels[index + 2] = value;
    pixels[index + 3] = 255;
  }
  return pixels;
}

describe("analyseMotionFrames", () => {
  it("returns no interaction for identical frames", () => {
    const first = frame(20, 20);
    expect(analyseMotionFrames(first, first, 20, 20)).toBeNull();
  });

  it("locates a compact moving region and mirrors it", () => {
    const previous = frame(20, 20);
    const current = frame(20, 20);
    for (let y = 7; y <= 13; y += 1) {
      for (let x = 3; x <= 8; x += 1) {
        const index = (y * 20 + x) * 4;
        current[index] = 255;
        current[index + 1] = 255;
        current[index + 2] = 255;
      }
    }

    const result = analyseMotionFrames(current, previous, 20, 20, true);
    expect(result).not.toBeNull();
    expect(result!.x).toBeGreaterThan(0.58);
    expect(result!.y).toBeGreaterThan(0.35);
    expect(result!.energy).toBeGreaterThan(0);
  });
});

describe("normalisePointerVelocity", () => {
  it("converts position change into a bounded interaction energy", () => {
    const result = normalisePointerVelocity(
      0.6,
      0.45,
      { x: 0.5, y: 0.5, vx: 0, vy: 0, energy: 0, timestamp: 100 },
      116.67,
    );
    expect(result.vx).toBeCloseTo(0.1, 2);
    expect(result.vy).toBeCloseTo(-0.05, 2);
    expect(result.energy).toBeGreaterThan(0.7);
  });
});

describe("qualityGrid", () => {
  it("uses a smaller automatic grid on lower core counts", () => {
    expect(qualityGrid("auto", 4).columns).toBe(112);
    expect(qualityGrid("auto", 8).columns).toBe(160);
  });

  it("keeps explicit quality choices deterministic", () => {
    expect(qualityGrid("low", 12)).toEqual({ columns: 96, rows: 54, pixelRatio: 1 });
    expect(qualityGrid("high", 2)).toEqual({ columns: 240, rows: 135, pixelRatio: 1.5 });
  });
});
