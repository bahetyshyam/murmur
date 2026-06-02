import { contextBridge, ipcRenderer } from 'electron'

export interface TranscribeError {
  kind: string
  userMessage: string
  description: string
  status?: number
}
export type TranscribeOutcome = { ok: true; text: string } | { ok: false; error: TranscribeError }

// Typed, parameterized bridge — never raw ipcRenderer. The OpenAI key lives
// only in main; the renderer can set/clear/check it but never read it back.
const api = {
  version: '2.0.0-dev',

  // Phase C — API key (main-only) + transcription.
  key: {
    set: (plain: string): Promise<void> => ipcRenderer.invoke('key:set', plain),
    clear: (): Promise<void> => ipcRenderer.invoke('key:clear'),
    status: (): Promise<boolean> => ipcRenderer.invoke('key:status'),
  },
  transcribe: (
    wav: ArrayBuffer,
    opts: { model: string; prompt?: string; language?: string },
  ): Promise<TranscribeOutcome> => ipcRenderer.invoke('transcribe', wav, opts),

  // Phase B (debug): write a captured WAV to a temp file to verify its format.
  debugSaveWav: (wav: ArrayBuffer): Promise<string> => ipcRenderer.invoke('debug:save-wav', wav),
}

contextBridge.exposeInMainWorld('murmur', api)

export type MurmurApi = typeof api
