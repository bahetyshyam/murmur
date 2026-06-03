import { app, Tray, Menu, BrowserWindow, nativeImage, shell, session, ipcMain, screen } from 'electron'
import { join } from 'path'
import { writeFile } from 'fs/promises'
import { tmpdir } from 'os'
import {
  TRAY_ICON_IDLE_1X,
  TRAY_ICON_IDLE_2X,
  TRAY_ICON_RECORDING_1X,
  TRAY_ICON_RECORDING_2X,
} from './trayIcon'
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
let hudWin: BrowserWindow | null = null
let state: AppState = 'idle'
let lastError = ''

const RENDERER_URL = process.env['ELECTRON_RENDERER_URL']

// Single instance. Each Electron instance creates its OWN tray; stale/duplicate
// instances pile up and wedge the menu-bar slot so no icon appears. Acquire the
// lock as early as possible — a second launch just exits.
const hasInstanceLock = app.requestSingleInstanceLock()
if (!hasInstanceLock) app.quit()

function trayImage(s: AppState): Electron.NativeImage {
  // Build a MULTI-REPRESENTATION template image: an 18px @1x rep AND a 36px @2x
  // rep. On HiDPI (2x) menu bars macOS requests the @2x backing pixels; with a
  // single-scale image (the old resize() path) there is none, so the status
  // item's content view lays out with HEIGHT 0 and the icon is invisible. Adding
  // both reps gives macOS real backing at either scale so it always draws.
  const oneX = s === 'recording' ? TRAY_ICON_RECORDING_1X : TRAY_ICON_IDLE_1X
  const twoX = s === 'recording' ? TRAY_ICON_RECORDING_2X : TRAY_ICON_IDLE_2X
  const img = nativeImage.createEmpty()
  img.addRepresentation({ scaleFactor: 1, dataURL: oneX })
  img.addRepresentation({ scaleFactor: 2, dataURL: twoX })
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
  const menu = buildMenu()
  // Mirror the menu onto the Dock icon (right-click), so the same actions work
  // even when Tahoe hides the tray. Kept in sync with state on every refresh.
  app.dock?.setMenu(menu)
  if (!tray) return
  tray.setImage(trayImage(state))
  tray.setToolTip('Murmur')
  tray.setContextMenu(menu)
}

/** Drives the tray glyph + state row + HUD. Other subsystems call this. */
export function setState(next: AppState, errorMessage = ''): void {
  state = next
  lastError = errorMessage
  refreshTray()
  syncHud()
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

// --- Recording HUD overlay (Phase G) ---------------------------------------
// A transparent, frameless, click-through, always-on-top, all-spaces window
// that floats a small pill near the bottom-center: live level bars while
// recording, a spinner while transcribing. It never steals focus.
const HUD_W = 220
const HUD_H = 72

function createHud(): void {
  hudWin = new BrowserWindow({
    width: HUD_W,
    height: HUD_H,
    show: false,
    frame: false,
    transparent: true,
    hasShadow: false,
    resizable: false,
    movable: false,
    focusable: false, // never take keyboard focus
    skipTaskbar: true,
    alwaysOnTop: true,
    fullscreenable: false,
    webPreferences: {
      preload: join(__dirname, '../preload/hud.js'),
      contextIsolation: true,
      sandbox: true,
    },
  })
  hudWin.setIgnoreMouseEvents(true) // click-through: pointer events pass through
  hudWin.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
  hudWin.setAlwaysOnTop(true, 'screen-saver') // float above fullscreen apps too
  // Re-assert the current state once the renderer is loaded (covers a state
  // change that raced the initial load).
  hudWin.webContents.on('did-finish-load', () => hudWin?.webContents.send('hud:state', state))
  if (RENDERER_URL) {
    hudWin.loadURL(`${RENDERER_URL}/hud.html`)
  } else {
    hudWin.loadFile(join(__dirname, '../renderer/hud.html'))
  }
}

function positionHud(): void {
  if (!hudWin || hudWin.isDestroyed()) return
  // Bottom-center of the display under the cursor (so it appears where you're
  // working on a multi-display setup), ~96px above the work-area bottom.
  const display = screen.getDisplayNearestPoint(screen.getCursorScreenPoint())
  const { x, y, width, height } = display.workArea
  hudWin.setPosition(Math.round(x + (width - HUD_W) / 2), Math.round(y + height - HUD_H - 96))
}

// Show the HUD while recording/transcribing, hide it otherwise. Uses
// showInactive() so it never steals focus from the app you're dictating into.
function syncHud(): void {
  if (!hudWin || hudWin.isDestroyed()) return
  hudWin.webContents.send('hud:state', state)
  const shouldShow = state === 'recording' || state === 'transcribing'
  if (shouldShow) {
    positionHud()
    if (!hudWin.isVisible()) hudWin.showInactive()
  } else if (hudWin.isVisible()) {
    hudWin.hide()
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

// Live mic level from the capture host → drives the HUD level bars.
ipcMain.on('rec:level', (_e, level: number) => {
  if (hudWin && !hudWin.isDestroyed()) hudWin.webContents.send('hud:level', level)
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
  if (!hasInstanceLock) return

  // Murmur shows a DOCK icon (clicking it opens Settings — see the 'activate'
  // handler). The Dock is the reliable entry point: macOS 26 "Tahoe" has a known
  // OS bug that hides third-party menu-bar items (affects many apps, not just
  // us), so we no longer depend on the tray alone. The tray is still created for
  // platforms / users where the menu bar renders it.
  if (process.platform === 'darwin') {
    app.setActivationPolicy('regular')
    app.dock?.show()
  }

  // Create the tray before any BrowserWindow (creating a window first can wedge
  // the tray's menu-bar slot on macOS). The icon ships @1x + @2x reps so it draws
  // on HiDPI menu bars; on Tahoe macOS may still hide it — the Dock covers that.
  tray = new Tray(trayImage('idle'))
  refreshTray()

  allowMediaPermissions()
  createRecorderHost()
  createHud()

  // Prune old history on launch (parity with the Swift app).
  try {
    const deleted = pruneHistory(DEFAULTS.retentionDays)
    if (deleted > 0) console.log(`[history] pruned ${deleted} transcripts older than ${DEFAULTS.retentionDays}d`)
  } catch (e) {
    console.error('[history] prune failed:', e)
  }

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

// Clicking the Dock icon (or otherwise activating the app) opens Settings — the
// reliable way to reach the UI given Tahoe's tray flakiness. Guarded on isReady
// so a launch-time activate can't run before the app is initialized.
app.on('activate', () => {
  if (app.isReady()) showSettings('main')
})

// Background app: don't quit when the last window closes (the Dock icon + tray
// keep it running; reopen Settings via the Dock).
app.on('window-all-closed', () => {})
app.on('will-quit', () => stopHotkey())
