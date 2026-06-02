import { app, safeStorage } from 'electron'
import { join } from 'path'
import { readFile, writeFile, rm } from 'fs/promises'

// OpenAI API key storage in the MAIN process only — encrypted at rest via
// Electron safeStorage (backed by the macOS Keychain), persisted to a file in
// userData. The plaintext key never crosses IPC to the renderer; only main
// reads it (when uploading). Replaces the Swift app's Keychain slot
// (service "murmur" / account "openai_api_key").
const keyFile = (): string => join(app.getPath('userData'), 'openai-key.enc')

export async function setKey(plain: string): Promise<void> {
  const trimmed = plain.trim()
  if (!trimmed) throw new Error('Key is empty.')
  if (!safeStorage.isEncryptionAvailable()) {
    throw new Error('Secure storage is unavailable on this system.')
  }
  await writeFile(keyFile(), safeStorage.encryptString(trimmed))
}

export async function getKey(): Promise<string | null> {
  try {
    const enc = await readFile(keyFile())
    const plain = safeStorage.decryptString(enc)
    return plain.length > 0 ? plain : null
  } catch {
    return null
  }
}

export async function clearKey(): Promise<void> {
  try {
    await rm(keyFile())
  } catch {
    /* already absent */
  }
}

export async function hasKey(): Promise<boolean> {
  return (await getKey()) !== null
}
