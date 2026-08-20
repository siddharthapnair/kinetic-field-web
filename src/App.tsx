import {
  Camera,
  CameraOff,
  Gauge,
  Maximize2,
  Minimize2,
  MousePointer2,
  RotateCcw,
  Settings2,
  SlidersHorizontal,
  X,
} from "lucide-react";
import { lazy, Suspense, useCallback, useEffect, useRef, useState } from "react";
import { cameraFailureState, releaseMediaStream } from "./lib/camera";
import { normalisePointerVelocity } from "./lib/motion";
import {
  DEFAULT_SETTINGS,
  type CameraState,
  type FieldSettings,
  type InteractionSample,
  type QualityMode,
} from "./types";

const KineticField = lazy(() =>
  import("./components/KineticField").then((module) => ({
    default: module.KineticField,
  })),
);

type RangeControlProps = {
  id: string;
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  displayValue?: string;
  onChange: (value: number) => void;
};

function RangeControl({
  id,
  label,
  value,
  min,
  max,
  step,
  displayValue,
  onChange,
}: RangeControlProps) {
  return (
    <div className="range-control">
      <span className="control-label">
        <label htmlFor={id}>{label}</label>
        <output>{displayValue ?? value.toFixed(2)}</output>
      </span>
      <input
        id={id}
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(event) => onChange(Number(event.target.value))}
      />
    </div>
  );
}

function cameraMessage(state: CameraState) {
  switch (state) {
    case "requesting":
      return "Waiting for camera permission";
    case "active":
      return "Camera motion active";
    case "denied":
      return "Camera access was declined. Pointer mode is still active.";
    case "unavailable":
      return "No available camera was found. Pointer mode is still active.";
    case "error":
      return "The camera could not start. Pointer mode is still active.";
    default:
      return "Pointer motion active";
  }
}

