// AudioWorklet processor source, embedded as a string and loaded at runtime via
// a Blob URL (see recorder.ts). This is deliberately NOT a separate file loaded
// with Vite's `?url`: Vite inlines small assets as base64 data URLs, which are
// unreliable for `audioWorklet.addModule`. A Blob URL is bundler-agnostic and
// behaves identically in dev (http) and the packaged app (file://).
//
// The processor forwards each mono Float32 capture block to the main thread,
// copying (the input buffer is reused per block) and transferring the buffer.
export const CAPTURE_WORKLET_SRC = `
class CaptureProcessor extends AudioWorkletProcessor {
  process(inputs) {
    const input = inputs[0]
    if (input && input[0]) {
      const block = input[0].slice(0)
      this.port.postMessage(block, [block.buffer])
    }
    return true
  }
}
registerProcessor('capture-processor', CaptureProcessor)
`
