import { app, Tray, Menu, BrowserWindow, nativeImage, shell, session, ipcMain } from 'electron'
import { join } from 'path'
import { writeFile } from 'fs/promises'
import { tmpdir } from 'os'
import { TRAY_ICON_IDLE, TRAY_ICON_RECORDING } from './trayIcon'

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
    { type: 'separator' },
    { label: 'History…', click: () => { /* Phase F */ } },
    { label: 'Settings…', accelerator: 'CmdOrCtrl+,', click: () => showSettings() },
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

function showSettings(): void {
  if (settingsWindow && !settingsWindow.isDestroyed()) {
    settingsWindow.show()
    settingsWindow.focus()
    return
  }
  settingsWindow = new BrowserWindow({
    width: 520,
    height: 420,
    resizable: true,
    title: 'Murmur Settings',
    show: false,
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      sandbox: true,
    },
  })
  settingsWindow.on('ready-to-show', () => settingsWindow?.show())
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

app.whenReady().then(() => {
  // Dock-less accessory app (Swift LSUIElement parity). NOTE: the tray only
  // renders in a packaged Murmur.app bundle — dev-mode `npx electron .` (the
  // generic com.github.Electron) does not get a menu-bar slot. Test the tray
  // via the packaged app (npm run pack).
  app.dock?.hide()
  if (process.platform === 'darwin') app.setActivationPolicy('accessory')

  allowMediaPermissions()

  tray = new Tray(trayImage('idle'))
  refreshTray()
})

// Menubar app: don't quit when the last window closes.
app.on('window-all-closed', () => {})
