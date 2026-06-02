import { app, Tray, Menu, BrowserWindow, nativeImage, shell, session, ipcMain } from 'electron'
import { join } from 'path'
import { writeFile } from 'fs/promises'
import { tmpdir } from 'os'
import { TRAY_ICON_IDLE, TRAY_ICON_RECORDING } from './trayIcon'
import { setKey, clearKey, hasKey, getKey } from './keyStore'
import { transcribe, makeError, type TranscribeOutcome } from './transcribe'
import { startHotkey, stopHotkey, promptAccessibility, isHotkeyInstalled, HOTKEY_KEYCODES } from './hotkey'
import { pasteText } from './paste'
import {
  appendTranscript,
  markPasted,
  pruneHistory,
  recentTranscripts,
  deleteTranscript,
  usageByModel,
  estimatedCost,
} from './history'

// Phase A — the menubar shell: a dock-less accessory app whose only persistent
// presence is the tray. Mirrors the Swift app's MenuBarController + AppDelegate
// at a structural level (state row, permission rows, History/Settings/etc.).
// State machine, hotkey, audio, etc. arrive in later phases.

type AppState = 'idle' | 'recording' | 'transcribing' | 'error'

let tray: Tray | null = null
let settingsWindow: BrowserWindow | null = null
let state: AppState = 'idle'
let lastError = ''

const RENDERER_URL = process.env['ELECTRON_RENDERER_URL']

function trayImage(s: AppState): Electron.NativeImage {
  const url = s === 'recording' ? TRAY_ICON_RECORDING : TRAY_ICON_IDLE
  const img = nativeImage.createFromDataURL(url).resize({ width: 18, height: 18 })
  img.setTemplateImage(true) // auto-tint for light/dark menubars
  return img
}

function stateLabel(s: AppState): string {
  switch (s) {
    case 'idle': return 'Idle'
    case 'recording': return 'Recording…'
    case 'transcribing': return 'Transcribing…'
    case 'error': return `Error: ${lastError}`
  }
}

function buildMenu(): Menu {
  return Menu.buildFromTemplate([
    { label: 'Murmur', enabled: false },
    { label: stateLabel(state), enabled: false },
    ...(isHotkeyInstalled()
      ? []
      : [
          { label: 'Hotkey disabled — grant Accessibility', enabled: false } as const,
          { label: 'Grant Accessibility Access…', click: () => promptAccessibility() } as const,
        ]),
    { type: 'separator' },
    { label: 'History…', click: () => showSettings('history') },
    { label: 'Settings…', accelerator: 'CmdOrCtrl+,', click: () => showSettings('main') },
    { label: 'Permissions Help…', click: () => { /* Phase H */ } },
    { label: 'Check for Updates…', click: () => { /* Phase I */ } },
    { type: 'separator' },
    { label: 'Quit Murmur', accelerator: 'CmdOrCtrl+Q', click: () => app.quit() },
  ])
}

function refreshTray(): void {
  if (!tray) return
  tray.setImage(trayImage(state))
  tray.setToolTip('Murmur')
  tray.setContextMenu(buildMenu())
}

/** Drives the tray glyph + state row. Other subsystems call this in later phases. */
export function setState(next: AppState, errorMessage = ''): void {
  state = next
  lastError = errorMessage
  refreshTray()
}

function showSettings(tab = 'main'): void {
  if (settingsWindow && !settingsWindow.isDestroyed()) {
    settingsWindow.webContents.send('ui:set-tab', tab)
    settingsWindow.show()
    settingsWindow.focus()
    return
  }
  settingsWindow = new BrowserWindow({
    width: 560,
    height: 460,
    resizable: true,
    title: 'Murmur',
    show: false,
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      sandbox: true,
    },
  })
  settingsWindow.on('ready-to-show', () => settingsWindow?.show())
  settingsWindow.webContents.on('did-finish-load', () => settingsWindow?.webContents.send('ui:set-tab', tab))
  settingsWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url)
    return { action: 'deny' }
  })
  if (RENDERER_URL) {
    settingsWindow.loadURL(RENDERER_URL)
  } else {
    settingsWindow.loadFile(join(__dirname, '../renderer/index.html'))
  }
}

// Allow microphone capture (getUserMedia) from our renderer. The macOS TCC
// prompt still fires on first use; the bundle's NSMicrophoneUsageDescription
// (set in electron-builder.yml) is what lets that prompt appear.
function allowMediaPermissions(): void {
  const ses = session.defaultSession
  // 'media' covers microphone capture in Electron's permission model.
  ses.setPermissionRequestHandler((_wc, permission, cb) => {
    cb(permission === 'media')
  })
  ses.setPermissionCheckHandler((_wc, permission) => {
    return permission === 'media'
  })
}

