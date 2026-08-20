export type QualityMode = "auto" | "low" | "high";

export type CameraState =
  | "idle"
  | "requesting"
  | "active"
  | "denied"
  | "unavailable"
  | "error";

export type InteractionSample = {
  x: number;
  y: number;
  vx: number;
  vy: number;
  energy: number;
  timestamp: number;
};

export type FieldSettings = {
  strength: number;
  radius: number;
  swirl: number;
  turbulence: number;
  pointSize: number;
  colourSpeed: number;
  quality: QualityMode;
  mirrorCamera: boolean;
  calmMotion: boolean;
};

export const DEFAULT_SETTINGS: FieldSettings = {
  strength: 1.18,
  radius: 0.3,
  swirl: 1.22,
  turbulence: 0.68,
  pointSize: 1.45,
  colourSpeed: 0.52,
  quality: "auto",
  mirrorCamera: true,
  calmMotion: false,
};
