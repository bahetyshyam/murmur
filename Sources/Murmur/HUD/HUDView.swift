import SwiftUI

/// Content of the floating HUD pill shown during recording / transcribing.
/// Runs inside an `NSHostingView` hosted by `HUDController`.
struct HUDView: View {
    enum Mode: Equatable {
        case recording
        case transcribing
    }

    let mode: Mode
    let levelHolder: HUDController.LevelHolder

    var body: some View {
        HStack(spacing: 10) {
            indicator
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        // Subtle ring so the pill stays legible over light wallpapers.
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var indicator: some View {
        switch mode {
        case .recording:
            // Live waveform — 5 bars whose heights track the mic RMS with
            // per-bar phase offsets so you see motion even when the user
            // is pausing between words.
            WaveformBars(level: levelHolder.level)
                .frame(width: 26, height: 16)
        case .transcribing:
            ProgressView()
                .controlSize(.small)
                .progressViewStyle(.circular)
                .tint(.white)
        }
    }

    private var label: String {
        switch mode {
        case .recording:    return "Listening…"
        case .transcribing: return "Transcribing…"
        }
    }
}

/// Animated 5-bar level meter. Heights are a blend of:
/// * The live input level (0…1) — so loud speech visibly peaks.
/// * A per-bar sine modulation driven by `TimelineView(.animation)` — so
///   the bars never look frozen even during silence.
private struct WaveformBars: View {
    let level: Float

    /// Per-bar phase offsets. Five bars, each offset a fifth of a
    /// cycle; keeps neighboring bars visually distinct.
    private static let phases: [Double] = [0.0, 0.4, 0.8, 1.2, 1.6]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<Self.phases.count, id: \.self) { i in
                        let phase = Self.phases[i]
                        let height = barHeight(level: Double(level), phase: phase, t: t, maxH: geo.size.height)
                        Capsule(style: .continuous)
                            .fill(Color.white)
                            .frame(width: 2, height: height)
                            .shadow(color: .white.opacity(0.4), radius: 2, x: 0, y: 0)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    /// Blend of input level and a phase-offset sine wave so the bars have
    /// life even when nothing's being spoken. Minimum height so the bars
    /// don't collapse to invisibility in a silent room.
    private func barHeight(level: Double, phase: Double, t: TimeInterval, maxH: CGFloat) -> CGFloat {
        let speed = 6.0              // rad/sec — quick but not frantic
        let wobble = 0.5 + 0.5 * sin(phase + t * speed)         // 0…1
        let drive = max(level, 0.08)                             // idle flutter
        let normalized = min(max(drive * (0.55 + 0.45 * wobble), 0.18), 1.0)
        return CGFloat(normalized) * maxH
    }
}