// Phase B (debug): persist a captured WAV so its format can be verified.
ipcMain.handle('debug:save-wav', async (_e, wav: ArrayBuffer): Promise<string> => {
  const path = join(tmpdir(), 'murmur_phaseB.wav')
  await writeFile(path, Buffer.from(wav))
  return path
})

// Phase C: API key storage (main-only) + transcription. The key never leaves
// main — the renderer can set/clear/check status but never read it back.
ipcMain.handle('key:set', (_e, plain: string) => setKey(plain))
ipcMain.handle('key:clear', () => clearKey())
ipcMain.handle('key:status', () => hasKey())

// Live mic level from the capture host (drives the HUD in Phase G).
ipcMain.on('rec:level', (_e, _level: number) => {
  // Phase G: forward to the HUD overlay window.
})

// History + usage (SQLite).
ipcMain.handle('history:recent', (_e, limit?: number) => recentTranscripts(limit ?? 200))
ipcMain.handle('history:delete', (_e, id: number) => deleteTranscript(id))
ipcMain.handle('history:usage', () =>
  usageByModel().map((r) => ({ ...r, cost: estimatedCost(r) })),
)

ipcMain.handle(
  'transcribe',
  async (
    _e,
    wav: ArrayBuffer,
    opts: { model: string; prompt?: string; language?: string },
  ): Promise<TranscribeOutcome> => {
    const apiKey = await getKey()
    if (!apiKey) return { ok: false, error: makeError({ kind: 'noKey' }) }
    return transcribe({ apiKey, wav, model: opts.model, prompt: opts.prompt, language: opts.language })
  },
)

app.whenReady().then(() => {
  // Dock-less accessory app (Swift LSUIElement parity). NOTE: the tray only
  // renders in a packaged Murmur.app bundle — dev-mode `npx electron .` (the
  // generic com.github.Electron) does not get a menu-bar slot. Test the tray
  // via the packaged app (npm run pack).
  app.dock?.hide()
  if (process.platform === 'darwin') app.setActivationPolicy('accessory')

  allowMediaPermissions()
  createRecorderHost()

  // Prune old history on launch (parity with the Swift app).
  try {
    const deleted = pruneHistory(DEFAULTS.retentionDays)
    if (deleted > 0) console.log(`[history] pruned ${deleted} transcripts older than ${DEFAULTS.retentionDays}d`)
  } catch (e) {
    console.error('[history] prune failed:', e)
  }

  tray = new Tray(trayImage('idle'))
  refreshTray()

  // Phase D: global modifier hotkey (Right Option). For now the toggle just
  // flips the tray glyph idle↔recording as a visible test; the full
  // record→transcribe→paste pipeline is wired once the state machine + capture
  // host exist. Installs once Accessibility is granted (polled, no prompt).
  startHotkey(
    HOTKEY_KEYCODES.alt_r,
    () => {
      void onHotkeyToggle().catch((e) => {
        console.error('[pipeline] toggle failed:', e)
        flashError('Something went wrong.')
      })
    },
    () => {
      console.log('[hotkey] installed (Accessibility granted)')
      refreshTray()
    },
  )
})

// --- Hidden capture host + the record→transcribe→paste pipeline -------------
// Defaults until Settings persistence lands (Phase H).
const DEFAULTS = { model: 'gpt-4o-transcribe', deviceId: '', pasteAtCursor: true, retentionDays: 30 }

interface RecResult { ok: boolean; wav?: ArrayBuffer; durationS?: number; peakLevel?: number; error?: string }
interface StartAck { ok: boolean; error?: string }

// "No speech" gate: gpt-4o-transcribe / Whisper hallucinate phrases ("Thank
// you", "はい", subtitle credits…) when fed silence. If the recording was too
// short or never rose above background level, skip the API call entirely
// (saves cost + avoids pasting garbage). Tunable.
const MIN_SPEECH_DURATION_S = 0.35
const SPEECH_PEAK_THRESHOLD = 0.05 // on the ×3-boosted smoothed level

let hostWin: BrowserWindow | null = null
let hostReady = false
let hostReadyWaiters: Array<() => void> = []

function createRecorderHost(): void {
  hostReady = false
  hostWin = new BrowserWindow({
    show: false,
    width: 1,
    height: 1,
    webPreferences: {
      preload: join(__dirname, '../preload/recorder-host.js'),
      contextIsolation: true,
      sandbox: true,
    },
  })
  // M3: if the capture renderer dies, recording would silently wedge forever.
  // Recreate it and recover the state machine.
  hostWin.webContents.on('render-process-gone', (_e, details) => {
    console.error('[host] render process gone:', details.reason, '— recreating')
    hostReady = false
    if (state === 'recording' || state === 'transcribing') setState('idle')
    createRecorderHost()
  })
  if (RENDERER_URL) {
    hostWin.loadURL(`${RENDERER_URL}/recorder-host.html`)
  } else {
    hostWin.loadFile(join(__dirname, '../renderer/recorder-host.html'))
  }
}

