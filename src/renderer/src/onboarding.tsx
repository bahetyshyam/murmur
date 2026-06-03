import React, { useEffect, useRef, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { Icon } from './icons'
import './theme'
import './onboarding.css'
import obWelcome from './assets/illustrations/ob-welcome.svg'
import obApikey from './assets/illustrations/ob-apikey.svg'
import obMic from './assets/illustrations/ob-mic.svg'
import obAx from './assets/illustrations/ob-accessibility.svg'
import obHotkey from './assets/illustrations/ob-hotkey.svg'
import obTryit from './assets/illustrations/ob-tryit.svg'
import obAllset from './assets/illustrations/ob-allset.svg'
import appIcon from './assets/murmur-app-icon.svg'

const HOTKEYS = [
  { id: 'alt_r', label: 'Right Option', sym: '⌥' },
  { id: 'alt_l', label: 'Left Option', sym: '⌥' },
  { id: 'cmd_r', label: 'Right Cmd', sym: '⌘' },
  { id: 'ctrl_r', label: 'Right Ctrl', sym: '⌃' },
  { id: 'shift_r', label: 'Right Shift', sym: '⇧' },
]
const sym = (id: string): string => HOTKEYS.find((h) => h.id === id)?.sym ?? '⌥'

type StepId = 'welcome' | 'apikey' | 'mic' | 'ax' | 'hotkey' | 'tryit' | 'done'
const STEPS: { id: StepId; art: string; kicker: string; title: string; cta: string }[] = [
  { id: 'welcome', art: obWelcome, kicker: 'Welcome', title: 'Talk. It types.', cta: 'Get started' },
  { id: 'apikey', art: obApikey, kicker: 'OpenAI API key', title: 'Connect your key', cta: 'Continue' },
  { id: 'mic', art: obMic, kicker: 'Microphone access', title: 'Let Murmur hear you', cta: 'Continue' },
  { id: 'ax', art: obAx, kicker: 'Accessibility access', title: 'Hotkey & paste', cta: 'Continue' },
  { id: 'hotkey', art: obHotkey, kicker: 'Your hotkey', title: 'Pick your trigger', cta: 'Continue' },
  { id: 'tryit', art: obTryit, kicker: 'Try it', title: 'Your first dictation', cta: 'Continue' },
  { id: 'done', art: obAllset, kicker: 'All set', title: "You're ready", cta: 'Open Murmur' },
]

function Onboarding(): React.JSX.Element {
  const [i, setI] = useState(0)
  const [keySaved, setKeySaved] = useState(false)
  const [mic, setMic] = useState(false)
  const [ax, setAx] = useState(false)
  const [hotkey, setHotkey] = useState('alt_r')
  const [tried, setTried] = useState(false)

  useEffect(() => {
    window.murmur.key.status().then(setKeySaved)
    window.murmur.config.get().then((c) => setHotkey(c.hotkey))
    const poll = (): void => {
      window.murmur.perms.status().then((s) => { setMic(s.mic); setAx(s.ax) })
    }
    poll()
    const t = setInterval(poll, 1500)
    return () => clearInterval(t)
  }, [])

  const step = STEPS[i]
  const gateOk: Record<StepId, boolean> = {
    welcome: true, apikey: keySaved, mic, ax, hotkey: true, tryit: tried, done: true,
  }
  const last = i === STEPS.length - 1
  const next = (): void => setI((n) => Math.min(n + 1, STEPS.length - 1))
  const back = (): void => setI((n) => Math.max(n - 1, 0))

  const body = ((): React.JSX.Element => {
    switch (step.id) {
      case 'welcome':
        return (
          <p className="muted" style={{ font: 'var(--text-body)', lineHeight: 1.6, margin: 0 }}>
            Tap your hotkey anywhere on your Mac and start talking. Tap again and Murmur transcribes your
            voice and pastes it right at the cursor — in any app. The dot lights up while you speak.
          </p>
        )
      case 'apikey':
        return <ApiKey saved={keySaved} onSaved={() => setKeySaved(true)} />
      case 'mic':
        return (
          <Permission
            granted={mic}
            label="Allow microphone"
            help="Murmur asks macOS for microphone access. Required to hear you."
            onGrant={async () => setMic(await window.murmur.perms.requestMic())}
          />
        )
      case 'ax':
        return (
          <Permission
            granted={ax}
            label="Open Accessibility settings"
            help="Accessibility lets Murmur detect the global hotkey and paste text into other apps. Toggle Murmur on, then come back."
            onGrant={() => window.murmur.perms.requestAx()}
          />
        )
      case 'hotkey':
        return (
          <HotkeyPick
            value={hotkey}
            onChange={(h) => { setHotkey(h); window.murmur.config.set({ hotkey: h }) }}
          />
        )
      case 'tryit':
        return <TryIt hotkey={hotkey} tried={tried} onTried={() => setTried(true)} />
      case 'done':
        return (
          <div className="col" style={{ gap: 12 }}>
            <p className="muted" style={{ font: 'var(--text-body)', margin: 0, lineHeight: 1.6 }}>
              Murmur lives in your menu bar and Dock. Tap your hotkey anywhere to dictate.
            </p>
            <ul className="dim" style={{ font: 'var(--text-caption)', margin: 0, paddingLeft: 18, lineHeight: 1.8 }}>
              <li>Reach Settings from the Dock icon or the menu bar (⌘,)</li>
              <li>Your history is private and stored on this Mac</li>
              <li>Speak for at least a second for best accuracy</li>
            </ul>
          </div>
        )
    }
  })()

  return (
    <div className="ob-grid">
      <div className="ob-art">
        {step.id === 'welcome' ? (
          <>
            <img src={appIcon} width={124} height={124} style={{ borderRadius: 28, boxShadow: 'var(--shadow-2)' }} alt="Murmur" />
            <span className="ob-wordmark">Murmur</span>
          </>
        ) : (
          <img src={step.art} width={190} height={190} alt="" />
        )}
      </div>

      <div className="ob-content">
        <div className="ob-head">
          <span className="ob-kicker">{step.kicker}</span>
          <h1 className="t-title" style={{ margin: 0 }}>{step.title}</h1>
        </div>
        <div key={step.id} className="ob-body ob-fade">{body}</div>
        <div className="ob-footer">
          <div className="rail-dots" style={{ justifyContent: 'center' }}>
            {STEPS.map((_, n) => <i key={n} className={n < i ? 'done' : n === i ? 'active' : ''} />)}
          </div>
          <div className="ob-nav">
            <button className="btn btn-ghost btn-sm" onClick={back} style={{ visibility: i === 0 ? 'hidden' : 'visible' }}>Back</button>
            <button
              className="btn btn-primary"
              disabled={!gateOk[step.id]}
              onClick={() => (last ? window.murmur.onboarding.finish() : next())}
            >
              {step.cta}{!last && <Icon name="arrow" size={15} />}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

function ApiKey({ saved, onSaved }: { saved: boolean; onSaved: () => void }): React.JSX.Element {
  const [val, setVal] = useState('')
  const save = async (): Promise<void> => { await window.murmur.key.set(val.trim()); setVal(''); onSaved() }
  return (
    <div className="col" style={{ gap: 16 }}>
      <input className="field field-mono" type="password" placeholder="sk-…" value={val}
        onChange={(e) => setVal(e.target.value)} disabled={saved} />
      <div className="row" style={{ gap: 12 }}>
        {!saved
          ? <button className="btn btn-primary btn-sm" disabled={!val.trim()} onClick={save}>Save key</button>
          : <span className="tag-pasted"><Icon name="check" size={14} /> Saved to Keychain</span>}
      </div>
      <p className="dim" style={{ font: 'var(--text-caption)', margin: 0, lineHeight: 1.55 }}>
        Stored securely in the macOS Keychain. It never leaves your device except to OpenAI.
      </p>
    </div>
  )
}

function Permission({ granted, onGrant, label, help }: {
  granted: boolean; onGrant: () => void; label: string; help: string
}): React.JSX.Element {
  return (
    <div className="col" style={{ gap: 16 }}>
      {!granted
        ? <button className="btn btn-primary btn-sm" onClick={onGrant}>{label}</button>
        : <span className="tag-pasted"><Icon name="check" size={14} /> Access granted</span>}
      <p className="dim" style={{ font: 'var(--text-caption)', margin: 0, lineHeight: 1.55 }}>{help}</p>
    </div>
  )
}

function HotkeyPick({ value, onChange }: { value: string; onChange: (id: string) => void }): React.JSX.Element {
  return (
    <div className="col" style={{ gap: 18 }}>
      <div className="row" style={{ gap: 12 }}>
        <span className="key key-lg">{sym(value)}</span>
        <span className="muted" style={{ font: 'var(--text-body-strong)' }}>
          {HOTKEYS.find((h) => h.id === value)?.label}
        </span>
      </div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
        {HOTKEYS.map((h) => {
          const on = h.id === value
          return (
            <button key={h.id} onClick={() => onChange(h.id)}
              className={'btn btn-sm ' + (on ? 'btn-secondary' : 'btn-ghost')}
              style={on ? { borderColor: 'var(--accent)', color: 'var(--accent-text)' } : {}}>
              <span style={{ fontFamily: 'var(--font-mono)' }}>{h.sym}</span> {h.label}
            </button>
          )
        })}
      </div>
    </div>
  )
}

function TryIt({ hotkey, tried, onTried }: { hotkey: string; tried: boolean; onTried: () => void }): React.JSX.Element {
  const ref = useRef<HTMLTextAreaElement | null>(null)
  return (
    <div className="col" style={{ gap: 16 }}>
      <p className="dim" style={{ font: 'var(--text-caption)', margin: 0, lineHeight: 1.55 }}>
        Click into the box below, tap <span className="key" style={{ minWidth: 18, height: 18, fontSize: 12, boxShadow: 'none' }}>{sym(hotkey)}</span>, say a few words, then tap again. Your words paste right here.
      </p>
      <textarea
        ref={ref}
        className="try-field"
        rows={2}
        placeholder="Your dictation appears here…"
        onChange={(e) => { if (e.target.value.trim()) onTried() }}
      />
      {tried && <span className="tag-pasted"><Icon name="check" size={14} /> Pasted at cursor</span>}
    </div>
  )
}

createRoot(document.getElementById('root')!).render(<Onboarding />)
