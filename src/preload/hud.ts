import { contextBridge, ipcRenderer } from 'electron'

// Preload for the recording HUD overlay. Receive-only: main pushes the app
// state (recording/transcribing/idle/error) and live mic levels; the HUD never
// sends anything back.
const hud = {
  onState: (cb: (state: string) => void): void => {
    ipcRenderer.on('hud:state', (_e, state: string) => cb(state))
  },
  onLevel: (cb: (level: number) => void): void => {
    ipcRenderer.on('hud:level', (_e, level: number) => cb(level))
  },
}

contextBridge.exposeInMainWorld('hud', hud)

export type HudApi = typeof hud
