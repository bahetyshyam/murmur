import Foundation

/// Classified failure modes from the transcription pipeline.
/// The UI renders distinct messages for each so the user can act on them.
enum TranscriberError: Error, CustomStringConvertible, Equatable {
    /// 401 — user's API key is wrong, expired, or revoked.
    case auth
    /// 429 — rate-limited or quota exhausted.
    case rateLimit
    /// URLSession-level failure (offline, DNS, TLS). The inner description
    /// carries the NSError message; keep it human-readable for Settings UI.
    case network(String)
    /// Any other non-2xx response.
    case http(status: Int, message: String)
    /// 200 but the body wasn't what we expected.
    case malformedResponse

    var description: String {
        switch self {
        case .auth:                       return "Invalid OpenAI API key (401)"
        case .rateLimit:                  return "Rate limit / quota exhausted (429)"
        case .network(let msg):           return "Network: \(msg)"
        case .http(let s, let m):         return "HTTP \(s): \(m)"
        case .malformedResponse:          return "Malformed response from OpenAI"
        }
    }

    /// Short, end-user-friendly message for HUD / notifications.
    var userMessage: String {
        switch self {
        case .auth:           return "API key invalid — open Settings."
        case .rateLimit:      return "Rate limit hit — try again shortly."
        case .network:        return "Network unavailable."
        case .http(let s, _): return "OpenAI returned \(s)."
        case .malformedResponse: return "Unexpected OpenAI response."
        }
    }
}
