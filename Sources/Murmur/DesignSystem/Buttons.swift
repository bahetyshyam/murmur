import SwiftUI

/// Murmur's button styles in the Ink identity — adapts Wispr's black pill to a
/// deep ink-blue fill with cream text. Three kinds:
/// - `.primary`   — solid ink pill, cream text (the main CTA).
/// - `.secondary` — cream/outlined pill, ink text.
/// - `.ghost`     — text-only, for tertiary actions.
struct InkButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }
    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        InkButton(kind: kind, configuration: configuration)
    }

    private struct InkButton: View {
        let kind: Kind
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .ghost ? 6 : 18)
                .padding(.vertical, kind == .ghost ? 4 : 9)
                .background(background)
                .overlay(border)
                .clipShape(Capsule(style: .continuous))
                .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1.0) : 0.4)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var foreground: Color {
            switch kind {
            case .primary:   return .inkCanvas
            case .secondary: return .inkText
            case .ghost:     return .inkText
            }
        }

        @ViewBuilder private var background: some View {
            switch kind {
            case .primary:   Capsule(style: .continuous).fill(Color.inkText)
            case .secondary: Capsule(style: .continuous).fill(Color.inkSurface)
            case .ghost:     Color.clear
            }
        }

        @ViewBuilder private var border: some View {
            if kind == .secondary {
                Capsule(style: .continuous).strokeBorder(Color.inkText.opacity(0.22), lineWidth: 1)
            }
        }
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    static var inkPrimary: InkButtonStyle { InkButtonStyle(kind: .primary) }
    static var inkSecondary: InkButtonStyle { InkButtonStyle(kind: .secondary) }
    static var inkGhost: InkButtonStyle { InkButtonStyle(kind: .ghost) }
}
