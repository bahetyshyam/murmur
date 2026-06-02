import AppKit

/// The Ink-palette app icon (cream dot on deep ink-blue), drawn in pure code.
/// Lives in `DesignSystemCore` so both the app (`MurmurIcon.appIcon`, for
/// `NSApp.applicationIconImage`) and the build-time `DMGAssets` tool (which
/// renders the `.icns` so Finder/Dock/the DMG show the real icon) share one
/// implementation. Moved verbatim from `MurmurIcon` — output is unchanged.
public enum InkIcon {
    private static let squircleRadiusRatio: CGFloat = 0.2237

    /// Full-color app icon at the requested size.
    public static func appIcon(size: CGFloat = 512) -> NSImage {
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawAppIcon(in: rect)
            return true
        }
    }

    /// Draw the icon into the current graphics context within `rect`.
    public static func drawAppIcon(in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let s = rect.width
        let r = s * squircleRadiusRatio

        // Clip to squircle (rounded rect as approximation — iOS/Big Sur icons
        // use a quintic superellipse, but a rounded rect at 0.2237 is close
        // enough at export sizes and is what NSBezierPath can do natively).
        let squircle = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        ctx.saveGState()
        squircle.addClip()

        // 1. Ink background — 165° linear gradient #1e2a3c → #0c1626.
        let top = Ink.inkTop
        let bot = Ink.inkBottom
        let bg = NSGradient(colors: [top, bot])
        let dx = sin(165 * .pi / 180) * s
        let dy = -cos(165 * .pi / 180) * s
        bg?.draw(from: NSPoint(x: rect.midX - dx / 2, y: rect.midY + dy / 2),
                 to:   NSPoint(x: rect.midX + dx / 2, y: rect.midY - dy / 2),
                 options: [])

        // 2. Warm halo — radial gradient centered, rgba(245,235,210,0.35) → 0.12 → 0.
        let haloColor = Ink.halo
        if let halo = NSGradient(colors: [
            haloColor.withAlphaComponent(0.35),
            haloColor.withAlphaComponent(0.12),
            haloColor.withAlphaComponent(0.0),
        ], atLocations: [0.0, 0.22, 0.5], colorSpace: .deviceRGB) {
            halo.draw(fromCenter: NSPoint(x: rect.midX, y: rect.midY), radius: 0,
                      toCenter: NSPoint(x: rect.midX, y: rect.midY), radius: s * 0.5,
                      options: [])
        }

        // 3. Soft outer glow behind the dot — #f3e9cf spread.
        let glowColor = Ink.accentSoft.withAlphaComponent(0.55)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.2, color: glowColor.cgColor)
        let dotDiameter = s * 0.22
        let dotRect = NSRect(
            x: rect.midX - dotDiameter / 2,
            y: rect.midY - dotDiameter / 2,
            width: dotDiameter,
            height: dotDiameter
        )
        // Fill with a neutral so the shadow casts; the real dot gradient is drawn next.
        Ink.accentSoft.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        ctx.restoreGState()

        // 4. Cream core — radial gradient #fdfaf1 → #f3e9cf (55%) → #d7c48e (100%).
        let core1 = Ink.cream
        let core2 = Ink.accentSoft
        let core3 = Ink.accent
        if let core = NSGradient(colors: [core1, core2, core3],
                                 atLocations: [0.0, 0.55, 1.0],
                                 colorSpace: .deviceRGB) {
            ctx.saveGState()
            NSBezierPath(ovalIn: dotRect).addClip()
            core.draw(fromCenter: NSPoint(x: dotRect.midX, y: dotRect.midY), radius: 0,
                      toCenter: NSPoint(x: dotRect.midX, y: dotRect.midY), radius: dotDiameter * 0.6,
                      options: [])
            ctx.restoreGState()
        }

        // 5. Reflection highlight — small ellipse, soft, upper-left of the dot.
        let reflW = s * 0.07
        let reflH = s * 0.045
        let reflRect = NSRect(
            x: rect.midX - reflW / 2,
            y: rect.midY + s * 0.07 - reflH / 2,  // 43% from top in a 100% box = 7% above center
            width: reflW,
            height: reflH
        )
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.02, color: NSColor.white.withAlphaComponent(0.75).cgColor)
        NSColor.white.withAlphaComponent(0.75).setFill()
        NSBezierPath(ovalIn: reflRect).fill()
        ctx.restoreGState()

        ctx.restoreGState()
    }
}
