import type { InteractionSample } from "../types";
import { analyseMotionFrames } from "./motion";

export class MotionTracker {
  private readonly canvas: HTMLCanvasElement;
  private readonly context: CanvasRenderingContext2D;
  private previousFrame: Uint8ClampedArray | null = null;
  private filtered: InteractionSample = {
    x: 0.5,
    y: 0.5,
    vx: 0,
    vy: 0,
    energy: 0,
    timestamp: performance.now(),
  };
  private lastSampleAt = 0;

  constructor(
    private readonly video: HTMLVideoElement,
    private readonly mirror: () => boolean,
    private readonly width = 96,
    private readonly height = 54,
  ) {
    this.canvas = document.createElement("canvas");
    this.canvas.width = width;
    this.canvas.height = height;
    const context = this.canvas.getContext("2d", { willReadFrequently: true });
    if (!context) throw new Error("Motion analysis canvas is unavailable.");
    this.context = context;
  }

  sample(timestamp: number): InteractionSample {
    if (timestamp - this.lastSampleAt < 42 || this.video.readyState < 2) {
      return this.filtered;
    }
    this.lastSampleAt = timestamp;

    this.context.drawImage(this.video, 0, 0, this.width, this.height);
    const frame = this.context.getImageData(0, 0, this.width, this.height).data;

    if (!this.previousFrame) {
      this.previousFrame = new Uint8ClampedArray(frame);
      return this.filtered;
    }

    const raw = analyseMotionFrames(
      frame,
      this.previousFrame,
      this.width,
      this.height,
      this.mirror(),
    );
    this.previousFrame.set(frame);

    if (!raw) {
      this.filtered.energy *= 0.86;
      this.filtered.vx *= 0.82;
      this.filtered.vy *= 0.82;
      this.filtered.timestamp = timestamp;
      return this.filtered;
    }

    const elapsed = Math.max(12, timestamp - this.filtered.timestamp);
    const alpha = 0.18 + raw.energy * 0.32;
    const nextX = this.filtered.x + (raw.x - this.filtered.x) * alpha;
    const nextY = this.filtered.y + (raw.y - this.filtered.y) * alpha;
    const velocityScale = 16.67 / elapsed;
    const vx = (nextX - this.filtered.x) * velocityScale;
    const vy = (nextY - this.filtered.y) * velocityScale;

    this.filtered = {
      x: nextX,
      y: nextY,
      vx: this.filtered.vx * 0.55 + vx * 0.45,
      vy: this.filtered.vy * 0.55 + vy * 0.45,
      energy: this.filtered.energy * 0.45 + raw.energy * 0.55,
      timestamp,
    };

    return this.filtered;
  }

  reset() {
    this.previousFrame = null;
    this.filtered.energy = 0;
    this.filtered.vx = 0;
    this.filtered.vy = 0;
  }
}
