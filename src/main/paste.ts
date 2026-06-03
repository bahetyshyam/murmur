import { clipboard } from 'electron'
import { nativePaste } from './hotkey'

// Paste text at the cursor, faithful to the Swift Paster: snapshot the
// clipboard → write the text → synthesize ⌘V → restore the snapshot 250 ms
// later (giving the focused app time to read it). On paste failure the text is
// LEFT on the clipboard (no restore) so the user can paste manually.
//
// Parity exception (documented): Electron's clipboard only exposes
// text/html/rtf/image, whereas the Swift Paster snapshotted ALL NSPasteboard
// types. Binary/file/custom-UTI clipboard contents are therefore not preserved
// in v1.
interface ClipboardSnapshot {
  text: string
  html: string
  rtf: string
  image: Electron.NativeImage
}

function snapshot(): ClipboardSnapshot {
  return {
    text: clipboard.readText(),
    html: clipboard.readHTML(),
    rtf: clipboard.readRTF(),
    image: clipboard.readImage(),
  }
}

function restore(s: ClipboardSnapshot): void {
  const data: Electron.Data = {}
  if (s.text) data.text = s.text
  if (s.html) data.html = s.html
  if (s.rtf) data.rtf = s.rtf
  if (!s.image.isEmpty()) data.image = s.image
  if (Object.keys(data).length === 0) clipboard.clear()
  else clipboard.write(data)
}

/** Returns true if the synthetic ⌘V was posted. */
export function pasteText(text: string, restoreClipboard = true): boolean {
  const snap = restoreClipboard ? snapshot() : null
  clipboard.writeText(text)
  const ok = nativePaste()
  if (!ok) return false // leave text on the clipboard for manual paste
  if (snap) setTimeout(() => restore(snap), 250)
  return true
}
