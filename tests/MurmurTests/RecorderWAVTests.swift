import Foundation
@testable import Murmur

/// Pure-data tests for `Recorder.wavBytes` — no AVAudioEngine, no mic, no
/// TCC prompt. The engine path is exercised interactively.
enum RecorderWAVTests {
    static func run() {
        Harness.suite("RecorderWAV") {
            Harness.test("headerForEmptyPCM") {
                let wav = Recorder.wavBytes(pcm: Data(), sampleRate: 16000, channels: 1)
                Harness.expectEqual(wav.count, 44)

                Harness.expectEqual(Array(wav[0..<4]),   Array("RIFF".utf8))
                Harness.expectEqual(Array(wav[8..<12]),  Array("WAVE".utf8))
                Harness.expectEqual(Array(wav[12..<16]), Array("fmt ".utf8))
                Harness.expectEqual(Array(wav[36..<40]), Array("data".utf8))

                Harness.expectEqual(readLEUInt32(wav, offset: 4),  36)
                Harness.expectEqual(readLEUInt32(wav, offset: 16), 16)
                Harness.expectEqual(readLEUInt16(wav, offset: 20), 1)
                Harness.expectEqual(readLEUInt16(wav, offset: 22), 1)
                Harness.expectEqual(readLEUInt32(wav, offset: 24), 16000)
                Harness.expectEqual(readLEUInt32(wav, offset: 28), 32000)
                Harness.expectEqual(readLEUInt16(wav, offset: 32), 2)
                Harness.expectEqual(readLEUInt16(wav, offset: 34), 16)
                Harness.expectEqual(readLEUInt32(wav, offset: 40), 0)
            }

            Harness.test("headerAccountsForPayloadSize") {
                var pcm = Data()
                for i: Int16 in 0..<10 {
                    var v = i.littleEndian
                    withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
                }
                let wav = Recorder.wavBytes(pcm: pcm, sampleRate: 16000, channels: 1)

                Harness.expectEqual(wav.count, 44 + 20)
                Harness.expectEqual(readLEUInt32(wav, offset: 4),  36 + 20)
                Harness.expectEqual(readLEUInt32(wav, offset: 40), 20)
                Harness.expectEqual(Array(wav[44...]), Array(pcm))
            }

            Harness.test("stereoHeader") {
                let wav = Recorder.wavBytes(pcm: Data(), sampleRate: 44100, channels: 2)
                Harness.expectEqual(readLEUInt16(wav, offset: 22), 2)
                Harness.expectEqual(readLEUInt32(wav, offset: 24), 44100)
                Harness.expectEqual(readLEUInt32(wav, offset: 28), 176400)
                Harness.expectEqual(readLEUInt16(wav, offset: 32), 4)
            }
        }
    }

    private static func readLEUInt16(_ d: Data, offset: Int) -> UInt16 {
        UInt16(d[offset]) | (UInt16(d[offset + 1]) << 8)
    }

    private static func readLEUInt32(_ d: Data, offset: Int) -> UInt32 {
        UInt32(d[offset])
            | (UInt32(d[offset + 1]) << 8)
            | (UInt32(d[offset + 2]) << 16)
            | (UInt32(d[offset + 3]) << 24)
    }
}
