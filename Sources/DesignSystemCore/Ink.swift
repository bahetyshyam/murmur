import AppKit

/// The **Ink** palette — Murmur's brand colors, as `NSColor` so they're usable
/// from pure-code AppKit drawing (the app icon, the menubar glyph, and the
/// build-time DMG background renderer). SwiftUI `Color` mirrors live in the
/// Murmur target's `DesignSystem/InkColors.swift`.
///
/// Cream dot on deep ink-blue, with a warm gold accent. The exact `NSColor`
/// initializers here are byte-for-byte the same expressions previously inlined
/// in `MurmurIcon`, so consuming these tokens is visually inert.
public enum Ink {
    /// Lightest cream — canvas / the dot's bright core (`#fdfaf1`).
    public static let cream = NSColor(red: 0xfd / 255.0, green: 0xfa / 255.0, blue: 0xf1 / 255.0, alpha: 1.0)
    /// Soft warm cream — the accent's pale tint / dot mid-tone (`#f3e9cf`).
    public static let accentSoft = NSColor(red: 0xf3 / 255.0, green: 0xe9 / 255.0, blue: 0xcf / 255.0, alpha: 1.0)
    /// Gold accent — the brand's "lights up" highlight (`#d7c48e`).
    public static let accent = NSColor(red: 0xd7 / 255.0, green: 0xc4 / 255.0, blue: 0x8e / 255.0, alpha: 1.0)
    /// Top of the ink-blue background gradient (`#1e2a3c`).
    public static let inkTop = NSColor(red: 0x1e / 255.0, green: 0x2a / 255.0, blue: 0x3c / 255.0, alpha: 1.0)
    /// Bottom of the ink-blue background gradient (`#0c1626`).
    public static let inkBottom = NSColor(red: 0x0c / 255.0, green: 0x16 / 255.0, blue: 0x26 / 255.0, alpha: 1.0)
    /// Warm halo glow over the ink background (`#f5ebd2`).
    public static let halo = NSColor(red: 245 / 255.0, green: 235 / 255.0, blue: 210 / 255.0, alpha: 1.0)

    // MARK: - Gradient builders (reused by the icon + DMG renderers)

    /// 2-stop ink-blue background gradient (top → bottom).
    public static func inkGradient() -> NSGradient? {
        NSGradient(colors: [inkTop, inkBottom])
    }

    /// 3-stop cream core gradient: bright core → soft mid → gold edge.
    public static func creamCoreGradient() -> NSGradient? {
        NSGradient(colors: [cream, accentSoft, accent],
                   atLocations: [0.0, 0.55, 1.0],
                   colorSpace: .deviceRGB)
    }
}
