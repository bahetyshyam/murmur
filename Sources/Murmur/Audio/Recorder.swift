import AVFAudio
import Foundation
import OSLog

enum RecorderError: Error, CustomStringConvertible {
    case alreadyRecording
    case notRecording
    case engineStartFailed(Error)
    case converterInitFailed
    case converterRunFailed(String)

    var description: String {
        switch self {
        case .alreadyRecording:         return "Recorder.alreadyRecording"
        case .notRecording:             return "Recorder.notRecording"
        case .engineStartFailed(let e): return "Recorder.engineStartFailed(\(e))"
        case .converterInitFailed:      return "Recorder.converterInitFailed"
        case .converterRunFailed(let s): return "Recorder.converterRunFailed(\(s))"
        }
    }
}

/// Microphone → interleaved 16-bit PCM → WAV bytes.
///
/// Design notes
/// ------------
/// * **Non-isolated** because the audio tap callback fires on AVAudio's
///   own thread. All shared state is guarded by `lock`.
/// * **Release-tail drain**: `stop(tailMs:)` sleeps briefly *before*
///   removing the tap / stopping the engine, so the last few PortAudio-
///   equivalent chunks aren't dropped. Parity with the Python fix.
/// * **Resampling**: input format from the HAL is typically 44.1 or
///   48 kHz Float32. We plumb it through `AVAudioConverter` to our
///   target (16 kHz Int16 mono by default — cheaper upload, fully
///   adequate for speech).
final class Recorder {
    private let log = Logger(subsystem: "com.local.murmur", category: "recorder")
    private let engine = AVAudioEngine()
    private let lock = NSLock()

    // Written on audio thread, read on caller thread under `lock`.
    private var pcm = Data()
    private var isRecording = false
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    private let targetSampleRate: Int
    private let targetChannels: Int

    // MARK: Live input level (0…1, smoothed).
    //
    // Computed off the pre-resample Float32 buffer with an attack/release
    // envelope so the HUD waveform rises quickly on speech and decays
    // gently during silence. `onLevel` is throttled to ~30Hz so we don't
    // fan out into SwiftUI 200x per second.
    private let levelLock = NSLock()
    private var _smoothedLevel: Float = 0
    private var lastLevelEmit: CFAbsoluteTime = 0

    /// Last reported smoothed level. Thread-safe.
    var currentLevel: Float {
        levelLock.lock(); defer { levelLock.unlock() }
        return _smoothedLevel
    }

    /// Optional fan-out invoked on the main queue when the level changes.
    /// The HUD subscribes while visible and nils this out when hidden.
    var onLevel: ((Float) -> Void)?

    init(sampleRate: Int = 16000, channels: Int = 1) {
        self.targetSampleRate = sampleRate
        self.targetChannels = channels
    }

