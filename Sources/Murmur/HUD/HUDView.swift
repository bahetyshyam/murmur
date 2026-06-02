import SwiftUI

/// Content of the floating HUD pill shown during recording / transcribing.
/// Runs inside an `NSHostingView` hosted by `HUDController`.
struct HUDView: View {
    enum Mode: Equatable {
        case recording
        case transcribing
    }

    let mode: Mode
    let levelHolder: MicLevelHolder

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
            // is pausing between words. Shared `LevelBars` (DesignSystem) with
            // the original HUD parameters → identical to the former inline meter.
            LevelBars(level: levelHolder.level, barCount: 5, tint: .white, barWidth: 2, spacing: 2)
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
