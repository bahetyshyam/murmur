// OpenAI transcription in the MAIN process. Faithful port of the Swift
// Transcriber: multipart POST to /v1/audio/transcriptions with the exact field
// order (model, response_format=json, [prompt], [language], file) and the exact
// status→error classification + user-facing messages.

const ENDPOINT = 'https://api.openai.com/v1/audio/transcriptions'

export type TranscribeErrorKind =
  | { kind: 'auth' }
  | { kind: 'rateLimit' }
  | { kind: 'network'; detail: string }
  | { kind: 'http'; status: number; body: string }
  | { kind: 'malformed' }
  | { kind: 'noKey' }

export interface TranscribeError {
  kind: TranscribeErrorKind['kind']
  /** Short, end-user-friendly message (HUD / notifications) — matches Swift. */
  userMessage: string
  /** Verbose description stored in History — matches Swift's `description`. */
  description: string
  status?: number
}

export type TranscribeOutcome = { ok: true; text: string } | { ok: false; error: TranscribeError }

function makeError(e: TranscribeErrorKind): TranscribeError {
  switch (e.kind) {
    case 'auth':
      return { kind: 'auth', userMessage: 'API key invalid — open Settings.', description: 'Invalid OpenAI API key (401)' }
    case 'rateLimit':
      return { kind: 'rateLimit', userMessage: 'Rate limit hit — try again shortly.', description: 'Rate limit / quota exhausted (429)' }
    case 'network':
      return { kind: 'network', userMessage: 'Network unavailable.', description: `Network: ${e.detail}` }
    case 'http':
      return { kind: 'http', status: e.status, userMessage: `OpenAI returned ${e.status}.`, description: `HTTP ${e.status}: ${e.body}` }
    case 'malformed':
      return { kind: 'malformed', userMessage: 'Unexpected OpenAI response.', description: 'Malformed response from OpenAI' }
    case 'noKey':
      return { kind: 'noKey', userMessage: 'No API key — open Settings.', description: 'No API key stored' }
  }
}

export interface TranscribeParams {
  apiKey: string
  wav: ArrayBuffer | Uint8Array
  model: string
  prompt?: string
  language?: string
}

export async function transcribe(params: TranscribeParams): Promise<TranscribeOutcome> {
  const { apiKey, wav, model, prompt, language } = params

  // Field order matches the Swift multipart body exactly.
  const form = new FormData()
  form.append('model', model)
  form.append('response_format', 'json')
  if (prompt && prompt.length > 0) form.append('prompt', prompt)
  if (language && language.length > 0) form.append('language', language)
  const bytes = wav instanceof Uint8Array ? wav : new Uint8Array(wav)
  form.append('file', new Blob([bytes], { type: 'audio/wav' }), 'audio.wav')

  let res: Response
  try {
    res = await fetch(ENDPOINT, {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form,
    })
  } catch (e) {
    return { ok: false, error: makeError({ kind: 'network', detail: e instanceof Error ? e.message : String(e) }) }
  }

  if (res.status === 200) {
    try {
      const json = (await res.json()) as { text?: unknown }
      if (typeof json.text !== 'string') return { ok: false, error: makeError({ kind: 'malformed' }) }
      return { ok: true, text: json.text }
    } catch {
      return { ok: false, error: makeError({ kind: 'malformed' }) }
    }
  }
  if (res.status === 401) return { ok: false, error: makeError({ kind: 'auth' }) }
  if (res.status === 429) return { ok: false, error: makeError({ kind: 'rateLimit' }) }
  const body = await res.text().catch(() => '<binary>')
  return { ok: false, error: makeError({ kind: 'http', status: res.status, body }) }
}

export { makeError }
