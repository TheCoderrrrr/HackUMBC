import SwiftUI

/// Centered white wordmark. Tapping anywhere on the splash skips the preview hold.
struct SplashWordmark: View {
    let onTap: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .accessibilityHidden(true)

            Text("Adaptive")
                .font(.geist(46, .regular, relativeTo: .largeTitle))
                .tracking(-1.38)
                .foregroundStyle(Color.white)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.isHeader)
        }
        .ignoresSafeArea()
    }
}
