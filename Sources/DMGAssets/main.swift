import AppKit
import DesignSystemCore

// Renders Murmur's drag-to-install DMG background, and optionally the app
// iconset, both in pure code (reusing DesignSystemCore).
//
//   DMGAssets <background.png> [iconset-dir]
//
// If an iconset dir is given, writes the standard icon_NxN[@2x].png files so
// `iconutil -c icns` can build Murmur.icns (so Finder/Dock/the DMG show the
// real Ink dot instead of a generic placeholder).
//
// The image is the size of the create-dmg window (540×380 pt) rendered at 2×
// (1080×760 px) with the PNG's DPI set to 144 so Finder shows it crisp on
// Retina. The two icon "zones" (the real Murmur.app icon and the Applications
// drop target, positioned by create-dmg) are left empty so Finder's icons
// don't collide with painted art — only the headline (top) and the gold arrow
// (between the icons) are drawn.
//
// create-dmg icon positions (top-left origin, y down): Murmur.app at (140,170),
// Applications at (400,170), in a 540×380 window.

let WIDTH: CGFloat = 540
let HEIGHT: CGFloat = 380
let SCALE: CGFloat = 2

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: DMGAssets <output.png>\n".utf8))
    exit(2)
}
let outPath = CommandLine.arguments[1]

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(WIDTH * SCALE), pixelsHigh: Int(HEIGHT * SCALE),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("DMGAssets: failed to allocate bitmap\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else {
    FileHandle.standardError.write(Data("DMGAssets: no graphics context\n".utf8))
    exit(1)
}
NSGraphicsContext.current = gctx
// Draw in 540×380 point space; the 2× scale fills the 1080×760 pixel buffer.
gctx.cgContext.scaleBy(x: SCALE, y: SCALE)

// 1. Cream canvas with a faint warm vignette toward the bottom.
//    NOTE: palette is PROVISIONAL — to be replaced with a differentiated
//    (non-Wispr) scheme during the dedicated design-system pass.
Ink.cream.setFill()
NSRect(x: 0, y: 0, width: WIDTH, height: HEIGHT).fill()
if let warm = NSGradient(colors: [Ink.accentSoft.withAlphaComponent(0.0),
                                  Ink.accentSoft.withAlphaComponent(0.35)]) {
    warm.draw(in: NSRect(x: 0, y: 0, width: WIDTH, height: HEIGHT), angle: 90)
}

// 2. Headline near the top — serif, dark ink, "drag" italicized.
let headlineColor = Ink.inkTop
let serif = DSFont.serif(size: 27, weight: .semibold)
let serifItalic: NSFont = {
    let d = serif.fontDescriptor.withSymbolicTraits(.italic)
    return NSFont(descriptor: d, size: 27) ?? serif
}()
let para = NSMutableParagraphStyle()
para.alignment = .center
para.lineSpacing = 2
let headline = NSMutableAttributedString()
headline.append(NSAttributedString(string: "To install, ", attributes: [.font: serif, .foregroundColor: headlineColor, .paragraphStyle: para]))
headline.append(NSAttributedString(string: "drag", attributes: [.font: serifItalic, .foregroundColor: headlineColor, .paragraphStyle: para]))
headline.append(NSAttributedString(string: " Murmur\nto Applications", attributes: [.font: serif, .foregroundColor: headlineColor, .paragraphStyle: para]))
let headlineRect = NSRect(x: 40, y: HEIGHT - 110, width: WIDTH - 80, height: 80)
headline.draw(in: headlineRect)

// (The arrow between the icons will be a designed vector ASSET, added during
// the design-system pass — we no longer hand-draw it in code.)

NSGraphicsContext.restoreGraphicsState()

// Encode at 144 DPI (1080×760 px shown as 540×380 pt → Retina-crisp).
rep.size = NSSize(width: WIDTH, height: HEIGHT)
guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("DMGAssets: PNG encode failed\n".utf8))
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    FileHandle.standardError.write(Data("DMGAssets: wrote \(outPath) (\(Int(WIDTH*SCALE))×\(Int(HEIGHT*SCALE)) px @144dpi)\n".utf8))
} catch {
    FileHandle.standardError.write(Data("DMGAssets: write failed: \(error)\n".utf8))
    exit(1)
}

// Optional: render the app iconset for `iconutil -c icns`.
if CommandLine.arguments.count >= 3 {
    let iconsetDir = CommandLine.arguments[2]
    // (filename, pixel size) per Apple's .iconset convention.
    let entries: [(String, Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]
    for (name, px) in entries {
        guard let irep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { continue }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: irep)
        InkIcon.drawAppIcon(in: NSRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px)))
        NSGraphicsContext.restoreGraphicsState()
        if let ipng = irep.representation(using: .png, properties: [:]) {
            try? ipng.write(to: URL(fileURLWithPath: iconsetDir).appendingPathComponent(name))
        }
    }
    FileHandle.standardError.write(Data("DMGAssets: wrote iconset → \(iconsetDir)\n".utf8))
}
