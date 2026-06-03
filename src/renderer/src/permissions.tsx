import React, { useEffect, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { Icon } from './icons'
import './theme'
import './permissions.css'
import permArt from './assets/illustrations/perm-accessibility.svg'

function Permissions(): React.JSX.Element {
  const [mic, setMic] = useState(false)
  const [ax, setAx] = useState(false)

  useEffect(() => {
    const poll = (): void => {
      window.murmur.perms.status().then((s) => { setMic(s.mic); setAx(s.ax) })
    }
    poll()
    const t = setInterval(poll, 1500)
    return () => clearInterval(t)
  }, [])

  return (
    <div className="perm-win">
      <div className="perm-art"><img src={permArt} width={190} height={190} alt="" /></div>
      <div className="perm-body">
        <div>
          <div className="perm-title">Permissions Help</div>
          <div className="dim" style={{ font: 'var(--text-body)', color: 'var(--text-secondary)', marginTop: 6 }}>
            Murmur needs two macOS permissions. Grant both to dictate anywhere.
          </div>
        </div>

        <div>
          <div className="perm-item">
            <span className="perm-ico"><Icon name="mic" size={19} /></span>
            <span>
              <div className="perm-it-name">Microphone</div>
              <div className="perm-it-sub">So Murmur can hear you.</div>
            </span>
            <span className="perm-status">
              {mic
                ? <span className="tag-pasted"><Icon name="check" size={13} /> Granted</span>
                : <button className="btn btn-secondary btn-sm" onClick={() => window.murmur.perms.requestMic().then(setMic)}>Allow</button>}
            </span>
          </div>
          <div className="perm-item">
            <span className="perm-ico"><Icon name="shield" size={19} /></span>
            <span>
              <div className="perm-it-name">Accessibility</div>
              <div className="perm-it-sub">Detects the global hotkey and pastes text.</div>
            </span>
            <span className="perm-status">
              {ax
                ? <span className="tag-pasted"><Icon name="check" size={13} /> Granted</span>
                : <button className="btn btn-primary btn-sm" onClick={() => window.murmur.perms.requestAx()}>Open settings</button>}
            </span>
          </div>
        </div>

        {!ax && (
          <div className="banner banner-error">
            <Icon name="alert" size={18} className="banner-icon" /> Accessibility is off — the hotkey and paste won't work until you enable Murmur.
          </div>
        )}

        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 'auto' }}>
          <button className="btn btn-primary" onClick={() => window.murmur.closeWindow()}>Done</button>
        </div>
      </div>
    </div>
  )
}

createRoot(document.getElementById('root')!).render(<Permissions />)
