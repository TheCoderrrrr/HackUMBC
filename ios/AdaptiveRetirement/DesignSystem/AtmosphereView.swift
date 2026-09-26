import SwiftUI

/// The living brand field behind Splash and Onboarding.
///
/// Drifts, morphs and slowly shifts hue; contour rings are derived from the same
/// warped field so they breathe with the glow. Frozen under Reduce Motion.
/// Never intercepts touches and is hidden from VoiceOver.
struct AtmosphereView: View {
    /// 0…1 — contour ring layer (1 on splash, 0 on setup).
    var contours: Double = 1
    /// 0…1 — colour field intensity.
    var glow: Double = 1
    /// 0…1 — grain amount.
    var grain: Double = 1
    /// Seconds per real second. Kept low: the motion should be felt more than seen.
    var speed: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var start = Date()

    /// A pleasant, already-composed moment for the static fallback.
    private static let restingTime: Double = 38

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let t = reduceMotion ? Self.restingTime : Self.restingTime + elapsed * speed
            GeometryReader { proxy in
                Rectangle()
                    .fill(Palette.page)
                    .colorEffect(
                        ShaderLibrary.adaptiveAtmosphere(
                            .float2(proxy.size),
                            .float(Float(t)),
                            .float(Float(contours)),
                            .float(Float(glow)),
                            .float(Float(grain)),
                            .float(Float(displayScale))
                        )
                    )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Applies the chart/texture duotone grain to any filled shape.
struct FillGrain: ViewModifier {
    var amount: Double = 1
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content.colorEffect(ShaderLibrary.fillGrain(.float(Float(amount)), .float(Float(displayScale))))
    }
}

extension View {
    func fillGrain(_ amount: Double = 1) -> some View { modifier(FillGrain(amount: amount)) }
}

/// The frosted charcoal glass used across setup: 68% charcoal over the field,
/// or an opaque surface under Reduce Transparency.
struct FrostedSetupSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Palette.page
            } else {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                    Palette.page.opacity(0.68)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Splash field") {
    ZStack {
        AtmosphereView()
        Text("Adaptive").font(TypeScale.wordmark).foregroundStyle(.white)
    }
    .onAppear(perform: FontRegistry.registerAll)
}
