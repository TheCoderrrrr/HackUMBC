import SwiftUI

/// The brand field shared by Splash and every setup step. Stays mounted across the
/// handoff so the colour field never restarts; only the contour rings fade.
struct SetupAtmosphere: View, Animatable {
    /// 1 on splash, 0 once setup content appears.
    var contours: Double

    var animatableData: Double {
        get { contours }
        set { contours = newValue }
    }

    var body: some View {
        AtmosphereView(contours: contours)
    }
}

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
                .font(.geist(46, .semibold, relativeTo: .largeTitle))
                .tracking(-1.38)
                .foregroundStyle(Color.white)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.isHeader)
        }
        .ignoresSafeArea()
    }
}
