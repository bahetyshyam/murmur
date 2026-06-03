import React, { useEffect, useRef, useState } from 'react'
import { AudioRecorder, listInputDevices, type InputDevice } from './audio/recorder'
import { Icon } from './icons'
import emptyHistoryArt from './assets/illustrations/empty-history.svg'
import emptyUsageArt from './assets/illustrations/empty-usage.svg'

// Derive the config type from the typed bridge (avoids importing across the
// renderer/preload TS-project boundary).
type MurmurConfig = Awaited<ReturnType<typeof window.murmur.config.get>>

type Tab = 'general' | 'history' | 'usage'

const MODELS = [
  { id: 'gpt-4o-transcribe', label: 'GPT-4o Transcribe', note: 'Most accurate · ~$0.006/min' },
  { id: 'gpt-4o-mini-transcribe', label: 'GPT-4o mini Transcribe', note: 'Faster & cheaper · ~$0.003/min' },
  { id: 'whisper-1', label: 'Whisper v1', note: 'Legacy · ~$0.006/min' },
]
const HOTKEYS = [
  { id: 'alt_r', label: 'Right Option', sym: '⌥' },
  { id: 'alt_l', label: 'Left Option', sym: '⌥' },
  { id: 'cmd_r', label: 'Right Cmd', sym: '⌘' },
  { id: 'ctrl_r', label: 'Right Ctrl', sym: '⌃' },
  { id: 'shift_r', label: 'Right Shift', sym: '⇧' },
]
const hotkeySym = (id: string): string => HOTKEYS.find((h) => h.id === id)?.sym ?? '⌥'

export function App(): React.JSX.Element {
  const [tab, setTab] = useState<Tab>('general')
  useEffect(() => {
    window.murmur.onSetTab((t) => setTab((t === 'history' || t === 'usage' ? t : 'general') as Tab))
  }, [])

  return (
    <div className="app">
      <div className="settings-tabbar">
        <span className="tabs">
          <button className={tab === 'general' ? 'on' : ''} onClick={() => setTab('general')}>General</button>
          <button className={tab === 'history' ? 'on' : ''} onClick={() => setTab('history')}>History</button>
          <button className={tab === 'usage' ? 'on' : ''} onClick={() => setTab('usage')}>Usage</button>
        </span>
      </div>
      <div className="settings-body">
        {tab === 'general' && <General />}
        {tab === 'history' && <History />}
        {tab === 'usage' && <Usage />}
      </div>
    </div>
  )
}

