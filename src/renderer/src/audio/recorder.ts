import { encodeWav, floatToInt16 } from './wav'
import { CAPTURE_WORKLET_SRC } from './worklet-source'

// Renderer-side audio capture, matching the Swift Recorder's output contract:
// 16 kHz / mono / Int16 WAV, a 300 ms real-audio release tail, and an RMS level
// meter (×3 boost, 0.85 release envelope, throttled to ~30 Hz).
const TARGET_RATE = 16000

export interface InputDevice {
  deviceId: string
  label: string
}

export interface RecordResult {
  wav: ArrayBuffer
  durationS: number
  sampleRate: number
  frames: number
  /** Peak smoothed input level (0…1) seen during the session — used to detect
   *  "no speech" so we don't transcribe silence (which the model hallucinates). */
  peakLevel: number
}

/** List audio input devices. Labels are only populated after mic permission
 *  has been granted at least once this session. */
export async function listInputDevices(): Promise<InputDevice[]> {
  const devices = await navigator.mediaDevices.enumerateDevices()
  return devices
    .filter((d) => d.kind === 'audioinput')
    .map((d) => ({ deviceId: d.deviceId, label: d.label || 'Microphone' }))
}

export class AudioRecorder {
  private ctx: AudioContext | null = null
  private stream: MediaStream | null = null
  private workletNode: AudioWorkletNode | null = null
  private source: MediaStreamAudioSourceNode | null = null
  private sink: GainNode | null = null
  private chunks: Float32Array[] = []
  private totalFrames = 0
  private nativeRate = 48000
  private smoothed = 0
  private peak = 0
  private lastEmit = 0
  private recording = false
  private onLevel?: (level: number) => void
  private onDisconnect?: () => void

  get isRecording(): boolean {
    return this.recording
  }

  async start(
    deviceId: string | undefined,
    onLevel?: (level: number) => void,
    onDisconnect?: () => void,
  ): Promise<void> {
    if (this.recording) throw new Error('already recording')
    this.onLevel = onLevel
    this.onDisconnect = onDisconnect
    this.chunks = []
    this.totalFrames = 0
    this.smoothed = 0
    this.peak = 0
    this.lastEmit = 0

    // Raw capture: disable browser DSP so we get the unprocessed mic signal
    // (parity with AVAudioEngine's raw tap).
    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        deviceId: deviceId ? { exact: deviceId } : undefined,
        channelCount: 1,
        echoCancellation: false,
        noiseSuppression: false,
        autoGainControl: false,
      },
    })

    // Mid-recording device disconnect (e.g. AirPods drop) — a failure mode the
    // Swift app never had since it used the system default.
    const track = this.stream.getAudioTracks()[0]
    track?.addEventListener('ended', () => this.onDisconnect?.())

    this.ctx = new AudioContext()
    this.nativeRate = this.ctx.sampleRate
    const blobUrl = URL.createObjectURL(new Blob([CAPTURE_WORKLET_SRC], { type: 'text/javascript' }))
    try {
      await this.ctx.audioWorklet.addModule(blobUrl)
    } finally {
      URL.revokeObjectURL(blobUrl)
    }

    this.source = this.ctx.createMediaStreamSource(this.stream)
    this.workletNode = new AudioWorkletNode(this.ctx, 'capture-processor')
    this.workletNode.port.onmessage = (e) => this.onBlock(e.data as Float32Array)

    // Pull the graph through a muted gain → destination so the worklet's
    // process() runs without echoing the mic to the speakers.
    this.sink = this.ctx.createGain()
    this.sink.gain.value = 0
    this.source.connect(this.workletNode)
    this.workletNode.connect(this.sink)
    this.sink.connect(this.ctx.destination)

    // The record click is a user gesture, but resume defensively in case the
    // context started suspended (else process() never runs → empty WAV).
    if (this.ctx.state === 'suspended') await this.ctx.resume()

    this.recording = true
  }

  private onBlock(block: Float32Array): void {
    if (!this.recording) return
    this.chunks.push(block)
    this.totalFrames += block.length

    // RMS → ×3 boost → attack-instant / 0.85-release envelope → ~30 Hz throttle.
    let sumSq = 0
    for (let i = 0; i < block.length; i++) sumSq += block[i] * block[i]
    const rms = Math.sqrt(sumSq / Math.max(block.length, 1))
    const boosted = Math.min(Math.max(rms * 3, 0), 1)
    this.smoothed = Math.max(boosted, this.smoothed * 0.85)
    if (this.smoothed > this.peak) this.peak = this.smoothed

    const now = performance.now()
    if (now - this.lastEmit >= 1000 / 30) {
      this.lastEmit = now
      this.onLevel?.(this.smoothed)
    }
  }

  async stop(tailMs = 300): Promise<RecordResult> {
    if (!this.recording) throw new Error('not recording')

    // Release tail: keep capturing REAL mic audio for tailMs, then tear down.
    // (Swift sleeps while the live tap keeps appending frames — not silence pad.)
    if (tailMs > 0) await new Promise((r) => setTimeout(r, tailMs))
    // Drain any worklet block already in flight to the main thread before we
    // flip the flag, so the final ~1-5 frames aren't dropped.
    await new Promise((r) => setTimeout(r, 0))
    this.recording = false

    this.source?.disconnect()
    this.workletNode?.disconnect()
    this.sink?.disconnect()
    this.stream?.getTracks().forEach((t) => t.stop())

    const captured = new Float32Array(this.totalFrames)
    let off = 0
    for (const c of this.chunks) {
      captured.set(c, off)
      off += c.length
    }
    const durationS = captured.length / this.nativeRate

    const out16k = await this.resample(captured, this.nativeRate, TARGET_RATE)
    const int16 = floatToInt16(out16k)
    const wav = encodeWav(int16, TARGET_RATE, 1)

    await this.ctx?.close()
    this.ctx = null
    this.chunks = []
    return { wav, durationS, sampleRate: TARGET_RATE, frames: int16.length, peakLevel: this.peak }
  }

  /** Resample native-rate Float32 → 16 kHz mono via the browser's high-quality
   *  OfflineAudioContext resampler. */
  private async resample(input: Float32Array, fromRate: number, toRate: number): Promise<Float32Array> {
    if (input.length === 0) return new Float32Array(0)
    if (fromRate === toRate) return input
    const frameCount = Math.max(1, Math.round((input.length * toRate) / fromRate))
    const offline = new OfflineAudioContext(1, frameCount, toRate)
    const buf = offline.createBuffer(1, input.length, fromRate)
    // `.set()` (vs copyToChannel) avoids the TS 5.7 Float32Array<ArrayBuffer>
    // generic mismatch and does the same single copy into the channel buffer.
    buf.getChannelData(0).set(input)
    const src = offline.createBufferSource()
    src.buffer = buf
    src.connect(offline.destination)
    src.start()
    const rendered = await offline.startRendering()
    return rendered.getChannelData(0)
  }
}
