/// <reference types="vite/client" />
import type { MurmurApi } from '../../preload'

declare global {
  interface Window {
    murmur: MurmurApi
  }
}