export function App() {
  const [settings, setSettings] = useState<FieldSettings>(DEFAULT_SETTINGS);
  const [cameraState, setCameraState] = useState<CameraState>("idle");
  const [introVisible, setIntroVisible] = useState(true);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [cameraPreview, setCameraPreview] = useState(false);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [uiVisible, setUiVisible] = useState(true);
  const [stats, setStats] = useState({ fps: 0, particles: 0 });

  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const cameraRequestRef = useRef(0);
  const cameraRequestPendingRef = useRef(false);
  const hideUiTimerRef = useRef<number | null>(null);
  const settingsButtonRef = useRef<HTMLButtonElement>(null);
  const dockCameraButtonRef = useRef<HTMLButtonElement>(null);
  const interactionRef = useRef<InteractionSample>({
    x: 0.5,
    y: 0.5,
    vx: 0,
    vy: 0,
    energy: 0.18,
    timestamp: 0,
  });

  const updateSetting = <Key extends keyof FieldSettings>(
    key: Key,
    value: FieldSettings[Key],
  ) => {
    setSettings((current) => ({ ...current, [key]: value }));
  };

  const revealInterface = useCallback(() => {
    setUiVisible(true);
    if (hideUiTimerRef.current) window.clearTimeout(hideUiTimerRef.current);
    if (cameraState === "active" && !settingsOpen && !introVisible) {
      hideUiTimerRef.current = window.setTimeout(() => {
        const focusedElement = document.activeElement;
        const interfaceHasFocus =
          focusedElement instanceof HTMLElement &&
          Boolean(focusedElement.closest(".interface-layer"));
        if (!interfaceHasFocus) setUiVisible(false);
      }, 4200);
    }
  }, [cameraState, introVisible, settingsOpen]);

  const dismissIntro = useCallback(() => {
    setIntroVisible(false);
    window.requestAnimationFrame(() => dockCameraButtonRef.current?.focus());
  }, []);

  const closeSettings = useCallback(() => {
    setSettingsOpen(false);
    window.requestAnimationFrame(() => settingsButtonRef.current?.focus());
  }, []);

  const stopCamera = useCallback(() => {
    cameraRequestRef.current += 1;
    cameraRequestPendingRef.current = false;
    const currentStream = streamRef.current;
    streamRef.current = null;
    releaseMediaStream(currentStream);
    if (videoRef.current) videoRef.current.srcObject = null;
    setCameraState("idle");
    setCameraPreview(false);
    setUiVisible(true);
  }, []);

  const startCamera = useCallback(async () => {
    if (cameraRequestPendingRef.current || streamRef.current) return;
    if (!window.isSecureContext && window.location.hostname !== "127.0.0.1") {
      setCameraState("unavailable");
      return;
    }
    if (!navigator.mediaDevices?.getUserMedia) {
      setCameraState("unavailable");
      return;
    }

    const requestId = cameraRequestRef.current + 1;
    cameraRequestRef.current = requestId;
    cameraRequestPendingRef.current = true;
    setCameraState("requesting");
    let acquiredStream: MediaStream | null = null;
    try {
      acquiredStream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: "user",
          width: { ideal: 640 },
          height: { ideal: 360 },
          frameRate: { ideal: 30, max: 30 },
        },
        audio: false,
      });

      if (requestId !== cameraRequestRef.current) {
        releaseMediaStream(acquiredStream);
        return;
      }

      const video = videoRef.current;
      if (!video) {
        releaseMediaStream(acquiredStream);
        throw new Error("Camera surface is unavailable.");
      }

      streamRef.current = acquiredStream;
      video.srcObject = acquiredStream;
      await video.play();
      if (requestId !== cameraRequestRef.current) {
        releaseMediaStream(acquiredStream);
        streamRef.current = null;
        video.srcObject = null;
        return;
      }

      const handleTrackEnded = () => {
        if (streamRef.current !== acquiredStream) return;
        cameraRequestRef.current += 1;
        cameraRequestPendingRef.current = false;
        streamRef.current = null;
        releaseMediaStream(acquiredStream);
        if (videoRef.current?.srcObject === acquiredStream) {
          videoRef.current.srcObject = null;
        }
        setCameraState("idle");
        setCameraPreview(false);
        setUiVisible(true);
      };
      acquiredStream.getVideoTracks().forEach((track) => {
        track.addEventListener("ended", handleTrackEnded, { once: true });
      });

      setCameraState("active");
      setIntroVisible(false);
      setUiVisible(true);
      window.requestAnimationFrame(() => dockCameraButtonRef.current?.focus());
    } catch (error) {
      releaseMediaStream(acquiredStream);
      if (streamRef.current === acquiredStream) streamRef.current = null;
      if (videoRef.current?.srcObject === acquiredStream) videoRef.current.srcObject = null;
      if (requestId === cameraRequestRef.current) {
        setCameraState(cameraFailureState(error));
      }
    } finally {
      if (requestId === cameraRequestRef.current) cameraRequestPendingRef.current = false;
    }
  }, []);

  const toggleFullscreen = useCallback(async () => {
    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen();
      } else {
        await document.documentElement.requestFullscreen();
      }
    } catch {
      setIsFullscreen(Boolean(document.fullscreenElement));
    }
  }, []);

  const updatePointer = useCallback(
    (clientX: number, clientY: number) => {
      revealInterface();
      if (cameraState === "active") return;

      const timestamp = performance.now();
      const x = clientX / Math.max(window.innerWidth, 1);
      const y = clientY / Math.max(window.innerHeight, 1);
      const motion = normalisePointerVelocity(
        x,
        y,
        interactionRef.current,
        timestamp,
      );
      interactionRef.current = { x, y, timestamp, ...motion };
    },
    [cameraState, revealInterface],
  );

  useEffect(() => {
    const mediaQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    const applyPreference = () => {
      if (mediaQuery.matches) {
        setSettings((current) => ({ ...current, calmMotion: true }));
      }
    };
    applyPreference();
    mediaQuery.addEventListener("change", applyPreference);
    return () => mediaQuery.removeEventListener("change", applyPreference);
  }, []);

  useEffect(() => {
    const updateFullscreen = () => setIsFullscreen(Boolean(document.fullscreenElement));
    document.addEventListener("fullscreenchange", updateFullscreen);
    return () => document.removeEventListener("fullscreenchange", updateFullscreen);
  }, []);

  useEffect(() => {
    const releaseCamera = (reconcileState: boolean) => {
      cameraRequestRef.current += 1;
      cameraRequestPendingRef.current = false;
      const currentStream = streamRef.current;
      streamRef.current = null;
      releaseMediaStream(currentStream);
      if (videoRef.current) videoRef.current.srcObject = null;
      if (reconcileState) {
        setCameraState("idle");
        setCameraPreview(false);
        setUiVisible(true);
      }
    };
    const handlePageHide = () => releaseCamera(true);
    const handlePageShow = () => {
      const hasLiveTrack = streamRef.current
        ?.getVideoTracks()
        .some((track) => track.readyState === "live");
      if (!hasLiveTrack) {
        setCameraState("idle");
        setCameraPreview(false);
      }
    };
    window.addEventListener("pagehide", handlePageHide);
    window.addEventListener("pageshow", handlePageShow);
    return () => {
      window.removeEventListener("pagehide", handlePageHide);
      window.removeEventListener("pageshow", handlePageShow);
      releaseCamera(false);
      if (hideUiTimerRef.current) window.clearTimeout(hideUiTimerRef.current);
    };
  }, []);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (target?.matches("input, select, textarea") && event.key !== "Escape") return;

      if (event.key.toLowerCase() === "c") {
        if (cameraState === "active") stopCamera();
        else void startCamera();
      } else if (event.key.toLowerCase() === "f") {
        void toggleFullscreen();
      } else if (event.key.toLowerCase() === "r") {
        setSettings(DEFAULT_SETTINGS);
      } else if (event.key === "Escape") {
        if (settingsOpen) closeSettings();
        else if (introVisible) dismissIntro();
      }
      revealInterface();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [cameraState, closeSettings, dismissIntro, introVisible, revealInterface, settingsOpen, startCamera, stopCamera, toggleFullscreen]);

  const cameraIsActive = cameraState === "active";

  return (
    <main
      className={`experience-shell ${uiVisible ? "is-ui-visible" : "is-ui-hidden"}`}
      onPointerMove={(event) => updatePointer(event.clientX, event.clientY)}
      onPointerDown={(event) => updatePointer(event.clientX, event.clientY)}
    >
      <Suspense fallback={<div className="field-loading" aria-hidden="true" />}>
        <KineticField
          settings={settings}
          cameraActive={cameraIsActive}
          videoRef={videoRef}
          interactionRef={interactionRef}
          onStats={(fps, particles) => setStats({ fps, particles })}
        />
      </Suspense>

      <video
        ref={videoRef}
        className={`camera-preview ${settings.mirrorCamera ? "is-mirrored" : ""} ${cameraPreview && cameraIsActive ? "is-visible" : ""}`}
        muted
        playsInline
        aria-label="Live camera preview"
      />

      <div className="ambient-vignette" aria-hidden="true" />

      <header className="experience-header interface-layer">
        <button
          type="button"
          className="wordmark"
          onClick={() => setIntroVisible(true)}
          aria-label="Open Kinetic Field introduction"
        >
          <span className="wordmark-mark" aria-hidden="true" />
          <span>Kinetic Field</span>
        </button>
        <div className="live-label" aria-live="polite">
          <span className={`status-dot ${cameraIsActive ? "is-camera" : ""}`} aria-hidden="true" />
          {cameraMessage(cameraState)}
        </div>
      </header>

      <section
        className={`experience-intro interface-layer ${introVisible ? "is-visible" : ""}`}
        aria-labelledby="experience-title"
        aria-hidden={!introVisible}
        inert={!introVisible}
      >
        <p className="eyebrow">Your movement becomes force</p>
        <h1 id="experience-title">Shape motion into light.</h1>
        <p className="intro-copy">
          A living particle field follows the motion seen by your laptop camera. Frames are processed on this device and are never uploaded.
        </p>
        <div className="intro-actions">
          <button
            type="button"
            className="primary-action"
            onClick={() => void startCamera()}
            disabled={cameraState === "requesting"}
          >
            <Camera size={17} aria-hidden="true" />
            {cameraState === "requesting" ? "Connecting camera" : "Enable camera"}
          </button>
          <button type="button" className="text-action" onClick={dismissIntro}>
            <MousePointer2 size={15} aria-hidden="true" />
            Continue with pointer
          </button>
        </div>
        {(cameraState === "denied" || cameraState === "unavailable" || cameraState === "error") && (
          <p className="camera-error" role="status">{cameraMessage(cameraState)}</p>
        )}
      </section>

      <div className="control-dock interface-layer" aria-label="Experience controls">
        <button
          ref={dockCameraButtonRef}
          type="button"
          className={`dock-action camera-action ${cameraIsActive ? "is-active" : ""}`}
          onClick={cameraIsActive ? stopCamera : () => void startCamera()}
          aria-pressed={cameraIsActive}
        >
          {cameraIsActive ? <CameraOff size={17} aria-hidden="true" /> : <Camera size={17} aria-hidden="true" />}
          <span>{cameraIsActive ? "Disable camera" : "Enable camera"}</span>
        </button>
        <span className="dock-divider" aria-hidden="true" />
        <button
          ref={settingsButtonRef}
          type="button"
          className="icon-action"
          onClick={() => {
            if (settingsOpen) closeSettings();
            else {
              setSettingsOpen(true);
              setUiVisible(true);
            }
          }}
          aria-label={settingsOpen ? "Close field controls" : "Open field controls"}
          aria-expanded={settingsOpen}
          aria-controls="field-controls"
        >
          <Settings2 size={18} aria-hidden="true" />
        </button>
        <button
          type="button"
          className="icon-action"
          onClick={() => void toggleFullscreen()}
          aria-label={isFullscreen ? "Exit fullscreen" : "Enter fullscreen"}
        >
          {isFullscreen ? <Minimize2 size={18} aria-hidden="true" /> : <Maximize2 size={18} aria-hidden="true" />}
        </button>
      </div>

      <aside
        id="field-controls"
        className={`settings-panel interface-layer ${settingsOpen ? "is-open" : ""}`}
        aria-hidden={!settingsOpen}
        inert={!settingsOpen}
      >
        <div className="panel-header">
          <div>
            <p className="panel-kicker">Field controls</p>
            <h2>Shape the response</h2>
          </div>
          <button type="button" className="icon-action" onClick={closeSettings} aria-label="Close controls">
            <X size={18} aria-hidden="true" />
          </button>
        </div>

        <div className="panel-content">
          <RangeControl id="field-force" label="Force" value={settings.strength} min={0.35} max={2.2} step={0.01} onChange={(value) => updateSetting("strength", value)} />
          <RangeControl id="field-radius" label="Radius" value={settings.radius} min={0.12} max={0.55} step={0.01} onChange={(value) => updateSetting("radius", value)} />
          <RangeControl id="field-swirl" label="Swirl" value={settings.swirl} min={0} max={2.4} step={0.01} onChange={(value) => updateSetting("swirl", value)} />
          <RangeControl id="field-turbulence" label="Turbulence" value={settings.turbulence} min={0} max={1.6} step={0.01} onChange={(value) => updateSetting("turbulence", value)} />
          <RangeControl id="field-point-size" label="Point glow" value={settings.pointSize} min={0.7} max={3} step={0.05} onChange={(value) => updateSetting("pointSize", value)} />
          <RangeControl id="field-colour-speed" label="Colour drift" value={settings.colourSpeed} min={0} max={1.8} step={0.01} onChange={(value) => updateSetting("colourSpeed", value)} />

          <fieldset className="quality-control">
            <legend>Render quality</legend>
            <div className="segmented-control">
              {(["low", "auto", "high"] as QualityMode[]).map((quality) => (
                <button
                  type="button"
                  key={quality}
                  className={settings.quality === quality ? "is-selected" : ""}
                  onClick={() => updateSetting("quality", quality)}
                  aria-pressed={settings.quality === quality}
                >
                  {quality}
                </button>
              ))}
            </div>
          </fieldset>

          <label className="toggle-control" htmlFor="mirror-camera" aria-label="Mirror camera">
            <span>
              <span className="toggle-title">Mirror camera</span>
              <span className="toggle-copy">Match your movement on screen</span>
            </span>
            <input id="mirror-camera" type="checkbox" checked={settings.mirrorCamera} onChange={(event) => updateSetting("mirrorCamera", event.target.checked)} />
          </label>

          <label className="toggle-control" htmlFor="calm-motion" aria-label="Calm motion">
            <span>
              <span className="toggle-title">Calm motion</span>
              <span className="toggle-copy">Lower autonomous movement and intensity</span>
            </span>
            <input id="calm-motion" type="checkbox" checked={settings.calmMotion} onChange={(event) => updateSetting("calmMotion", event.target.checked)} />
          </label>

          <label
            className={`toggle-control ${cameraIsActive ? "" : "is-disabled"}`}
            htmlFor="camera-preview"
            aria-label="Camera preview"
          >
            <span>
              <span className="toggle-title">Camera preview</span>
              <span className="toggle-copy">Show what the motion sensor sees</span>
            </span>
            <input id="camera-preview" type="checkbox" checked={cameraPreview} disabled={!cameraIsActive} onChange={(event) => setCameraPreview(event.target.checked)} />
          </label>
        </div>

        <div className="panel-footer">
          <div className="performance-readout">
            <Gauge size={16} aria-hidden="true" />
            <span>{stats.fps || "…"} fps</span>
            <span>{stats.particles ? stats.particles.toLocaleString() : "…"} particles</span>
          </div>
          <button type="button" className="reset-action" onClick={() => setSettings(DEFAULT_SETTINGS)}>
            <RotateCcw size={15} aria-hidden="true" /> Reset field
          </button>
        </div>
      </aside>

      <footer className="experience-footer interface-layer">
        <span className="interaction-hint">
          <SlidersHorizontal size={13} aria-hidden="true" />
          {cameraIsActive ? "Move within the camera frame" : "Move your pointer through the field"}
        </span>
        <span className="shortcut-hint">C camera · F fullscreen · R reset</span>
      </footer>
    </main>
  );
}
