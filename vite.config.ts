import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  // Relative asset URLs keep the static build portable between a dedicated
  // hostname and a directory owned by an existing site.
  base: "./",
  plugins: [react()],
  build: {
    // The executable budget is enforced after every production build. This
    // warning remains slightly below that hard ceiling for earlier feedback.
    chunkSizeWarningLimit: 550,
  },
  server: {
    host: "127.0.0.1",
  },
  preview: {
    host: "127.0.0.1",
  },
});