// M1: the host signals readiness once its IPC listeners are installed, so we
// never send rec:start into the void before the renderer is listening.
ipcMain.on('rec:ready', () => {
  hostReady = true
  hostReadyWaiters.forEach((w) => w())
  hostReadyWaiters = []
})

function whenHostReady(timeoutMs = 3000): Promise<boolean> {
  if (hostReady) return Promise.resolve(true)
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve(hostReady), timeoutMs)
    hostReadyWaiters.push(() => {
      clearTimeout(timer)
      resolve(true)
    })
  })
}

/** Send `channel` to the host and await its `reply` (listener registered first;
 *  resolves to `fallback` on timeout). */
function sendAndAwait<T>(reply: string, timeoutMs: number, fallback: T, send: () => void): Promise<T> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      ipcMain.removeListener(reply, handler)
      resolve(fallback)
    }, timeoutMs)
    const handler = (_e: Electron.IpcMainEvent, payload: T): void => {
      clearTimeout(timer)
      resolve(payload)
    }
    ipcMain.once(reply, handler)
    send()
  })
}

let errorClearTimer: ReturnType<typeof setTimeout> | null = null
function flashError(message: string): void {
  setState('error', message)
  if (errorClearTimer) clearTimeout(errorClearTimer)
  errorClearTimer = setTimeout(() => {
    if (state === 'error') setState('idle')
  }, 3000)
}

// N1: serialize toggles so the async start/stop transitions can't interleave.
let toggleBusy = false

// The hotkey toggle drives the full pipeline (Swift AppModel parity): ignored
// while transcribing/error; on idle→recording it starts capture (acked); on
// recording→transcribing it stops, transcribes, and pastes.
async function onHotkeyToggle(): Promise<void> {
  if (toggleBusy) return
  toggleBusy = true
  try {
    if (state === 'idle') {
      const ready = await whenHostReady()
      if (!ready || !hostWin) {
        flashError('Recorder unavailable — try again.')
        return
      }
      setState('recording')
      // M1/M2: await the start ack — covers a lost/late rec:start AND a
      // start failure (mic busy/denied), instead of wedging at "recording".
      const ack = await sendAndAwait<StartAck>('rec:started', 5000, { ok: false, error: 'timeout' }, () =>
        hostWin!.webContents.send('rec:start', DEFAULTS.deviceId),
      )
      if (!ack.ok) flashError(ack.error ? `Couldn't start recording: ${ack.error}` : "Couldn't start recording.")
      return
    }

    if (state !== 'recording') return // ignore while transcribing / error

    setState('transcribing')
    const rec = await sendAndAwait<RecResult>('rec:result', 30_000, { ok: false, error: 'recording timed out' }, () =>
      hostWin?.webContents.send('rec:stop'),
    )
    if (!rec.ok || !rec.wav) {
      flashError(rec.error ?? 'Recording failed')
      return
    }
    // Skip silence / accidental taps before spending an API call.
    if ((rec.durationS ?? 0) < MIN_SPEECH_DURATION_S || (rec.peakLevel ?? 0) < SPEECH_PEAK_THRESHOLD) {
      console.log('[pipeline] no speech (dur=%ss peak=%s) — skipping transcription', rec.durationS, rec.peakLevel)
      setState('idle')
      return
    }
    const apiKey = await getKey()
    if (!apiKey) {
      flashError('No API key — open Settings.')
      return
    }
    const outcome = await transcribe({ apiKey, wav: rec.wav, model: DEFAULTS.model })
    if (!outcome.ok) {
      // Record the failure (recoverable from History) then surface it.
      appendTranscript('', DEFAULTS.model, rec.durationS ?? 0, outcome.error.description)
      flashError(outcome.error.userMessage)
      return
    }
    // Persist BEFORE pasting (Swift AppModel order) so the text is recoverable
    // even if paste fails.
    const rowId = appendTranscript(outcome.text, DEFAULTS.model, rec.durationS ?? 0)
    if (outcome.text && DEFAULTS.pasteAtCursor) {
      if (pasteText(outcome.text)) {
        markPasted(rowId)
        setState('idle')
      } else {
        flashError('Paste failed — text is on the clipboard.')
      }
    } else {
      markPasted(rowId)
      setState('idle')
    }
  } finally {
    toggleBusy = false
  }
}

// Menubar app: don't quit when the last window closes.
app.on('window-all-closed', () => {})
app.on('will-quit', () => stopHotkey())
