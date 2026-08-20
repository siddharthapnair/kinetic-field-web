export const particleVertexShader = /* glsl */ `
  uniform float uTime;
  uniform float uAspect;
  uniform float uPixelRatio;
  uniform float uEnergy;
  uniform float uStrength;
  uniform float uRadius;
  uniform float uSwirl;
  uniform float uTurbulence;
  uniform float uPointSize;
  uniform float uColourSpeed;
  uniform float uCalm;
  uniform vec2 uPointer;
  uniform vec2 uVelocity;

  varying vec3 vColour;
  varying float vAlpha;

  vec3 hsv2rgb(vec3 c) {
    vec3 rgb = clamp(abs(mod(c.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    rgb = rgb * rgb * (3.0 - 2.0 * rgb);
    return c.z * mix(vec3(1.0), rgb, c.y);
  }

  float fieldNoise(vec2 p, float t) {
    return sin(p.x * 8.3 + t * 0.71) * cos(p.y * 7.1 - t * 0.63)
      + sin((p.x + p.y) * 13.7 - t * 0.39) * 0.45;
  }

  void main() {
    vec3 displaced = position;
    displaced.x *= uAspect;

    vec2 pointerWorld = vec2((uPointer.x - 0.5) * 2.0 * uAspect, (0.5 - uPointer.y) * 2.0);
    vec2 delta = displaced.xy - pointerWorld;
    float distanceToPointer = length(delta) + 0.0001;
    float influence = exp(-(distanceToPointer * distanceToPointer) / max(0.025, uRadius * uRadius));
    float speed = min(1.0, length(uVelocity) * 9.0);
    float activeEnergy = max(uEnergy, speed * 0.75);
    vec2 tangent = vec2(-delta.y, delta.x) / distanceToPointer;
    vec2 radial = delta / distanceToPointer;

    float motionGate = smoothstep(0.01, 0.16, activeEnergy) + (1.0 - uCalm) * 0.12;
    float quietNoise = fieldNoise(displaced.xy, uTime) * 0.008 * (1.0 - uCalm);
    displaced.xy += vec2(quietNoise, -quietNoise * 0.72);

    float rotatingWave = sin(distanceToPointer * 24.0 - uTime * 3.4 + activeEnergy * 2.0);
    float swirlForce = influence * uSwirl * uStrength * (0.035 + activeEnergy * 0.135) * motionGate;
    float radialForce = influence * rotatingWave * uStrength * (0.012 + activeEnergy * 0.052) * motionGate;
    displaced.xy += tangent * swirlForce;
    displaced.xy += radial * radialForce;
    displaced.xy += vec2(uVelocity.x * uAspect, -uVelocity.y) * influence * uStrength * 0.58;

    float turbulence = fieldNoise(displaced.xy * 1.8, uTime * 1.3) * uTurbulence;
    displaced.z += influence * (0.22 + activeEnergy * 0.62) * (0.72 + turbulence * 0.28) * motionGate;
    displaced.z += sin(position.x * 10.0 + position.y * 8.0 + uTime * 0.8) * 0.012 * (1.0 - uCalm);

    float angle = atan(delta.y, delta.x) / 6.2831853;
    float baseHue = fract(0.52 + position.x * 0.045 + position.y * 0.035 + uTime * uColourSpeed * 0.018 * (1.0 - uCalm));
    float reactiveHue = fract(baseHue + angle * 0.62 + influence * 0.48 + activeEnergy * 0.17);
    vec3 restingColour = hsv2rgb(vec3(baseHue, 0.72, 0.58));
    vec3 reactiveColour = hsv2rgb(vec3(reactiveHue, 0.92, 1.0));
    float colourMix = clamp(influence * (0.44 + activeEnergy * 1.3), 0.0, 1.0);
    vColour = mix(restingColour, reactiveColour, colourMix);
    vAlpha = 0.16 + influence * (0.36 + activeEnergy * 0.58);

    gl_Position = projectionMatrix * modelViewMatrix * vec4(displaced, 1.0);
    gl_PointSize = uPointSize * uPixelRatio * (0.78 + influence * (0.65 + activeEnergy * 1.55));
  }
`;

export const particleFragmentShader = /* glsl */ `
  varying vec3 vColour;
  varying float vAlpha;

  void main() {
    vec2 centred = gl_PointCoord - vec2(0.5);
    float distanceFromCentre = length(centred);
    if (distanceFromCentre > 0.5) discard;
    float softDisc = smoothstep(0.5, 0.04, distanceFromCentre);
    float core = smoothstep(0.24, 0.0, distanceFromCentre);
    gl_FragColor = vec4(vColour * (0.82 + core * 0.55), vAlpha * softDisc);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }
`;