    /// Whether a session is in progress. Thread-safe.
    var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return isRecording
    }

    // MARK: - Public lifecycle

    /// Begin capturing. Fails if already active. Prompts the user for
    /// Microphone permission on first call (TCC banner).
    func start() throws {
        lock.lock()
        if isRecording {
            lock.unlock()
            throw RecorderError.alreadyRecording
        }
        pcm.removeAll(keepingCapacity: true)
        lock.unlock()

        // Reset the smoothed level so leftover state from the last
        // session doesn't bleed into the HUD.
        levelLock.lock()
        _smoothedLevel = 0
        lastLevelEmit = 0
        levelLock.unlock()

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(targetSampleRate),
            channels: AVAudioChannelCount(targetChannels),
            interleaved: true
        ) else {
            throw RecorderError.converterInitFailed
        }
        guard let conv = AVAudioConverter(from: inputFormat, to: target) else {
            throw RecorderError.converterInitFailed
        }
        converter = conv
        targetFormat = target

        log.info("start: input=\(inputFormat.sampleRate, privacy: .public)Hz/\(inputFormat.channelCount, privacy: .public)ch → target=\(self.targetSampleRate, privacy: .public)Hz/\(self.targetChannels, privacy: .public)ch")

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecorderError.engineStartFailed(error)
        }

        lock.lock()
        isRecording = true
        lock.unlock()
    }

    /// Stop capturing and return the WAV bytes. `tailMs` extra milliseconds
    /// of audio are captured before teardown (compensates for OS input
    /// latency — last syllables would otherwise be clipped).
    func stop(tailMs: Int) async throws -> Data {
        lock.lock()
        if !isRecording {
            lock.unlock()
            throw RecorderError.notRecording
        }
        lock.unlock()

        if tailMs > 0 {
            try? await Task.sleep(nanoseconds: UInt64(tailMs) * 1_000_000)
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        isRecording = false
        let captured = pcm
        lock.unlock()

        log.info("stop: captured \(captured.count, privacy: .public) PCM bytes (\(captured.count / 2, privacy: .public) samples)")
        return Self.wavBytes(pcm: captured, sampleRate: targetSampleRate, channels: targetChannels)
    }

    // MARK: - Audio thread

    private func process(buffer: AVAudioPCMBuffer) {
        updateLevel(from: buffer)

        guard let converter, let target = targetFormat else { return }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrames) else {
            return
        }

        var error: NSError?
        var consumed = false
        _ = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let error {
            log.error("convert error: \(error.localizedDescription, privacy: .public)")
            return
        }

        let abl = outBuffer.audioBufferList.pointee.mBuffers
        guard let mData = abl.mData, abl.mDataByteSize > 0 else { return }

        lock.lock()
        pcm.append(mData.assumingMemoryBound(to: UInt8.self), count: Int(abl.mDataByteSize))
        lock.unlock()
    }

    // MARK: - Level metering (audio thread)

    /// Compute RMS of the Float32 input buffer, smooth it with an
    /// attack/release envelope, and publish it (throttled to ~30Hz) to
    /// `onLevel` so the HUD can animate without being deluged.
    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Average across channels (usually mono anyway).
        let channelCount = Int(buffer.format.channelCount)
        var sumSq: Float = 0
        for c in 0..<channelCount {
            let samples = channelData[c]
            var localSq: Float = 0
            for i in 0..<frameCount {
                let s = samples[i]
                localSq += s * s
            }
            sumSq += localSq
        }
        let meanSq = sumSq / Float(frameCount * max(channelCount, 1))
        let rms = sqrtf(meanSq)

        // Speech RMS rarely exceeds ~0.3 at typical mic gain; 3× gain
        // lifts it into a visible range, then clamp.
        let boosted = min(max(rms * 3.0, 0), 1.0)

        // Attack/release envelope: instant rise, ~15% decay per frame.
        levelLock.lock()
        let previous = _smoothedLevel
        let next = max(boosted, previous * 0.85)
        _smoothedLevel = next
        levelLock.unlock()

        // Throttle UI fan-out to ~30Hz.
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastLevelEmit < (1.0 / 30.0) { return }
        lastLevelEmit = now

        if let cb = onLevel {
            DispatchQueue.main.async {
                cb(next)
            }
        }
    }

    // MARK: - WAV encoding (pure, testable)

    /// Wrap raw interleaved Int16 little-endian PCM in a WAVE/PCM header.
    static func wavBytes(pcm: Data, sampleRate: Int, channels: Int) -> Data {
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate * channels * Int(bitsPerSample) / 8)
        let blockAlign = UInt16(channels * Int(bitsPerSample) / 8)
        let subchunk2Size = UInt32(pcm.count)
        let chunkSize = 36 + subchunk2Size

        var header = Data()
        header.append(Data("RIFF".utf8))
        header.appendLE(chunkSize)
        header.append(Data("WAVE".utf8))
        header.append(Data("fmt ".utf8))
        header.appendLE(UInt32(16))                 // PCM subchunk size
        header.appendLE(UInt16(1))                  // format = PCM
        header.appendLE(UInt16(channels))
        header.appendLE(UInt32(sampleRate))
        header.appendLE(byteRate)
        header.appendLE(blockAlign)
        header.appendLE(bitsPerSample)
        header.append(Data("data".utf8))
        header.appendLE(subchunk2Size)

        var out = Data()
        out.reserveCapacity(header.count + pcm.count)
        out.append(header)
        out.append(pcm)
        return out
    }
}

private extension Data {
    mutating func appendLE(_ v: UInt16) {
        var x = v.littleEndian
        Swift.withUnsafeBytes(of: &x) { self.append(contentsOf: $0) }
    }
    mutating func appendLE(_ v: UInt32) {
        var x = v.littleEndian
        Swift.withUnsafeBytes(of: &x) { self.append(contentsOf: $0) }
    }
}
