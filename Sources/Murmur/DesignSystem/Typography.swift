import SwiftUI

/// Serif display type for Murmur's headlines (SwiftUI New York, no font file
/// shipped — `design: .serif`), with sans-serif body/caption tokens. Mirrors
/// the AppKit `DSFont.serif` used by the DMG renderer.
enum Typography {
    /// Large serif headline — the step's main line.
    static func display(_ size: CGFloat = 30) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
    /// Smaller serif heading.
    static func heading(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
    /// Body copy (sans).
    static func body(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular)
    }
    /// Caption / secondary (sans).
    static func caption(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .regular)
    }
    /// Uppercased, tracked label used by the progress rail.
    static func railLabel(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .semibold)
    }
}
