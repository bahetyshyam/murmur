import Foundation

/// One row in the transcript history. Plain value type (no SwiftData)
/// because the SwiftData macro plugin isn't bundled with the Command
/// Line Tools toolchain, and this app builds without full Xcode.
///
/// Persistence lives in `HistoryStore` (SQLite3, schema-compatible with
/// the Python prototype so a future migration could preserve rows).
struct Transcript: Equatable, Identifiable {
    var id: Int64
    var timestamp: Date
    var text: String
    var model: String
    var durationS: Double?
    var pasted: Bool
    /// Non-nil when transcription itself failed (e.g. auth, rate limit).
    var error: String?
}
