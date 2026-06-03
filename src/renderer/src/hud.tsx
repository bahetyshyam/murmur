import React, { useEffect, useState } from 'react'
import { createRoot } from 'react-dom/client'
import './theme'
import './hud.css'

// Bridge exposed by src/preload/hud.ts (declared inline — renderer and preload
// are separate TS projects, so we don't import across the boundary).
interface HudApi {
  onState(cb: (state: string) => void): void
  onLevel(cb: (level: number) => void): void
}
declare global {
  interface Window {
    hud: HudApi
  }
}

type Mode = 'idle' | 'recording' | 'transcribing' | 'error'

// Center-weighted bar profile so the meter reads as a little waveform.
const BAR_WEIGHTS = [0.45, 0.68, 0.88, 1, 0.88, 0.68, 0.45]

function Hud(): React.JSX.Element | null {
  const [mode, setMode] = useState<Mode>('idle')
  const [level, setLevel] = useState(0)

  useEffect(() => {
    window.hud.onState((s) => setMode(s as Mode))
    window.hud.onLevel((l) => setLevel(l))
  }, [])

  if (mode !== 'recording' && mode !== 'transcribing') return null

  return (
    <div className="hud-wrap">
      <div className="hud">
        {mode === 'recording' ? (
          <>
            <span className="rec-dot" />
            <Bars level={level} />
          </>
        ) : (
          <>
            <span className="spinner" />
            <span>Transcribing…</span>
          </>
        )}
      </div>
    </div>
  )
}

function Bars({ level }: { level: number }): React.JSX.Element {
  const v = Math.max(0, Math.min(1, level * 1.6)) // light visual boost
  return (
    <span className="bars">
      {BAR_WEIGHTS.map((w, i) => (
        <span key={i} style={{ height: `${6 + v * 22 * w}px` }} />
      ))}
    </span>
  )
}

createRoot(document.getElementById('root')!).render(<Hud />)
