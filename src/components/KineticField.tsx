import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { MotionTracker } from "../lib/MotionTracker";
import { qualityGrid } from "../lib/motion";
import { particleFragmentShader, particleVertexShader } from "../lib/particleShaders";
import type { FieldSettings, InteractionSample } from "../types";

type KineticFieldProps = {
  settings: FieldSettings;
  cameraActive: boolean;
  videoRef: React.RefObject<HTMLVideoElement | null>;
  interactionRef: React.MutableRefObject<InteractionSample>;
  onStats: (fps: number, particles: number) => void;
};

type RenderMode = "webgl" | "canvas-2d";

function viewportGrid(
  quality: FieldSettings["quality"],
  hardwareConcurrency: number,
  aspect: number,
  particleLimit = Number.POSITIVE_INFINITY,
) {
  const baseGrid = qualityGrid(quality, hardwareConcurrency);
  const safeAspect = Math.min(3.2, Math.max(0.35, aspect));
  const particleCount = Math.min(
    particleLimit,
    baseGrid.columns * baseGrid.rows,
  );
  const columns = Math.max(24, Math.round(Math.sqrt(particleCount * safeAspect)));
  const rows = Math.max(24, Math.round(particleCount / columns));

  return { columns, rows, pixelRatio: baseGrid.pixelRatio };
}

function particlePositions(columns: number, rows: number) {
  const positions = new Float32Array(columns * rows * 3);
  let positionIndex = 0;

  for (let row = 0; row < rows; row += 1) {
    for (let column = 0; column < columns; column += 1) {
      positions[positionIndex] = column / Math.max(columns - 1, 1) * 2 - 1;
      positions[positionIndex + 1] = 1 - row / Math.max(rows - 1, 1) * 2;
      positions[positionIndex + 2] = 0;
      positionIndex += 3;
    }
  }

  return positions;
}

