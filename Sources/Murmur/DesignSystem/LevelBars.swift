import SwiftUI
import Observation

/// Observable mic-level mirror, mutated on the main queue by `Recorder.onLevel`
/// (throttled to ~30 Hz). Shared by the recording HUD (`HUDController`) and the
/// onboarding mic-test step so a SwiftUI meter re-renders without its own timer.
/// Non-isolated (like the value it replaced) — the Recorder callback already
/// hops to the main actor before mutating `level`.
@Observable
final class MicLevelHolder {
    var level: Float = 0
}

/// Animated level meter — a row of bars whose heights blend the live input
/// level with a per-bar sine wobble so they stay alive during silence.
///
/// Generalized from the HUD's former private `WaveformBars`. With the defaults
/// (`barCount: 5`, `tint: .white`, `barWidth: 2`, `spacing: 2`) it reproduces
/// the old HUD meter exactly; the onboarding mic test uses more, wider, gold
/// bars over a fuller width.
struct LevelBars: View {
    var level: Float
    var barCount: Int = 5
    var tint: Color = .white
    var barWidth: CGFloat = 2
    var spacing: CGFloat = 2

    /// Per-bar phase offsets spread across a 2.0-rad cycle — the original used
    /// `[0, 0.4, 0.8, 1.2, 1.6]` for 5 bars, i.e. `i * (2.0 / barCount)`.
    private var phases: [Double] {
        (0..<barCount).map { Double($0) * (2.0 / Double(barCount)) }
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { i in
                        let phase = phases[i]
                        let height = barHeight(level: Double(level), phase: phase, t: t, maxH: geo.size.height)
                        Capsule(style: .continuous)
                            .fill(tint)
                            .frame(width: barWidth, height: height)
                            .shadow(color: tint.opacity(0.4), radius: 2, x: 0, y: 0)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    /// Blend of input level and a phase-offset sine wave so the bars have life
    /// even in silence. Verbatim from the original HUD meter.
    private func barHeight(level: Double, phase: Double, t: TimeInterval, maxH: CGFloat) -> CGFloat {
        let speed = 6.0              // rad/sec — quick but not frantic
        let wobble = 0.5 + 0.5 * sin(phase + t * speed)         // 0…1
        let drive = max(level, 0.08)                             // idle flutter
        let normalized = min(max(drive * (0.55 + 0.45 * wobble), 0.18), 1.0)
        return CGFloat(normalized) * maxH
    }
}