function General(): React.JSX.Element {
  const [cfg, setCfg] = useState<MurmurConfig | null>(null)
  const [devices, setDevices] = useState<InputDevice[]>([])

  const [keyInput, setKeyInput] = useState('')
  const [keySaved, setKeySaved] = useState<boolean>(false)
  const [editingKey, setEditingKey] = useState(false)

  const recorderRef = useRef<AudioRecorder | null>(null)
  if (!recorderRef.current) recorderRef.current = new AudioRecorder()
  const [recording, setRecording] = useState(false)
  const [transcribing, setTranscribing] = useState(false)
  const [level, setLevel] = useState(0)
  const [transcript, setTranscript] = useState('')
  const [error, setError] = useState('')

  const refreshDevices = async (): Promise<void> => {
    try {
      setDevices(await listInputDevices())
    } catch (e) {
      setError(String(e))
    }
  }

  useEffect(() => {
    window.murmur.config.get().then(setCfg)
    window.murmur.key.status().then(setKeySaved)
    refreshDevices()
  }, [])

  const patch = (p: Partial<MurmurConfig>): void => {
    setCfg((c) => (c ? { ...c, ...p } : c))
    window.murmur.config.set(p)
  }

  const saveKey = async (): Promise<void> => {
    await window.murmur.key.set(keyInput.trim())
    setKeyInput('')
    setEditingKey(false)
    setKeySaved(await window.murmur.key.status())
  }
  const clearKey = async (): Promise<void> => {
    await window.murmur.key.clear()
    setKeyInput('')
    setEditingKey(true)
    setKeySaved(false)
  }

  const startTest = async (): Promise<void> => {
    setError('')
    setTranscript('')
    try {
      await recorderRef.current!.start(cfg?.deviceId || undefined, (l) => setLevel(l), () => {
        setError('Microphone disconnected mid-recording.')
        void stopTest()
      })
      setRecording(true)
    } catch (e) {
      setError(String(e))
    }
  }
  const stopTest = async (): Promise<void> => {
    try {
      const r = await recorderRef.current!.stop(300)
      setRecording(false)
      setLevel(0)
      setTranscribing(true)
      const outcome = await window.murmur.transcribe(r.wav, { model: cfg?.model ?? MODELS[0].id })
      setTranscribing(false)
      if (outcome.ok) setTranscript(outcome.text || '(no speech detected)')
      else setError(outcome.error.userMessage)
    } catch (e) {
      setError(String(e))
      setRecording(false)
      setTranscribing(false)
    }
  }

  if (!cfg) return <div className="dim fade">Loading…</div>
  const modelNote = MODELS.find((m) => m.id === cfg.model)?.note ?? ''
  const showSavedKey = keySaved && !editingKey

  return (
    <div className="fade" style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <div className="section-head">OpenAI</div>
      <div className="card set-card">
        <div className="set-row">
          <div className="set-label">
            <div className="set-name">API key</div>
            <div className="set-help">Stored in the macOS Keychain. Never leaves your device except to OpenAI.</div>
          </div>
          <div className="set-control" style={{ flexDirection: 'column', alignItems: 'flex-end', gap: 8 }}>
            <input
              className="field field-mono"
              type="password"
              placeholder="sk-…"
              value={showSavedKey ? '••••••••••••••••' : keyInput}
              onChange={(e) => { setKeyInput(e.target.value); setEditingKey(true) }}
              onFocus={() => { if (showSavedKey) { setEditingKey(true); setKeyInput('') } }}
              style={{ width: 220 }}
            />
            <div className="set-control">
              {showSavedKey && <span className="tag-pasted"><Icon name="check" size={13} /> saved</span>}
              <button className="btn btn-primary btn-sm" disabled={!keyInput.trim()} onClick={saveKey}>Save</button>
              <button className="btn btn-ghost btn-sm" disabled={!keySaved} onClick={clearKey}>Clear</button>
            </div>
          </div>
        </div>
        <div className="set-row">
          <div className="set-label">
            <div className="set-name">Model</div>
            <div className="set-help">{modelNote}</div>
          </div>
          <div className="set-control">
            <span className="select-wrap">
              <select className="field" value={cfg.model} onChange={(e) => patch({ model: e.target.value })}>
                {MODELS.map((m) => <option key={m.id} value={m.id}>{m.label}</option>)}
              </select>
            </span>
          </div>
        </div>
      </div>

      <div className="section-head">Input</div>
      <div className="card set-card">
        <div className="set-row">
          <div className="set-label"><div className="set-name">Microphone</div></div>
          <div className="set-control">
            <span className="select-wrap">
              <select className="field" value={cfg.deviceId} onChange={(e) => patch({ deviceId: e.target.value })} disabled={recording}>
                <option value="">Auto-detect (system default)</option>
                {devices.map((d) => <option key={d.deviceId} value={d.deviceId}>{d.label}</option>)}
              </select>
            </span>
            <button className="icon-btn" title="Refresh devices" onClick={refreshDevices} disabled={recording}><Icon name="refresh" /></button>
          </div>
        </div>
        <div className="set-row">
          <div className="set-label">
            <div className="set-name">Record test</div>
            <div className="set-help">{recording ? 'Listening…' : transcribing ? 'Transcribing…' : 'Check your level before you dictate.'}</div>
          </div>
          <div className="set-control" style={{ flexDirection: 'column', alignItems: 'flex-end', gap: 8 }}>
            <div className="meter"><div className="meter-fill" style={{ width: `${Math.round(level * 100)}%` }} /></div>
            <button
              className={'btn btn-sm ' + (recording ? 'btn-danger' : 'btn-secondary')}
              onClick={() => (recording ? stopTest() : startTest())}
              disabled={transcribing}
            >
              {recording ? <Icon name="stop" size={13} /> : <Icon name="play" size={13} />} {recording ? 'Stop' : 'Record'}
            </button>
          </div>
        </div>
        {transcript && (
          <div className="set-row" style={{ alignItems: 'flex-start' }}>
            <div className="set-label"><div className="set-name">Result</div></div>
            <div className="set-control" style={{ maxWidth: 320 }}>
              <div className="transcript t-body">{transcript}</div>
            </div>
          </div>
        )}
        {error && (
          <div className="set-row">
            <div className="banner banner-error" style={{ width: '100%' }}><Icon name="alert" size={18} className="banner-icon" /> {error}</div>
          </div>
        )}
      </div>

      <div className="section-head">Behavior</div>
      <div className="card set-card">
        <div className="set-row">
          <div className="set-label">
            <div className="set-name">Hotkey</div>
            <div className="set-help">Tap once to start, tap again to stop.</div>
          </div>
          <div className="set-control">
            <span className="key">{hotkeySym(cfg.hotkey)}</span>
            <span className="select-wrap" style={{ width: 150 }}>
              <select className="field" value={cfg.hotkey} onChange={(e) => patch({ hotkey: e.target.value })}>
                {HOTKEYS.map((h) => <option key={h.id} value={h.id}>{h.label}</option>)}
              </select>
            </span>
          </div>
        </div>
        <div className="set-row">
          <div className="set-label">
            <div className="set-name">Paste at cursor</div>
            <div className="set-help">Insert the transcript where you're typing.</div>
          </div>
          <div className="set-control">
            <label className="switch">
              <input type="checkbox" checked={cfg.pasteAtCursor} onChange={(e) => patch({ pasteAtCursor: e.target.checked })} />
              <span className="track" /><span className="thumb" />
            </label>
          </div>
        </div>
        <div className="set-row">
          <div className="set-label"><div className="set-name">Automatically check for updates</div></div>
          <div className="set-control">
            <label className="switch">
              <input type="checkbox" checked={cfg.autoUpdate} onChange={(e) => patch({ autoUpdate: e.target.checked })} />
              <span className="track" /><span className="thumb" />
            </label>
          </div>
        </div>
      </div>
    </div>
  )
}