export function KineticField({
  settings,
  cameraActive,
  videoRef,
  interactionRef,
  onStats,
}: KineticFieldProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const settingsRef = useRef(settings);
  const cameraActiveRef = useRef(cameraActive);
  const statsCallbackRef = useRef(onStats);
  const fallbackCanvasRef = useRef<HTMLCanvasElement>(null);
  const [renderMode, setRenderMode] = useState<RenderMode>("webgl");

  useEffect(() => {
    settingsRef.current = settings;
  }, [settings]);

  useEffect(() => {
    cameraActiveRef.current = cameraActive;
  }, [cameraActive]);

  useEffect(() => {
    statsCallbackRef.current = onStats;
  }, [onStats]);

  useEffect(() => {
    const hardwareConcurrency = navigator.hardwareConcurrency || 8;
    let motionTracker: MotionTracker | null = null;
    let lastVideo: HTMLVideoElement | null = null;

    const pointerOrIdleInteraction = (timestamp: number): InteractionSample => {
      const pointer = interactionRef.current;
      const idleFor = Math.max(0, timestamp - pointer.timestamp);

      if (idleFor > 1800) {
        if (settingsRef.current.calmMotion) {
          return {
            x: 0.5,
            y: 0.5,
            vx: 0,
            vy: 0,
            energy: 0,
            timestamp,
          };
        }

        return {
          x: 0.5 + Math.sin(timestamp * 0.00029) * 0.2,
          y: 0.5 + Math.cos(timestamp * 0.00023) * 0.13,
          vx: Math.cos(timestamp * 0.00029) * 0.003,
          vy: -Math.sin(timestamp * 0.00023) * 0.002,
          energy: 0.2,
          timestamp,
        };
      }

      const decay = Math.exp(-idleFor / 240);
      return {
        ...pointer,
        vx: pointer.vx * decay,
        vy: pointer.vy * decay,
        energy: pointer.energy * decay,
      };
    };

    const sampleInteraction = (timestamp: number): InteractionSample => {
      const currentVideo = videoRef.current;
      if (currentVideo && currentVideo !== lastVideo) {
        try {
          motionTracker = new MotionTracker(
            currentVideo,
            () => settingsRef.current.mirrorCamera,
          );
        } catch {
          motionTracker = null;
        }
        lastVideo = currentVideo;
      }

      if (cameraActiveRef.current && motionTracker) {
        try {
          return motionTracker.sample(timestamp);
        } catch {
          return pointerOrIdleInteraction(timestamp);
        }
      }

      return pointerOrIdleInteraction(timestamp);
    };

    if (renderMode === "canvas-2d") {
      const canvas = fallbackCanvasRef.current;
      const context = canvas?.getContext("2d", { alpha: false });
      if (!canvas || !context) return;

      let frameId = 0;
      let width = 1;
      let height = 1;
      let pixelRatio = 1;
      let grid = viewportGrid(
        settingsRef.current.quality,
        hardwareConcurrency,
        16 / 9,
        settingsRef.current.quality === "high" ? 7200 : 4800,
      );
      let lastFrameAt = performance.now();
      let statsWindowStartedAt = lastFrameAt;
      let frameCount = 0;
      let smoothedEnergy = 0.18;

      const resizeFallback = () => {
        width = Math.max(1, canvas.clientWidth || window.innerWidth);
        height = Math.max(1, canvas.clientHeight || window.innerHeight);
        const aspect = width / height;
        grid = viewportGrid(
          settingsRef.current.quality,
          hardwareConcurrency,
          aspect,
          settingsRef.current.quality === "high" ? 7200 : 4800,
        );
        pixelRatio = Math.min(window.devicePixelRatio || 1, grid.pixelRatio);
        canvas.width = Math.max(1, Math.round(width * pixelRatio));
        canvas.height = Math.max(1, Math.round(height * pixelRatio));
      };

      const fieldNoise = (x: number, y: number, time: number) =>
        Math.sin(x * 8.3 + time * 0.71) * Math.cos(y * 7.1 - time * 0.63)
        + Math.sin((x + y) * 13.7 - time * 0.39) * 0.45;

      const renderFallback = (timestamp: number) => {
        const delta = Math.min(50, timestamp - lastFrameAt);
        lastFrameAt = timestamp;
        frameCount += 1;

        const activeInteraction = sampleInteraction(timestamp);
        const currentSettings = settingsRef.current;
        const energyResponse = currentSettings.calmMotion ? 0.42 : 1;
        const targetEnergy = activeInteraction.energy * energyResponse;
        const energyLerp = targetEnergy > smoothedEnergy ? 0.2 : 0.055;
        smoothedEnergy += (targetEnergy - smoothedEnergy)
          * energyLerp
          * Math.min(2, delta / 16.67);

        const time = timestamp * 0.001;
        const aspect = width / Math.max(height, 1);
        const pointerWorldX = (activeInteraction.x - 0.5) * 2 * aspect;
        const pointerWorldY = (0.5 - activeInteraction.y) * 2;
        const speed = Math.min(
          1,
          Math.hypot(activeInteraction.vx, activeInteraction.vy) * 9,
        );
        const activeEnergy = Math.max(smoothedEnergy, speed * 0.75);
        const motionGate = currentSettings.calmMotion
          ? Math.min(1, activeEnergy * 8)
          : 1;

        context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
        context.globalCompositeOperation = "source-over";
        context.globalAlpha = 1;
        context.fillStyle = "#050810";
        context.fillRect(0, 0, width, height);
        context.globalCompositeOperation = "lighter";
        context.globalAlpha = currentSettings.calmMotion ? 0.3 : 0.42;
        context.beginPath();

        for (let row = 0; row < grid.rows; row += 1) {
          const rowProgress = row / Math.max(grid.rows - 1, 1);
          const hue = (188 + rowProgress * 74 + time * currentSettings.colourSpeed * 4) % 360;
          context.fillStyle = `hsl(${hue} 78% 62%)`;

          for (let column = 0; column < grid.columns; column += 1) {
            const columnProgress = column / Math.max(grid.columns - 1, 1);
            let worldX = (columnProgress - 0.5) * 2 * aspect;
            let worldY = (0.5 - rowProgress) * 2;
            const deltaX = worldX - pointerWorldX;
            const deltaY = worldY - pointerWorldY;
            const distance = Math.hypot(deltaX, deltaY) + 0.0001;
            const influence = Math.exp(
              -(distance * distance)
              / Math.max(0.025, currentSettings.radius * currentSettings.radius),
            );
            const tangentX = -deltaY / distance;
            const tangentY = deltaX / distance;
            const radialX = deltaX / distance;
            const radialY = deltaY / distance;
            const quietNoise = fieldNoise(worldX, worldY, time)
              * 0.008
              * (1 - (currentSettings.calmMotion ? 0.82 : 0));
            worldX += quietNoise;
            worldY -= quietNoise * 0.72;

            const rotatingWave = Math.sin(distance * 24 - time * 3.4 + activeEnergy * 2);
            const swirlForce = influence
              * currentSettings.swirl
              * currentSettings.strength
              * motionGate
              * (0.035 + activeEnergy * 0.135);
            const radialForce = influence
              * rotatingWave
              * currentSettings.strength
              * motionGate
              * (0.012 + activeEnergy * 0.052);
            worldX += tangentX * swirlForce + radialX * radialForce;
            worldY += tangentY * swirlForce + radialY * radialForce;
            worldX += activeInteraction.vx
              * aspect
              * influence
              * currentSettings.strength
              * 0.58;
            worldY -= activeInteraction.vy
              * influence
              * currentSettings.strength
              * 0.58;

            const turbulence = fieldNoise(worldX * 1.8, worldY * 1.8, time * 1.3)
              * currentSettings.turbulence
              * influence
              * motionGate
              * 0.006;
            worldX += turbulence;
            worldY -= turbulence * 0.7;

            const screenX = (worldX / aspect + 1) * 0.5 * width;
            const screenY = (1 - worldY) * 0.5 * height;
            const pointSize = Math.max(
              0.8,
              currentSettings.pointSize
              * (0.78 + influence * (0.65 + activeEnergy * 1.55)),
            );
            context.fillRect(
              screenX - pointSize * 0.5,
              screenY - pointSize * 0.5,
              pointSize,
              pointSize,
            );

            if (influence > 0.035) {
              const reactiveSize = pointSize * (0.75 + influence * 0.7);
              context.rect(
                screenX - reactiveSize * 0.5,
                screenY - reactiveSize * 0.5,
                reactiveSize,
                reactiveSize,
              );
            }
          }
        }

        context.globalAlpha = Math.min(0.86, 0.3 + activeEnergy * 0.5);
        context.fillStyle = `hsl(${(202 + time * currentSettings.colourSpeed * 18 + activeEnergy * 118) % 360} 96% 68%)`;
        context.fill();
        context.globalAlpha = 1;
        context.globalCompositeOperation = "source-over";

        if (timestamp - statsWindowStartedAt >= 1000) {
          const fps = Math.round(
            frameCount * 1000 / (timestamp - statsWindowStartedAt),
          );
          statsCallbackRef.current(fps, grid.columns * grid.rows);
          frameCount = 0;
          statsWindowStartedAt = timestamp;
        }

        frameId = window.requestAnimationFrame(renderFallback);
      };

      resizeFallback();
      window.addEventListener("resize", resizeFallback);
      frameId = window.requestAnimationFrame(renderFallback);

      return () => {
        window.removeEventListener("resize", resizeFallback);
        window.cancelAnimationFrame(frameId);
      };
    }

    const canvas = canvasRef.current;
    if (!canvas) return;

    let renderer: THREE.WebGLRenderer | null = null;
    let geometry: THREE.BufferGeometry | null = null;
    let material: THREE.ShaderMaterial | null = null;
    let frameId = 0;
    let webglFailed = false;

    const activateFallback = () => {
      if (webglFailed) return;
      webglFailed = true;
      setRenderMode("canvas-2d");
    };

    const onContextLost = (event: Event) => {
      event.preventDefault();
      activateFallback();
    };

    try {
      renderer = new THREE.WebGLRenderer({
        canvas,
        alpha: false,
        antialias: false,
        powerPreference: "high-performance",
      });
      renderer.outputColorSpace = THREE.SRGBColorSpace;
      renderer.toneMapping = THREE.ACESFilmicToneMapping;
      renderer.toneMappingExposure = 1.16;
      renderer.setClearColor(new THREE.Color(0x050810), 1);
      renderer.debug.onShaderError = activateFallback;

      const scene = new THREE.Scene();
      const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 10);
      camera.position.z = 3;

      let grid = viewportGrid(
        settingsRef.current.quality,
        hardwareConcurrency,
        (canvas.clientWidth || window.innerWidth)
          / Math.max(canvas.clientHeight || window.innerHeight, 1),
      );
      geometry = new THREE.BufferGeometry();
      geometry.setAttribute(
        "position",
        new THREE.BufferAttribute(particlePositions(grid.columns, grid.rows), 3),
      );

      const uniforms = {
        uTime: { value: 0 },
        uAspect: { value: 1 },
        uPixelRatio: { value: renderer.getPixelRatio() },
        uEnergy: { value: 0.25 },
        uStrength: { value: settingsRef.current.strength },
        uRadius: { value: settingsRef.current.radius },
        uSwirl: { value: settingsRef.current.swirl },
        uTurbulence: { value: settingsRef.current.turbulence },
        uPointSize: { value: settingsRef.current.pointSize },
        uColourSpeed: { value: settingsRef.current.colourSpeed },
        uCalm: { value: settingsRef.current.calmMotion ? 1 : 0 },
        uPointer: { value: new THREE.Vector2(0.5, 0.5) },
        uVelocity: { value: new THREE.Vector2(0, 0) },
      };

      material = new THREE.ShaderMaterial({
        uniforms,
        vertexShader: particleVertexShader,
        fragmentShader: particleFragmentShader,
        transparent: true,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
        depthTest: false,
      });

      const field = new THREE.Points(geometry, material);
      scene.add(field);

      let lastFrameAt = performance.now();
      let statsWindowStartedAt = lastFrameAt;
      let frameCount = 0;
      let smoothedEnergy = 0.18;

      const resize = () => {
        if (!renderer || !geometry || webglFailed) return;
        try {
          const width = canvas.clientWidth || window.innerWidth;
          const height = canvas.clientHeight || window.innerHeight;
          const aspect = width / Math.max(height, 1);
          const nextGrid = viewportGrid(
            settingsRef.current.quality,
            hardwareConcurrency,
            aspect,
          );
          if (
            nextGrid.columns !== grid.columns
            || nextGrid.rows !== grid.rows
          ) {
            grid = nextGrid;
            const nextGeometry = new THREE.BufferGeometry();
            nextGeometry.setAttribute(
              "position",
              new THREE.BufferAttribute(
                particlePositions(grid.columns, grid.rows),
                3,
              ),
            );
            nextGeometry.computeBoundingSphere();
            field.geometry = nextGeometry;
            geometry.dispose();
            geometry = nextGeometry;
          }

          renderer.setPixelRatio(
            Math.min(window.devicePixelRatio || 1, grid.pixelRatio),
          );
          renderer.setSize(width, height, false);
          camera.left = -aspect;
          camera.right = aspect;
          camera.top = 1;
          camera.bottom = -1;
          camera.updateProjectionMatrix();
          uniforms.uAspect.value = aspect;
          uniforms.uPixelRatio.value = renderer.getPixelRatio();
        } catch {
          activateFallback();
        }
      };

      const render = (timestamp: number) => {
        if (!renderer || webglFailed) return;
        const delta = Math.min(50, timestamp - lastFrameAt);
        lastFrameAt = timestamp;
        frameCount += 1;
        const activeInteraction = sampleInteraction(timestamp);

        const energyResponse = settingsRef.current.calmMotion ? 0.42 : 1;
        const targetEnergy = activeInteraction.energy * energyResponse;
        const energyLerp = targetEnergy > smoothedEnergy ? 0.2 : 0.055;
        smoothedEnergy += (targetEnergy - smoothedEnergy)
          * energyLerp
          * Math.min(2, delta / 16.67);

        uniforms.uTime.value = timestamp * 0.001;
        uniforms.uEnergy.value = smoothedEnergy;
        uniforms.uPointer.value.set(activeInteraction.x, activeInteraction.y);
        uniforms.uVelocity.value.set(activeInteraction.vx, activeInteraction.vy);
        uniforms.uStrength.value = settingsRef.current.strength;
        uniforms.uRadius.value = settingsRef.current.radius;
        uniforms.uSwirl.value = settingsRef.current.swirl;
        uniforms.uTurbulence.value = settingsRef.current.turbulence;
        uniforms.uPointSize.value = settingsRef.current.pointSize;
        uniforms.uColourSpeed.value = settingsRef.current.colourSpeed;
        uniforms.uCalm.value = settingsRef.current.calmMotion ? 1 : 0;

        try {
          renderer.render(scene, camera);
        } catch {
          activateFallback();
          return;
        }

        if (timestamp - statsWindowStartedAt >= 1000) {
          const fps = Math.round(
            frameCount * 1000 / (timestamp - statsWindowStartedAt),
          );
          statsCallbackRef.current(fps, grid.columns * grid.rows);
          frameCount = 0;
          statsWindowStartedAt = timestamp;
        }

        if (!webglFailed) frameId = window.requestAnimationFrame(render);
      };

      canvas.addEventListener("webglcontextlost", onContextLost);
      resize();
      renderer.compile(scene, camera);
      if (!webglFailed) frameId = window.requestAnimationFrame(render);

      window.addEventListener("resize", resize);

      return () => {
        window.removeEventListener("resize", resize);
        canvas.removeEventListener("webglcontextlost", onContextLost);
        window.cancelAnimationFrame(frameId);
        geometry?.dispose();
        material?.dispose();
        try {
          renderer?.dispose();
        } catch {
          // A lost context may reject renderer cleanup; the 2D canvas is independent.
        }
      };
    } catch {
      geometry?.dispose();
      material?.dispose();
      try {
        renderer?.dispose();
      } catch {
        // Renderer construction can fail before a complete context exists.
      }
      activateFallback();
      return;
    }
  }, [interactionRef, renderMode, settings.quality, videoRef]);

  return (
    <>
      <canvas
        ref={canvasRef}
        className="field-canvas"
        aria-hidden="true"
        style={{ visibility: renderMode === "webgl" ? "visible" : "hidden" }}
      />
      <canvas
        ref={fallbackCanvasRef}
        className="field-canvas"
        aria-hidden="true"
        style={{ visibility: renderMode === "canvas-2d" ? "visible" : "hidden" }}
      />
    </>
  );
}
