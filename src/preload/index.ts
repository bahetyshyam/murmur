import { contextBridge } from 'electron'

// Phase A: minimal, typed bridge. Each later phase adds parameterized,
// validated channels (recording, transcribe, settings, history, key,
// permissions, hotkey, hud, update) — never raw ipcRenderer.
const api = {
  version: '2.0.0-dev',
}

contextBridge.exposeInMainWorld('murmur', api)

export type MurmurApi = typeof api
