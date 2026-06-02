import Database from 'better-sqlite3'
import { app } from 'electron'
import { join } from 'path'

// SQLite transcript history, faithful to the Swift HistoryStore schema (same
// file: Application Support/Murmur/history.sqlite3 — which is exactly Electron's
// userData/history.sqlite3 for productName "Murmur", so prior history carries
// over). `ts` is Unix epoch seconds.
let db: Database.Database | null = null
let dbFailed = false

// Non-fatal: if SQLite can't open (e.g. the native module fails to load), we
// log once and run without history — dictation must never break because of it
// (parity with the Swift app's in-memory fallback intent).
function getDb(): Database.Database | null {
  if (db) return db
  if (dbFailed) return null
  try {
    const d = new Database(join(app.getPath('userData'), 'history.sqlite3'))
    d.pragma('journal_mode = WAL')
    d.exec(`
      CREATE TABLE IF NOT EXISTS transcripts (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        ts         REAL NOT NULL,
        text       TEXT NOT NULL,
        model      TEXT NOT NULL,
        duration_s REAL,
        pasted     INTEGER NOT NULL DEFAULT 0,
        error      TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_transcripts_ts ON transcripts(ts DESC);
    `)
    db = d
    return d
  } catch (e) {
    dbFailed = true
    console.error('[history] SQLite unavailable — running without history:', e)
    return null
  }
}

/** Persist a transcript (text empty + error set for failures). Returns rowid,
 *  or -1 if history is unavailable. */
export function appendTranscript(text: string, model: string, durationS: number, error?: string): number {
  const d = getDb()
  if (!d) return -1
  try {
    const info = d
      .prepare('INSERT INTO transcripts (ts, text, model, duration_s, pasted, error) VALUES (?, ?, ?, ?, 0, ?)')
      .run(Date.now() / 1000, text, model, durationS, error ?? null)
    return Number(info.lastInsertRowid)
  } catch (e) {
    console.error('[history] append failed:', e)
    return -1
  }
}

export function markPasted(id: number): void {
  if (id < 0) return
  try {
    getDb()?.prepare('UPDATE transcripts SET pasted = 1 WHERE id = ?').run(id)
  } catch (e) {
    console.error('[history] markPasted failed:', e)
  }
}

/** Delete rows older than `retentionDays` (<=0 is a no-op). Returns rows deleted. */
export function pruneHistory(retentionDays: number): number {
  if (retentionDays <= 0) return 0
  const d = getDb()
  if (!d) return 0
  try {
    return d.prepare('DELETE FROM transcripts WHERE ts < ?').run(Date.now() / 1000 - retentionDays * 86_400).changes
  } catch (e) {
    console.error('[history] prune failed:', e)
    return 0
  }
}

export interface Transcript {
  id: number
  timestamp: number // Unix epoch seconds
  text: string
  model: string
  durationS: number | null
  pasted: boolean
  error: string | null
}

interface TranscriptRow {
  id: number
  ts: number
  text: string
  model: string
  duration_s: number | null
  pasted: number
  error: string | null
}

export function recentTranscripts(limit = 200): Transcript[] {
  const rows = getDb()
    .prepare('SELECT id, ts, text, model, duration_s, pasted, error FROM transcripts ORDER BY ts DESC LIMIT ?')
    .all(limit) as TranscriptRow[]
  return rows.map((r) => ({
    id: r.id,
    timestamp: r.ts,
    text: r.text,
    model: r.model,
    durationS: r.duration_s,
    pasted: r.pasted !== 0,
    error: r.error,
  }))
}

export function deleteTranscript(id: number): void {
  getDb().prepare('DELETE FROM transcripts WHERE id = ?').run(id)
}

export interface UsageRow {
  model: string
  count: number
  totalSeconds: number
}

export function usageByModel(): UsageRow[] {
  const rows = getDb()
    .prepare('SELECT model, COUNT(*) AS count, COALESCE(SUM(duration_s), 0) AS total FROM transcripts GROUP BY model')
    .all() as Array<{ model: string; count: number; total: number }>
  return rows.map((r) => ({ model: r.model, count: r.count, totalSeconds: r.total }))
}

// OpenAI published per-minute transcription pricing (Swift parity).
export function pricePerMinute(model: string): number {
  switch (model) {
    case 'whisper-1':
    case 'gpt-4o-transcribe':
      return 0.006
    case 'gpt-4o-mini-transcribe':
      return 0.003
    default:
      return 0.006
  }
}

export function estimatedCost(row: UsageRow): number {
  return pricePerMinute(row.model) * (row.totalSeconds / 60)
}
