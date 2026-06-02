import { resolve } from 'path'
import { defineConfig } from 'electron-vite'
import react from '@vitejs/plugin-react'

// macOS-first Electron + React + TS. One renderer for now (Settings); the
// HUD / History / Onboarding windows get added as additional HTML entries in
// later phases.
export default defineConfig({
  main: {
    build: {
      rollupOptions: {
        input: { index: resolve(__dirname, 'src/main/index.ts') },
        // The native hotkey addon is loaded via createRequire at a runtime path
        // — never bundle the .node binary into the main chunk.
        external: [/\.node$/],
      },
    },
  },
  preload: {
    build: {
      rollupOptions: {
        input: { index: resolve(__dirname, 'src/preload/index.ts') },
      },
    },
  },
  renderer: {
    root: 'src/renderer',
    build: {
      rollupOptions: {
        input: { settings: resolve(__dirname, 'src/renderer/index.html') },
      },
    },
    plugins: [react()],
  },
})
