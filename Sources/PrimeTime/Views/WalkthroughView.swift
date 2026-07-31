import SwiftUI
import PrimeTimeCore

/// The interactive walkthrough of the label model (issue #93, step 2 of the
/// onboarding sequence). This file is a placeholder: the two variant branches
/// (scrollable story vs paged steps) replace this view's body. The stable
/// contract they build against:
///
/// - `walkthrough` — the shared `WalkthroughModel`: the demo week, the
///   group-by key, the schema-smell toggles, aggregation, and colours. One
///   continuous dataset across every step of the tour.
/// - `onBack` — return to the Welcome step.
/// - `onContinue` — leave the walkthrough (finished *or* skipped) and move on
///   to the starter label sets step.
struct WalkthroughView: View {
    @Bindable var walkthrough: WalkthroughModel
    var onBack: () -> Void
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("The interactive tour lands here")
                    .font(.title2.weight(.semibold))
                Text("Watch labels aggregate into charts, break them with schema smells, and heal them again — coming from the variant branches.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Spacer()
            Divider()
            OnboardingFooter(back: onBack, primaryTitle: "Continue",
                             primaryAction: onContinue) {
                Button("Skip Tour", action: onContinue)
            }
        }
    }
}
