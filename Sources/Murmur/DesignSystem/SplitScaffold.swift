import SwiftUI

/// The wizard's left-content / right-illustration split, on the Ink canvas.
/// Generic over the two columns so each onboarding step supplies its own
/// content (left) and illustration (right). Left ≈ 58%, right ≈ 42%, matching
/// the Wispr reference proportions.
@MainActor
struct WizardShell<Content: View, Illustration: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var illustration: () -> Illustration

    var body: some View {
        HStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 40)
                .padding(.vertical, 36)
                .layoutPriority(1)

            illustration()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.inkSurface)
        }
        .background(Color.inkCanvas)
    }
}
