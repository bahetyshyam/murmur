import { contextBridge, ipcRenderer } from 'electron'

export interface RecResult {
  ok: boolean
  wav?: ArrayBuffer
  durationS?: number
  peakLevel?: number
  error?: string
}

// Preload for the hidden capture-host window. Main drives recording over IPC
// (rec:start / rec:stop); the host streams levels and returns the WAV.
const recHost = {
  onStart: (cb: (deviceId: string) => void) =>
    ipcRenderer.on('rec:start', (_e, deviceId: string) => cb(deviceId)),
  onStop: (cb: () => void) => ipcRenderer.on('rec:stop', () => cb()),
  sendReady: () => ipcRenderer.send('rec:ready'),
  sendStarted: (payload: { ok: boolean; error?: string }) => ipcRenderer.send('rec:started', payload),
  sendLevel: (level: number) => ipcRenderer.send('rec:level', level),
  sendResult: (payload: RecResult) => ipcRenderer.send('rec:result', payload),
}

contextBridge.exposeInMainWorld('recHost', recHost)

export type RecHostApi = typeof recHost
