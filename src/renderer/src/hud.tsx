import React, { useEffect, useState } from 'react'
import { createRoot } from 'react-dom/client'

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

  // Main hides the window when idle/error, but render nothing too (belt + braces).
  if (mode !== 'recording' && mode !== 'transcribing') return null

  return (
    <div style={WRAP}>
      <style>{KEYFRAMES}</style>
      <div style={PILL}>{mode === 'recording' ? <Bars level={level} /> : <Dots />}</div>
    </div>
  )
}

function Bars({ level }: { level: number }): React.JSX.Element {
  const v = Math.max(0, Math.min(1, level * 1.6)) // light visual boost
  return (
    <div style={ROW}>
      {BAR_WEIGHTS.map((w, i) => (
        <span key={i} style={{ ...BAR, height: `${5 + v * 26 * w}px` }} />
      ))}
    </div>
  )
}

function Dots(): React.JSX.Element {
  return (
    <div style={ROW}>
      {[0, 1, 2].map((i) => (
        <span key={i} style={{ ...DOT, animationDelay: `${i * 0.18}s` }} />
      ))}
    </div>
  )
}

const WRAP: React.CSSProperties = {
  height: '100%',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
}
const PILL: React.CSSProperties = {
  minWidth: 96,
  height: 44,
  padding: '0 18px',
  borderRadius: 22,
  background: 'rgba(28, 28, 30, 0.92)',
  boxShadow: '0 6px 20px rgba(0, 0, 0, 0.35)',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  WebkitBackdropFilter: 'blur(12px)',
}
const ROW: React.CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  gap: 4,
  height: 32,
}
const BAR: React.CSSProperties = {
  width: 4,
  borderRadius: 2,
  background: '#f2f2f7',
  transition: 'height 90ms ease-out',
}
const DOT: React.CSSProperties = {
  width: 8,
  height: 8,
  borderRadius: '50%',
  background: '#f2f2f7',
  animation: 'murmurPulse 1.1s ease-in-out infinite',
}
const KEYFRAMES = `@keyframes murmurPulse {
  0%, 100% { opacity: 0.3; transform: scale(0.75); }
  50% { opacity: 1; transform: scale(1); }
}`

createRoot(document.getElementById('root')!).render(<Hud />)
