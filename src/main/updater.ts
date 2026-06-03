import { app, dialog, BrowserWindow } from 'electron'
import electronUpdater from 'electron-updater'
import { getConfig } from './config'

const { autoUpdater } = electronUpdater

// Self-signed auto-update via GitHub releases (electron-updater reads the
// generated latest-mac.yml + the .zip). Updates only verify across versions
// when every release is signed by the SAME stable identity — see RELEASING.md.
let wired = false
let manual = false

function info(message: string, detail: string): void {
  const win = BrowserWindow.getFocusedWindow()
  const opts: Electron.MessageBoxOptions = { type: 'info', message, detail, buttons: ['OK'] }
  if (win) void dialog.showMessageBox(win, opts)
  else void dialog.showMessageBox(opts)
}

function wire(): void {
  if (wired) return
  wired = true
  autoUpdater.autoDownload = true
  autoUpdater.autoInstallOnAppQuit = true

  autoUpdater.on('update-not-available', () => {
    if (manual) info("You're up to date", `Murmur ${app.getVersion()} is the latest version.`)
    manual = false
  })
  autoUpdater.on('update-available', () => {
    if (manual) info('Update available', "Downloading in the background — you'll be prompted to restart when it's ready.")
  })
  autoUpdater.on('error', (e) => {
    console.error('[updater]', e?.message ?? e)
    if (manual) info('Check for updates', 'Could not reach the update server. Try again later.')
    manual = false
  })
  autoUpdater.on('update-downloaded', (i) => {
    manual = false
    const win = BrowserWindow.getFocusedWindow()
    const opts: Electron.MessageBoxOptions = {
      type: 'info',
      message: `Murmur ${i.version} is ready`,
      detail: 'Restart to finish updating.',
      buttons: ['Restart now', 'Later'],
      defaultId: 0,
      cancelId: 1,
    }
    const p = win ? dialog.showMessageBox(win, opts) : dialog.showMessageBox(opts)
    void p.then((r) => { if (r.response === 0) autoUpdater.quitAndInstall() })
  })
}

/** Silent background check (honors the autoUpdate setting). UI only on download. */
export function checkForUpdatesBackground(): void {
  if (!getConfig().autoUpdate) return
  wire()
  manual = false
  autoUpdater.checkForUpdates().catch((e) => console.error('[updater] bg check failed:', e?.message ?? e))
}

/** Manual "Check for Updates…" — always reports the outcome. */
export function checkForUpdatesInteractive(): void {
  wire()
  manual = true
  autoUpdater.checkForUpdates().catch((e) => {
    console.error('[updater] check failed:', e?.message ?? e)
    info('Check for updates', 'Could not reach the update server. Try again later.')
    manual = false
  })
}
