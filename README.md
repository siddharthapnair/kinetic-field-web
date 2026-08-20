# Kinetic Field

A webcam-driven generative particle installation for the browser. Movement becomes force, turbulence and colour in a live WebGL field inspired by interactive projection art.

## What it does

- Reads motion from a normal laptop webcam
- Processes all camera frames locally in the browser
- Renders up to 32,400 GPU-driven particles in one draw call
- Works immediately with mouse, pen or touch when camera access is unavailable
- Provides force, radius, swirl, turbulence, glow and colour controls
- Includes automatic, low and high performance modes
- Supports fullscreen projector use, reduced motion and keyboard control
- Builds to a static `dist` directory ready for Firebase Hosting

## Privacy model

Camera frames never leave the device. The app requests video only, with audio explicitly disabled. Frames are reduced to a small local motion map and are neither uploaded nor stored. Turning the camera off, closing the page or leaving the page stops the media tracks.

## Local development

Requirements: Node.js 24 and npm.

```bash
npm install
npm run dev
```

Open the local address printed in the terminal. Webcam access works on `localhost` and `127.0.0.1` without HTTPS.

## Verification

```bash
npm run lint
npm test
npm run build
```

The production build also enforces network and parse-size budgets. It fails if
the JavaScript exceeds 800 KiB raw or 220 KiB gzip in total, if one JavaScript
chunk exceeds 550 KiB raw or 145 KiB gzip, or if CSS exceeds 20 KiB gzip.

## Controls

- `C`: enable or disable the camera
- `F`: enter or exit fullscreen
- `R`: restore field defaults
- `Escape`: close open interface panels

Pointer and touch input remain available in every camera state.

## Firebase Hosting

The recommended production topology is a dedicated Firebase Hosting site
connected to its own subdomain, for example `kinetic.yourdomain.com`. The site
may live in a new Firebase project or alongside other Hosting sites in an
existing project. In either case, the repository deliberately uses the named
Hosting target `kinetic-field`, so deployment remains explicit.

For a fully isolated project:

1. Create a new Firebase project.
2. Run `firebase use --add` and select it.
3. Create or select a Hosting site.
4. Bind that site to the target with `firebase target:apply hosting kinetic-field YOUR_HOSTING_SITE_ID`.
5. Run `npm run build`.
6. Deploy with `firebase deploy --only hosting:kinetic-field`.

For a second site inside an existing Firebase project, create the secondary site first and bind only that site to `kinetic-field`. Do not deploy this repository to an existing default Hosting site.

Firebase supplies HTTPS on its generated domains and connected custom domains,
which is required for webcam access outside local development. The Hosting
configuration also limits camera access to this origin, disables microphone
access and applies a self-hosted Content Security Policy compatible with this
app's webcam stream and WebGL renderer.

### Existing-site path

A URL path such as `yourdomain.com/kinetic-field/` is not a separate Firebase
Hosting destination. DNS operates at the hostname level, not the path level. To
use an existing path, integrate this build into that site's deployment, place
the generated files beneath the chosen directory and add a rewrite scoped only
to that directory. Do not use this repository's broad `**` rewrite unchanged,
because it is designed to own a dedicated Hosting site. Vite emits relative
asset URLs so the compiled app itself remains portable to such a directory.

The security policy permits same-origin framing only. A cross-origin iframe
deployment needs a deliberate `frame-ancestors` change, an iframe `allow`
policy for the camera and a matching camera policy on the parent site.

The source uses a relative social-image path so builds remain environment
independent. Once a canonical public hostname is fixed, an absolute Open Graph
image URL can improve compatibility with social crawlers.

The checked-in GitHub Actions workflow verifies the app only. It contains no
Firebase credentials and cannot deploy. Configure deployment separately after
the dedicated Hosting site and target have been chosen.

## Architecture

- React handles consent, camera states and operator controls.
- Three.js owns one WebGL point field and a custom shader.
- A low-resolution motion analyser measures position, velocity and energy from consecutive frames.
- The shader converts that interaction into local vortex, drag, wave depth and reactive colour.
- No backend, account, database or external inference service is required.

## Browser support

Current Chrome, Edge and Safari are the primary targets. Browsers must support WebGL and `navigator.mediaDevices.getUserMedia`. If either capability is unavailable, the pointer experience still works.
