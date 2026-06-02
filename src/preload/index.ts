import { contextBridge, ipcRenderer } from 'electron'

// Typed, parameterized bridge — never raw ipcRenderer. Each phase adds channels.
const api = {
  version: '2.0.0-dev',
  // Phase B (debug): write a captured WAV to a temp file so we can verify its
  // format (ffprobe/hexdump). Removed once transcription (Phase C) lands.
  debugSaveWav: (wav: ArrayBuffer): Promise<string> => ipcRenderer.invoke('debug:save-wav', wav),
}

contextBridge.exposeInMainWorld('murmur', api)

export type MurmurApi = typeof api
