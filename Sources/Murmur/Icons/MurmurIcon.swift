import AppKit

/// Pure-code rendering of Murmur's icon family. Avoids shipping
/// `Assets.xcassets` / `.icns` so the SPM build stays a single
/// `swift build` away from producing a working app.
///
/// Palette: **Ink** — soft cream dot on deep ink blue. Matches
/// `murmur/project/icon-explorations.jsx` DOT_VARIANTS.ink.
///
/// Menubar glyphs match `murmur/project/icon-library.jsx` MenubarGlyph:
/// 22pt-ish viewbox, 1.5/22 stroke scaling, circle ring + state-specific
/// interior. Rendered as a **template image** so macOS recolors for
/// light/dark/accented menubars automatically.
enum MurmurIcon {
    /// State the menubar glyph can represent. Mirrors `AppModel.State`
    /// but without the error message payload.
    enum GlyphState {
        case idle, recording, transcribing, error
    }

    // MARK: - Menubar template glyph

    /// Pure-black glyph on transparent background, marked as template so
    /// macOS tints it correctly for light/dark/accented menubars.
    static func menubarGlyph(_ state: GlyphState, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawMenubarGlyph(state: state, in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Murmur"
        return image
    }

    private static func drawMenubarGlyph(state: GlyphState, in rect: NSRect) {
        let s = rect.width
        let sw = s * 1.5 / 22                              // stroke scales with size
        let cx = rect.midX
        let cy = rect.midY
        let circR = s * 0.42

        NSColor.black.setStroke()
        NSColor.black.setFill()

        // Outer ring is always present — it's what makes the silhouette recognisable.
        let ring = NSBezierPath()
        ring.appendOval(in: NSRect(x: cx - circR, y: cy - circR,
                                   width: circR * 2, height: circR * 2))
        ring.lineWidth = sw
        ring.stroke()

        switch state {
        case .idle:
            drawIdleInterior(cx: cx, cy: cy, s: s, sw: sw)
        case .recording:
            let r = s * 0.17
            NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)).fill()
        case .transcribing:
            drawWaveformInterior(cx: cx, cy: cy, s: s, sw: sw)
        case .error:
            drawErrorInterior(cx: cx, cy: cy, s: s, sw: sw, circR: circR)
        }
    }

    /// Mic body (rounded rect), mic base curve, stem. Matches the JSX idle path.
    private static func drawIdleInterior(cx: CGFloat, cy: CGFloat, s: CGFloat, sw: CGFloat) {
        // Note: AppKit's y-axis points UP, whereas the JSX viewBox points DOWN.
        // We flip the y offsets so the mic body sits in the top half of the
        // ring and the stem hangs below.

        // Mic body: width=0.18s, height=0.22s, rx=0.09s, centered horizontally,
        // top half of the glyph.
        let bodyW = s * 0.18
        let bodyH = s * 0.22
        let bodyRect = NSRect(
            x: cx - bodyW / 2,
            y: cy - 0.05 * s,      // -(-0.17 + 0.22/2) ≈ -0.06; slight adjust for visual centering
            width: bodyW,
            height: bodyH
        )
        let body = NSBezierPath(roundedRect: bodyRect, xRadius: s * 0.09, yRadius: s * 0.09)
        body.lineWidth = sw
        body.lineCapStyle = .round
        body.lineJoinStyle = .round
        body.stroke()

        // Base U-curve — using a simple arc approximation via bezier. In AppKit
        // y-up space the curve opens downward (cups the mic from below).
        let base = NSBezierPath()
        let baseYTop = cy - s * 0.02
        let baseYBot = cy - s * 0.14
        base.move(to: NSPoint(x: cx - s * 0.13, y: baseYTop))
        base.curve(to: NSPoint(x: cx, y: baseYBot),
                   controlPoint1: NSPoint(x: cx - s * 0.13, y: baseYBot),
                   controlPoint2: NSPoint(x: cx - s * 0.07, y: baseYBot))
        base.curve(to: NSPoint(x: cx + s * 0.13, y: baseYTop),
                   controlPoint1: NSPoint(x: cx + s * 0.07, y: baseYBot),
                   controlPoint2: NSPoint(x: cx + s * 0.13, y: baseYBot))
        base.lineWidth = sw
        base.lineCapStyle = .round
        base.lineJoinStyle = .round
        base.stroke()

        // Stem — short vertical tick under the mic base.
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: cx, y: baseYBot))
        stem.line(to: NSPoint(x: cx, y: baseYBot - s * 0.06))
        stem.lineWidth = sw
        stem.lineCapStyle = .round
        stem.stroke()
    }

    /// Five vertical bars (heights 0.10, 0.18, 0.24, 0.18, 0.10) centered on cy.
    private static func drawWaveformInterior(cx: CGFloat, cy: CGFloat, s: CGFloat, sw: CGFloat) {
        let heights: [CGFloat] = [0.10, 0.18, 0.24, 0.18, 0.10]
        let stroke = sw * 1.1
        for (i, h) in heights.enumerated() {
            let x = cx + CGFloat(i - 2) * s * 0.09
            let bar = NSBezierPath()
            bar.move(to: NSPoint(x: x, y: cy - s * h))
            bar.line(to: NSPoint(x: x, y: cy + s * h))
            bar.lineWidth = stroke
            bar.lineCapStyle = .round
            bar.stroke()
        }
    }

    /// Triangle + exclamation bar + dot. Triangle apex points up.
    private static func drawErrorInterior(cx: CGFloat, cy: CGFloat, s: CGFloat, sw: CGFloat, circR: CGFloat) {
        // Apex-up triangle within the ring.
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: cx, y: cy + circR * 0.95))                 // apex (top)
        tri.line(to: NSPoint(x: cx + circR * 0.92, y: cy - circR * 0.68))  // bottom-right
        tri.line(to: NSPoint(x: cx - circR * 0.92, y: cy - circR * 0.68))  // bottom-left
        tri.close()
        tri.lineWidth = sw
        tri.lineJoinStyle = .round
        tri.stroke()

        // Exclamation bar.
        let bar = NSBezierPath()
        bar.move(to: NSPoint(x: cx, y: cy + s * 0.08))
        bar.line(to: NSPoint(x: cx, y: cy - s * 0.04))
        bar.lineWidth = sw
        bar.lineCapStyle = .round
        bar.stroke()

        // Dot.
        let dotR = sw * 0.7
        NSBezierPath(ovalIn: NSRect(
            x: cx - dotR,
            y: cy - s * 0.11 - dotR,
            width: dotR * 2,
            height: dotR * 2
        )).fill()
    }

    // MARK: - App icon (Ink-palette Dot)

    /// Full-color app icon at the requested size. Call with 512 or 1024
    /// for `NSApp.applicationIconImage`.
    static func appIcon(size: CGFloat = 512) -> NSImage {
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawInkDot(in: rect)
            return true
        }
    }

    private static let squircleRadiusRatio: CGFloat = 0.2237

    private static func drawInkDot(in rect: NSRect) {
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
        // 165° in CSS is "from top, rotating clockwise" = direction vector
        // (sin 165°, -cos 165°) ≈ (0.259, 0.966) — i.e. mostly downward, slight right.
        // In AppKit gradient coords we go from start (top-ish-left) to end (bottom-ish-right).
        let top = NSColor(red: 0x1e / 255.0, green: 0x2a / 255.0, blue: 0x3c / 255.0, alpha: 1.0)
        let bot = NSColor(red: 0x0c / 255.0, green: 0x16 / 255.0, blue: 0x26 / 255.0, alpha: 1.0)
        let bg = NSGradient(colors: [top, bot])
        // 165° in CSS ≈ 255° in AppKit NSGradient angle (AppKit uses CCW from +x).
        // Easier: draw linearly from start/end points.
        let dx = sin(165 * .pi / 180) * s
        let dy = -cos(165 * .pi / 180) * s
        bg?.draw(from: NSPoint(x: rect.midX - dx / 2, y: rect.midY + dy / 2),
                 to:   NSPoint(x: rect.midX + dx / 2, y: rect.midY - dy / 2),
                 options: [])

        // 2. Warm halo — radial gradient centered, rgba(245,235,210,0.35) → 0.12 → 0.
        let haloColor = NSColor(red: 245/255.0, green: 235/255.0, blue: 210/255.0, alpha: 1.0)
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
        let glowColor = NSColor(red: 0xf3 / 255.0, green: 0xe9 / 255.0, blue: 0xcf / 255.0, alpha: 0.55)
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
        NSColor(red: 0xf3 / 255.0, green: 0xe9 / 255.0, blue: 0xcf / 255.0, alpha: 1.0).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        ctx.restoreGState()

        // 4. Cream core — radial gradient #fdfaf1 → #f3e9cf (55%) → #d7c48e (100%).
        let core1 = NSColor(red: 0xfd / 255.0, green: 0xfa / 255.0, blue: 0xf1 / 255.0, alpha: 1.0)
        let core2 = NSColor(red: 0xf3 / 255.0, green: 0xe9 / 255.0, blue: 0xcf / 255.0, alpha: 1.0)
        let core3 = NSColor(red: 0xd7 / 255.0, green: 0xc4 / 255.0, blue: 0x8e / 255.0, alpha: 1.0)
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
        // JSX positions at left:50%, top:43% with w=0.07s, h=0.045s, blur 2px.
        // In AppKit y-up that's slightly *above* the dot center.
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

    // MARK: - State mapping helper

    /// Convenience: turn an `AppModel.State` into its glyph state.
    static func glyphState(for state: AppModel.State) -> GlyphState {
        switch state {
        case .idle:         return .idle
        case .recording:    return .recording
        case .transcribing: return .transcribing
        case .error:        return .error
        }
    }
}