function relTime(epochSeconds: number): string {
  const diff = Date.now() / 1000 - epochSeconds
  if (diff < 60) return 'just now'
  if (diff < 3600) return `${Math.floor(diff / 60)} min ago`
  if (diff < 86400) return `${Math.floor(diff / 3600)} hr ago`
  return new Date(epochSeconds * 1000).toLocaleDateString()
}

function History(): React.JSX.Element {
  const [rows, setRows] = useState<Awaited<ReturnType<typeof window.murmur.history.recent>>>([])
  const load = async (): Promise<void> => setRows(await window.murmur.history.recent())
  useEffect(() => { load() }, [])

  const del = async (id: number): Promise<void> => { await window.murmur.history.delete(id); load() }
  const copy = (text: string): void => { void navigator.clipboard?.writeText(text).catch(() => {}) }

  if (rows.length === 0) {
    return (
      <div className="empty fade">
        <img className="empty-art" src={emptyHistoryArt} alt="" />
        <div className="empty-title">No transcripts yet</div>
        <div className="empty-sub">Tap your hotkey anywhere and start talking — your transcripts show up here.</div>
      </div>
    )
  }
  return (
    <div className="fade" style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      {rows.map((r) => (
        <div className="list-row" key={r.id}>
          <div className="list-meta">
            <span className="badge">{r.model}</span>
            <span className="list-time">{relTime(r.timestamp)}</span>
            {r.pasted && <span className="tag-pasted"><Icon name="check" size={13} /> pasted</span>}
            <span style={{ marginLeft: 'auto', display: 'flex', gap: 2 }}>
              {!r.error && <button className="icon-btn" style={{ width: 26, height: 26 }} title="Copy" onClick={() => copy(r.text)}><Icon name="copy" size={14} /></button>}
              <button className="icon-btn" style={{ width: 26, height: 26 }} title="Delete" onClick={() => del(r.id)}><Icon name="x" size={14} /></button>
            </span>
          </div>
          <div className={'list-body' + (r.error ? ' is-error' : '')}>{r.error ?? r.text}</div>
        </div>
      ))}
    </div>
  )
}

function Usage(): React.JSX.Element {
  const [rows, setRows] = useState<Awaited<ReturnType<typeof window.murmur.history.usage>>>([])
  useEffect(() => { window.murmur.history.usage().then(setRows) }, [])

  if (rows.length === 0) {
    return (
      <div className="empty fade">
        <img className="empty-art" src={emptyUsageArt} alt="" />
        <div className="empty-title">No usage yet</div>
        <div className="empty-sub">Once you start dictating, your estimated spend appears here.</div>
      </div>
    )
  }
  const total = rows.reduce((s, r) => s + r.cost, 0)
  return (
    <div className="fade" style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div className="card" style={{ padding: '4px 16px' }}>
        <table className="usage-table">
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
            <tr className="total"><td>Total</td><td></td><td></td><td>${total.toFixed(4)}</td></tr>
          </tbody>
        </table>
      </div>
      <div className="dim" style={{ font: 'var(--text-caption)', padding: '0 2px' }}>
        Estimated from audio duration × OpenAI's per-minute pricing. Covers your retained history.
      </div>
    </div>
  )
}
