import { useEffect, useRef, useState } from 'react'
import { AudioRecorder, listInputDevices, type InputDevice, type RecordResult } from './audio/recorder'

// Phase B test harness: device picker + record/stop + live level meter + WAV
// info, in the Settings window. Lets us verify capture/format end-to-end before
// wiring it to the real state machine + transcription (Phase C).
export function App(): JSX.Element {
  const recorderRef = useRef<AudioRecorder | null>(null)
  if (!recorderRef.current) recorderRef.current = new AudioRecorder()

  const [devices, setDevices] = useState<InputDevice[]>([])
  const [deviceId, setDeviceId] = useState<string>('')
  const [recording, setRecording] = useState(false)
  const [level, setLevel] = useState(0)
  const [result, setResult] = useState<RecordResult | null>(null)
  const [error, setError] = useState<string>('')
  const [saved, setSaved] = useState<string>('')

  const refreshDevices = async (): Promise<void> => {
    try {
      setDevices(await listInputDevices())
    } catch (e) {
      setError(String(e))
    }
  }

  useEffect(() => {
    refreshDevices()
  }, [])

  const start = async (): Promise<void> => {
    setError('')
    setResult(null)
    setSaved('')
    try {
      await recorderRef.current!.start(
        deviceId || undefined,
        (l) => setLevel(l),
        () => {
          setError('Microphone disconnected mid-recording.')
          stop()
        },
      )
      setRecording(true)
      // Labels populate after the first grant — refresh the picker.
      refreshDevices()
    } catch (e) {
      setError(String(e))
    }
  }

  const stop = async (): Promise<void> => {
    try {
      const r = await recorderRef.current!.stop(300)
      setResult(r)
      setRecording(false)
      setLevel(0)
    } catch (e) {
      setError(String(e))
      setRecording(false)
    }
  }

  const saveWav = async (): Promise<void> => {
    if (!result) return
    const path = await window.murmur.debugSaveWav(result.wav)
    setSaved(path)
  }

  return (
    <div className="app">
      <h1>Murmur — Phase B</h1>
      <p className="subtitle">Audio capture · device picker · 16 kHz WAV</p>

      <label className="row">
        <span>Microphone</span>
        <select value={deviceId} onChange={(e) => setDeviceId(e.target.value)} disabled={recording}>
          <option value="">Auto-detect (system default)</option>
          {devices.map((d) => (
            <option key={d.deviceId} value={d.deviceId}>
              {d.label}
            </option>
          ))}
        </select>
      </label>

      <div className="meter">
        <div className="meter-fill" style={{ width: `${Math.round(level * 100)}%` }} />
      </div>

      <div className="row">
        {!recording ? (
          <button onClick={start}>● Record</button>
        ) : (
          <button onClick={stop}>■ Stop</button>
        )}
        <button onClick={refreshDevices} disabled={recording}>
          Refresh devices
        </button>
      </div>

      {result && (
        <div className="result">
          <div>
            duration <b>{result.durationS.toFixed(2)}s</b> · {result.frames.toLocaleString()} samples @{' '}
            {result.sampleRate} Hz · WAV <b>{result.wav.byteLength.toLocaleString()}</b> bytes
          </div>
          <button onClick={saveWav}>Save WAV to /tmp</button>
          {saved && <div className="muted">saved → {saved}</div>}
        </div>
      )}

      {error && <div className="error">{error}</div>}
    </div>
  )
}
