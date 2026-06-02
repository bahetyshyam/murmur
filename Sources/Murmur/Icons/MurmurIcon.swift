import AppKit
import DesignSystemCore

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
        // Rasterize eagerly via lockFocus rather than the lazy
        // `NSImage(size:flipped:drawingHandler:)` form. The lazy handler is
        // invoked by AppKit at display time on a context we don't control;
        // an eagerly-drawn bitmap is a concrete image the status bar can
        // always render, which is more robust for a menubar template image.
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        drawMenubarGlyph(state: state, in: NSRect(x: 0, y: 0, width: size, height: size))
        image.unlockFocus()
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
    /// for `NSApp.applicationIconImage`. Drawing lives in
    /// `DesignSystemCore.InkIcon` so the build-time `.icns` generator shares it.
    static func appIcon(size: CGFloat = 512) -> NSImage {
        InkIcon.appIcon(size: size)
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
