import { app, systemPreferences } from 'electron'
import { createRequire } from 'node:module'
import { join } from 'path'

// Loads + drives the native CGEventTap modifier-hotkey addon. Mirrors the Swift
// HotkeyMonitor: install on the configured modifier, poll for Accessibility,
// debounce, fire a toggle. Down-edge detection lives in native; debounce here.

interface HotkeyAddon {
  install(targetKeycode: number, cb: (event: string) => void): boolean
  uninstall(): void
}

// Modifier keycodes (Swift parity). Default: Right Option (alt_r).
export const HOTKEY_KEYCODES: Record<string, number> = {
  alt_r: 61,
  alt_l: 58,
  cmd_r: 54,
  ctrl_r: 62,
  shift_r: 60,
}

const DEBOUNCE_MS = 200
const POLL_MS = 2000

let addon: HotkeyAddon | null = null
let pollTimer: ReturnType<typeof setInterval> | null = null
let installed = false
let lastToggle = 0

function loadAddon(): HotkeyAddon | null {
  if (addon) return addon
  try {
    // `.node` is asarUnpack'd in the packaged app; in dev it's in the repo.
    const rel = join('native', 'build', 'Release', 'hotkey.node')
    const path = app.isPackaged
      ? join(process.resourcesPath, 'app.asar.unpacked', rel)
      : join(app.getAppPath(), rel)
    addon = createRequire(__filename)(path) as HotkeyAddon
    return addon
  } catch (e) {
    console.error('[hotkey] failed to load native addon:', e)
    return null
  }
}

/** True once the Accessibility permission is granted and the tap is installed.
 *  Useful for the menubar "grant Accessibility" affordance. */
export function isHotkeyInstalled(): boolean {
  return installed
}

/** Start listening for the configured modifier hotkey, polling for the
 *  Accessibility grant until it's available (no relaunch needed). Does NOT
 *  prompt — prompting belongs to the onboarding wizard (Phase H). */
export function startHotkey(keycode: number, onToggle: () => void, onInstalled?: () => void): void {
  const a = loadAddon()
  if (!a) return

  const tryInstall = (): boolean => {
    if (installed) return true
    // Silent check (false) — never re-prompts; prompting is an explicit gesture.
    if (!systemPreferences.isTrustedAccessibilityClient(false)) return false
    const ok = a.install(keycode, (event) => {
      if (event !== 'toggle') return
      const now = Date.now()
      if (now - lastToggle < DEBOUNCE_MS) return
      lastToggle = now
      onToggle()
    })
    installed = ok
    if (ok) onInstalled?.()
    return ok
  }

  if (!tryInstall()) {
    pollTimer = setInterval(() => {
      if (tryInstall() && pollTimer) {
        clearInterval(pollTimer)
        pollTimer = null
      }
    }, POLL_MS)
  }
}

/** Surface the system Accessibility prompt + register the app in the Privacy
 *  list. Must be an EXPLICIT user gesture (menu / onboarding button), never at
 *  bootstrap (project rule). Returns whether already trusted. */
export function promptAccessibility(): boolean {
  return systemPreferences.isTrustedAccessibilityClient(true)
}

export function stopHotkey(): void {
  if (pollTimer) {
    clearInterval(pollTimer)
    pollTimer = null
  }
  if (addon && installed) {
    addon.uninstall()
    installed = false
  }
}
