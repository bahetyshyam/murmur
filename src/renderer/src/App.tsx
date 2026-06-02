import { useEffect, useRef, useState } from 'react'
import { AudioRecorder, listInputDevices, type InputDevice, type RecordResult } from './audio/recorder'

const MODELS = ['gpt-4o-transcribe', 'gpt-4o-mini-transcribe', 'whisper-1']

// Phase B+C test harness: mic picker + record/stop + live meter (B), and API
// key management + record→transcribe→text (C), in the Settings window. The real
// design-system Settings UI arrives in Phase H.
export function App(): JSX.Element {
  const recorderRef = useRef<AudioRecorder | null>(null)
  if (!recorderRef.current) recorderRef.current = new AudioRecorder()

  const [devices, setDevices] = useState<InputDevice[]>([])
  const [deviceId, setDeviceId] = useState('')
  const [model, setModel] = useState(MODELS[0])
  const [recording, setRecording] = useState(false)
  const [level, setLevel] = useState(0)
  const [result, setResult] = useState<RecordResult | null>(null)
  const [error, setError] = useState('')

  const [keyInput, setKeyInput] = useState('')
  const [keyStatus, setKeyStatus] = useState<boolean | null>(null)
  const [transcript, setTranscript] = useState('')
  const [transcribing, setTranscribing] = useState(false)

  const refreshDevices = async (): Promise<void> => {
    try {
      setDevices(await listInputDevices())
    } catch (e) {
      setError(String(e))
    }
  }
  const refreshKey = async (): Promise<void> => setKeyStatus(await window.murmur.key.status())

  useEffect(() => {
    refreshDevices()
    refreshKey()
  }, [])

  const saveKey = async (): Promise<void> => {
    try {
      await window.murmur.key.set(keyInput)
      setKeyInput('')
      await refreshKey()
    } catch (e) {
      setError(String(e))
    }
  }
  const clearKey = async (): Promise<void> => {
    await window.murmur.key.clear()
    await refreshKey()
  }

  const start = async (): Promise<void> => {
    setError('')
    setResult(null)
    setTranscript('')
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
      // Full pipeline test: record → transcribe → text.
      setTranscribing(true)
      const outcome = await window.murmur.transcribe(r.wav, { model })
      setTranscribing(false)
      if (outcome.ok) {
        setTranscript(outcome.text || '(empty transcription)')
      } else {
        setError(outcome.error.userMessage)
      }
    } catch (e) {
      setError(String(e))
      setRecording(false)
      setTranscribing(false)
    }
  }

  return (
    <div className="app">
      <h1>Murmur — Phase C</h1>
      <p className="subtitle">Audio capture · API key · OpenAI transcription</p>

      <section className="card">
        <div className="card-title">OpenAI API key {keyStatus === true && <span className="ok">✓ saved</span>}</div>
        <div className="row">
          <input
            type="password"
            placeholder="sk-…"
            value={keyInput}
            onChange={(e) => setKeyInput(e.target.value)}
            style={{ flex: 1 }}
          />
          <button onClick={saveKey} disabled={!keyInput.trim()}>
            Save
          </button>
          <button onClick={clearKey} disabled={keyStatus !== true}>
            Clear
          </button>
        </div>
      </section>

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

      <label className="row">
        <span>Model</span>
        <select value={model} onChange={(e) => setModel(e.target.value)} disabled={recording}>
          {MODELS.map((m) => (
            <option key={m} value={m}>
              {m}
            </option>
          ))}
        </select>
      </label>

      <div className="meter">
        <div className="meter-fill" style={{ width: `${Math.round(level * 100)}%` }} />
      </div>

      <div className="row">
        {!recording ? <button onClick={start}>● Record</button> : <button onClick={stop}>■ Stop</button>}
        <button onClick={refreshDevices} disabled={recording}>
          Refresh devices
        </button>
      </div>

      {transcribing && <div className="muted">Transcribing…</div>}

      {transcript && (
        <section className="card">
          <div className="card-title">Transcript</div>
          <div className="transcript">{transcript}</div>
        </section>
      )}

      {result && (
        <div className="muted">
          {result.durationS.toFixed(2)}s · {result.frames.toLocaleString()} samples @ {result.sampleRate} Hz · WAV{' '}
          {result.wav.byteLength.toLocaleString()} bytes
        </div>
      )}

      {error && <div className="error">{error}</div>}
    </div>
  )
}
