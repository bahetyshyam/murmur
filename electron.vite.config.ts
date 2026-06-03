import { resolve } from 'path'
import { defineConfig, externalizeDepsPlugin } from 'electron-vite'
import react from '@vitejs/plugin-react'

// macOS-first Electron + React + TS. One renderer for now (Settings); the
// HUD / History / Onboarding windows get added as additional HTML entries in
// later phases.
export default defineConfig({
  main: {
    // Keep production deps (e.g. better-sqlite3) OUT of the bundle so native
    // modules are require'd from node_modules at runtime — bundling them breaks
    // their .node binding loader in the packaged app.
    plugins: [externalizeDepsPlugin()],
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
    plugins: [externalizeDepsPlugin()],
    build: {
      rollupOptions: {
        input: {
          index: resolve(__dirname, 'src/preload/index.ts'),
          'recorder-host': resolve(__dirname, 'src/preload/recorder-host.ts'),
          hud: resolve(__dirname, 'src/preload/hud.ts'),
        },
      },
    },
  },
  renderer: {
    root: 'src/renderer',
    build: {
      rollupOptions: {
        input: {
          settings: resolve(__dirname, 'src/renderer/index.html'),
          'recorder-host': resolve(__dirname, 'src/renderer/recorder-host.html'),
          hud: resolve(__dirname, 'src/renderer/hud.html'),
          onboarding: resolve(__dirname, 'src/renderer/onboarding.html'),
          permissions: resolve(__dirname, 'src/renderer/permissions.html'),
        },
      },
    },
    plugins: [react()],
  },
})
