import { useEffect, useRef, useState } from 'react'
import { AudioRecorder, listInputDevices, type InputDevice, type RecordResult } from './audio/recorder'

const MODELS = ['gpt-4o-transcribe', 'gpt-4o-mini-transcribe', 'whisper-1']
type Tab = 'main' | 'history' | 'usage'

// Phase B/C/F test harness in the Settings window: capture + key + transcription
// (main tab), transcript history, and usage/cost. The real design-system UI
// arrives in Phase H.
export function App(): JSX.Element {
  const [tab, setTab] = useState<Tab>('main')

  useEffect(() => {
    window.murmur.onSetTab((t) => setTab(t as Tab))
  }, [])

  return (
    <div className="app">
      <nav className="tabs">
        <button className={tab === 'main' ? 'on' : ''} onClick={() => setTab('main')}>Test</button>
        <button className={tab === 'history' ? 'on' : ''} onClick={() => setTab('history')}>History</button>
        <button className={tab === 'usage' ? 'on' : ''} onClick={() => setTab('usage')}>Usage</button>
      </nav>
      {tab === 'main' && <MainTab />}
      {tab === 'history' && <HistoryTab />}
      {tab === 'usage' && <UsageTab />}
    </div>
  )
}

function MainTab(): JSX.Element {
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
      await recorderRef.current!.start(deviceId || undefined, (l) => setLevel(l), () => {
        setError('Microphone disconnected mid-recording.')
        stop()
      })
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
      setTranscribing(true)
      const outcome = await window.murmur.transcribe(r.wav, { model })
      setTranscribing(false)
      if (outcome.ok) setTranscript(outcome.text || '(empty transcription)')
      else setError(outcome.error.userMessage)
    } catch (e) {
      setError(String(e))
      setRecording(false)
      setTranscribing(false)
    }
  }

  return (
    <>
      <section className="card">
        <div className="card-title">OpenAI API key {keyStatus === true && <span className="ok">✓ saved</span>}</div>
        <div className="row">
          <input type="password" placeholder="sk-…" value={keyInput} onChange={(e) => setKeyInput(e.target.value)} style={{ flex: 1 }} />
          <button onClick={saveKey} disabled={!keyInput.trim()}>Save</button>
          <button onClick={clearKey} disabled={keyStatus !== true}>Clear</button>
        </div>
      </section>

      <label className="row">
        <span>Microphone</span>
        <select value={deviceId} onChange={(e) => setDeviceId(e.target.value)} disabled={recording}>
          <option value="">Auto-detect (system default)</option>
          {devices.map((d) => <option key={d.deviceId} value={d.deviceId}>{d.label}</option>)}
        </select>
      </label>

      <label className="row">
        <span>Model</span>
        <select value={model} onChange={(e) => setModel(e.target.value)} disabled={recording}>
          {MODELS.map((m) => <option key={m} value={m}>{m}</option>)}
        </select>
      </label>

      <div className="meter"><div className="meter-fill" style={{ width: `${Math.round(level * 100)}%` }} /></div>

      <div className="row">
        {!recording ? <button onClick={start}>● Record</button> : <button onClick={stop}>■ Stop</button>}
        <button onClick={refreshDevices} disabled={recording}>Refresh devices</button>
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
          {result.durationS.toFixed(2)}s · {result.frames.toLocaleString()} samples @ {result.sampleRate} Hz
        </div>
      )}
      {error && <div className="error">{error}</div>}
    </>
  )
}

function relTime(epochSeconds: number): string {
  return new Date(epochSeconds * 1000).toLocaleString()
}

function HistoryTab(): JSX.Element {
  const [rows, setRows] = useState<Awaited<ReturnType<typeof window.murmur.history.recent>>>([])
  const load = async (): Promise<void> => setRows(await window.murmur.history.recent())
  useEffect(() => {
    load()
  }, [])
  const del = async (id: number): Promise<void> => {
    await window.murmur.history.delete(id)
    load()
  }
  if (rows.length === 0) return <div className="muted">No transcripts yet.</div>
  return (
    <div className="list">
      {rows.map((r) => (
        <div className="list-row" key={r.id}>
          <div className="list-meta">
            <span className="badge">{r.model}</span>
            <span className="muted">{relTime(r.timestamp)}</span>
            {r.pasted && <span className="ok">pasted</span>}
            <button className="del" onClick={() => del(r.id)}>✕</button>
          </div>
          <div className={r.error ? 'error' : 'transcript'}>{r.error ?? r.text}</div>
        </div>
      ))}
    </div>
  )
}

function UsageTab(): JSX.Element {
  const [rows, setRows] = useState<Awaited<ReturnType<typeof window.murmur.history.usage>>>([])
  useEffect(() => {
    window.murmur.history.usage().then(setRows)
  }, [])
  const total = rows.reduce((sum, r) => sum + r.cost, 0)
  return (
    <section className="card">
      <div className="card-title">Estimated spend</div>
      <div className="muted">From audio duration × OpenAI's per-minute pricing. Covers your retained history.</div>
      <div className="usage-total">Total <b>${total.toFixed(4)}</b></div>
      {rows.length === 0 ? (
        <div className="muted">No usage yet.</div>
      ) : (
        <table className="usage">
          <thead><tr><th>Model</th><th>Count</th><th>Minutes</th><th>Cost</th></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.model}>
                <td>{r.model}</td>
                <td>{r.count}</td>
                <td>{(r.totalSeconds / 60).toFixed(1)}</td>
                <td>${r.cost.toFixed(4)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  )
}
