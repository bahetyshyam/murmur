import { contextBridge, ipcRenderer } from 'electron'

export interface TranscribeError {
  kind: string
  userMessage: string
  description: string
  status?: number
}
export type TranscribeOutcome = { ok: true; text: string } | { ok: false; error: TranscribeError }

export interface Transcript {
  id: number
  timestamp: number
  text: string
  model: string
  durationS: number | null
  pasted: boolean
  error: string | null
}
export interface UsageRow {
  model: string
  count: number
  totalSeconds: number
  cost: number
}
export interface MurmurConfig {
  model: string
  deviceId: string
  hotkey: string
  pasteAtCursor: boolean
  autoUpdate: boolean
  retentionDays: number
}

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

  // Phase F — history + usage.
  history: {
    recent: (limit?: number): Promise<Transcript[]> => ipcRenderer.invoke('history:recent', limit),
    delete: (id: number): Promise<void> => ipcRenderer.invoke('history:delete', id),
    usage: (): Promise<UsageRow[]> => ipcRenderer.invoke('history:usage'),
  },
  // Persisted settings (model, mic, hotkey, paste, auto-update, retention).
  config: {
    get: (): Promise<MurmurConfig> => ipcRenderer.invoke('config:get'),
    set: (patch: Partial<MurmurConfig>): Promise<MurmurConfig> => ipcRenderer.invoke('config:set', patch),
  },

  // Main asks the Settings window to switch tabs (e.g. tray → History…).
  onSetTab: (cb: (tab: string) => void): void => {
    ipcRenderer.on('ui:set-tab', (_e, tab: string) => cb(tab))
  },

  // Phase B (debug): write a captured WAV to a temp file to verify its format.
  debugSaveWav: (wav: ArrayBuffer): Promise<string> => ipcRenderer.invoke('debug:save-wav', wav),
}

contextBridge.exposeInMainWorld('murmur', api)

export type MurmurApi = typeof api
