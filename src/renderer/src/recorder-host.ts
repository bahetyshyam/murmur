import { AudioRecorder } from './audio/recorder'

// Shape of the bridge exposed by src/preload/recorder-host.ts (declared inline
// — the renderer and preload live in separate TS projects, so we don't import
// across the boundary).
interface RecHostApi {
  onStart(cb: (deviceId: string) => void): void
  onStop(cb: () => void): void
  sendReady(): void
  sendStarted(payload: { ok: boolean; error?: string }): void
  sendLevel(level: number): void
  sendResult(payload: { ok: boolean; wav?: ArrayBuffer; durationS?: number; error?: string }): void
}

declare global {
  interface Window {
    recHost: RecHostApi
  }
}

// Headless capture host: owns the AudioRecorder for the app's lifetime (a
// menubar app has no always-open window, so getUserMedia lives here). Main
// sends rec:start/rec:stop; we ack start, stream levels, and return the WAV.
const recorder = new AudioRecorder()
let active = false

window.recHost.onStart(async (deviceId: string) => {
  if (active) {
    window.recHost.sendStarted({ ok: true })
    return
  }
  try {
    await recorder.start(
      deviceId || undefined,
      (level) => window.recHost.sendLevel(level),
      () => {
        // Mic disconnected mid-recording. v1: log; the next stop() still
        // returns the audio buffered so far. (Robust abort is a later refinement.)
        console.warn('[recorder-host] microphone disconnected mid-recording')
      },
    )
    active = true
    window.recHost.sendStarted({ ok: true })
  } catch (e) {
    active = false
    window.recHost.sendStarted({ ok: false, error: String(e) })
  }
})

window.recHost.onStop(async () => {
  if (!active) {
    window.recHost.sendResult({ ok: false, error: 'not recording' })
    return
  }
  active = false
  try {
    const r = await recorder.stop(300)
    window.recHost.sendResult({ ok: true, wav: r.wav, durationS: r.durationS })
  } catch (e) {
    window.recHost.sendResult({ ok: false, error: String(e) })
  }
})

// Tell main the host is loaded and listening (so it doesn't send rec:start into
// the void before the listeners above are installed).
window.recHost.sendReady()
