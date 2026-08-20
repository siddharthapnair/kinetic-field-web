import { describe, expect, it, vi } from "vitest";
import { cameraFailureState, releaseMediaStream } from "./camera";

describe("releaseMediaStream", () => {
  it("stops every track attached to a stream", () => {
    const firstStop = vi.fn();
    const secondStop = vi.fn();
    const stream = {
      getTracks: () => [{ stop: firstStop }, { stop: secondStop }],
    } as unknown as MediaStream;

    releaseMediaStream(stream);
    expect(firstStop).toHaveBeenCalledOnce();
    expect(secondStop).toHaveBeenCalledOnce();
  });

  it("accepts an absent stream", () => {
    expect(() => releaseMediaStream(null)).not.toThrow();
  });
});

describe("cameraFailureState", () => {
  it("distinguishes permission denial and missing devices", () => {
    expect(cameraFailureState(new DOMException("No", "NotAllowedError"))).toBe("denied");
    expect(cameraFailureState(new DOMException("Missing", "NotFoundError"))).toBe("unavailable");
  });

  it("uses a safe generic state for unknown failures", () => {
    expect(cameraFailureState(new Error("Busy"))).toBe("error");
  });
});
