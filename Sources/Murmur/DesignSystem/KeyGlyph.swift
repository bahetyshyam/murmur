import SwiftUI

/// A keycap glyph that "lights up" (gold glow) while held — used by the
/// onboarding shortcut-test step. Murmur's hotkeys are modifier-only, so this
/// shows a modifier label (e.g. "⌥ Right Option") rather than the fn/globe key
/// Wispr uses.
struct KeyGlyph: View {
    let label: String
    var active: Bool = false
    var size: CGFloat = 64

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
            .fill(active ? Color.inkAccentSoft : Color.inkSurface)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .strokeBorder(active ? Color.inkAccent : Color.inkText.opacity(0.2),
                                  lineWidth: active ? 2 : 1)
            )
            .overlay(
                Text(label)
                    .font(.system(size: size * 0.22, weight: .semibold))
                    .foregroundStyle(active ? Color.inkText : Color.inkTextSecondary)
                    .padding(size * 0.12)
                    .multilineTextAlignment(.center)
            )
            .frame(minWidth: size, minHeight: size)
            .shadow(color: active ? Color.inkAccent.opacity(0.55) : .clear,
                    radius: active ? 12 : 0)
            .animation(.easeOut(duration: 0.12), value: active)
    }
}
