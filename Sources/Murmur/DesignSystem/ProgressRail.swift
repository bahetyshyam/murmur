import SwiftUI

/// Top-of-wizard progress rail: uppercased, tracked phase labels separated by
/// chevrons, with the passed/current phases filled gold and future phases
/// dimmed. Generalizes the capsule-dots idiom from the old onboarding header.
struct ProgressRail: View {
    let phases: [String]
    /// Index of the current phase (0-based).
    let current: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(phases.enumerated()), id: \.offset) { idx, label in
                Text(label.uppercased())
                    .font(Typography.railLabel())
                    .tracking(1.2)
                    .foregroundStyle(color(for: idx))
                if idx < phases.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.inkText.opacity(0.25))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current)
    }

    private func color(for idx: Int) -> Color {
        if idx == current { return .inkText }          // current — strongest
        if idx < current { return .inkAccent }         // passed — gold
        return .inkText.opacity(0.3)                    // future — dim
    }
}
