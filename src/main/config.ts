import { app } from 'electron'
import { join } from 'path'
import { readFileSync, writeFileSync } from 'fs'

// Persisted user settings (parity with the Swift AppConfig). Stored as JSON in
// userData; the OpenAI key is NOT here — it lives in the Keychain (keyStore).
export interface MurmurConfig {
  model: string
  deviceId: string // '' = system default
  hotkey: string // key id: alt_r | alt_l | cmd_r | ctrl_r | shift_r
  pasteAtCursor: boolean
  autoUpdate: boolean
  retentionDays: number
  onboardingSeen: boolean // shown the 7-step wizard at least once
}

const DEFAULTS: MurmurConfig = {
  model: 'gpt-4o-transcribe',
  deviceId: '',
  hotkey: 'alt_r',
  pasteAtCursor: true,
  autoUpdate: true,
  retentionDays: 30,
  onboardingSeen: false,
}

let cache: MurmurConfig | null = null

function configPath(): string {
  return join(app.getPath('userData'), 'config.json')
}

export function getConfig(): MurmurConfig {
  if (cache) return cache
  let loaded: MurmurConfig
  try {
    loaded = { ...DEFAULTS, ...JSON.parse(readFileSync(configPath(), 'utf8')) }
  } catch {
    loaded = { ...DEFAULTS }
  }
  cache = loaded
  return loaded
}

export function setConfig(patch: Partial<MurmurConfig>): MurmurConfig {
  const next = { ...getConfig(), ...patch }
  cache = next
  try {
    writeFileSync(configPath(), JSON.stringify(next, null, 2))
  } catch (e) {
    console.error('[config] write failed:', e)
  }
  return next
}
