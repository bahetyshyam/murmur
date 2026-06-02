import AppKit

/// Serif display type for Murmur's headlines, resolved without shipping a font
/// file. SwiftUI code can use `Font.system(size:weight:design:.serif)` directly;
/// this AppKit helper exists for the build-time DMG renderer, which has no
/// SwiftUI context and must resolve a concrete `NSFont`.
public enum DSFont {
    /// A serif font at the given size/weight. Resolution order:
    /// 1. The system serif design (New York, bundled with macOS 14+).
    /// 2. Georgia, then Times New Roman (always present fallbacks).
    /// 3. The plain system font (so we never return something unusable).
    public static func serif(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.serif),
           let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        for name in ["Georgia", "Times New Roman"] {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return base
    }
}
