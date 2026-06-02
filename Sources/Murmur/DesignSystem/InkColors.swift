import SwiftUI
import DesignSystemCore

/// SwiftUI `Color` mirrors of the `Ink` brand palette (the `NSColor` source of
/// truth lives in `DesignSystemCore/Ink.swift`), plus a few UI-only derived
/// tokens (panel surface, text) used by the onboarding + settings chrome.
extension Color {
    /// Bright cream canvas (`Ink.cream`).
    static let inkCanvas = Color(nsColor: Ink.cream)
    /// Warm paper panel — slightly darker than the canvas, for the wizard's
    /// illustration column and card fills.
    static let inkSurface = Color(red: 0.945, green: 0.918, blue: 0.851)
    /// Gold accent — the "lights up" highlight (`Ink.accent`).
    static let inkAccent = Color(nsColor: Ink.accent)
    /// Pale accent tint (`Ink.accentSoft`).
    static let inkAccentSoft = Color(nsColor: Ink.accentSoft)
    /// Deep ink-blue (gradient top / bottom).
    static let inkDeepTop = Color(nsColor: Ink.inkTop)
    static let inkDeepBottom = Color(nsColor: Ink.inkBottom)
    /// Primary text on cream — dark slate.
    static let inkText = Color(red: 0.12, green: 0.15, blue: 0.20)
    /// Secondary / caption text.
    static let inkTextSecondary = Color(red: 0.12, green: 0.15, blue: 0.20).opacity(0.55)
    /// Hairline divider on cream.
    static let inkHairline = Color(red: 0.12, green: 0.15, blue: 0.20).opacity(0.12)
}

/// Shared gradients for SwiftUI surfaces.
enum InkStyle {
    /// The deep ink-blue background (top → bottom), e.g. for dark illustration
    /// panels or the menubar dot motif.
    static var deep: LinearGradient {
        LinearGradient(colors: [.inkDeepTop, .inkDeepBottom], startPoint: .top, endPoint: .bottom)
    }
}
