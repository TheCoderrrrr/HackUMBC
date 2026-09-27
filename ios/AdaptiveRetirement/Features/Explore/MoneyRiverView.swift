import SwiftUI

/// The money river: one month's take-home cash as fine streamlines flowing from a
/// shared source into three aligned destinations. Green reaches retirement; blue
/// reaches reserves and debt. `month` is animatable so seeks and playback glide.
struct MoneyRiverView: View {
    let timeline: ExploreTimeline
    let month: Double
    var body: some View {
        let destinations = timeline.destinations(at: Int(month.rounded()))
        VStack(spacing: 0) {
            RiverStreamlines(timeline: timeline, month: month)
                .frame(height: 190)
            HStack(alignment: .top, spacing: MoneyRiverLayout.columnSpacing) {
                ForEach(Array(destinations.enumerated()), id: \.offset) { _, destination in
                    DestinationColumn(destination: destination)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(minHeight: 56, alignment: .top)
        }
    }
}

enum MoneyRiverLayout {
    static let columnSpacing: CGFloat = 6
    /// Figma reference width for the streamline geometry.
    static let referenceWidth: CGFloat = 345

    /// Centers of the three destination columns.
    static func columnCenters(width: CGFloat) -> [CGFloat] {
        let column: CGFloat = (width - columnSpacing * 2) / 3
        let pitch: CGFloat = column + columnSpacing
        return (0..<3).map { (index: Int) -> CGFloat in column / 2 + CGFloat(index) * pitch }
    }
}

private struct DestinationColumn: View {
    let destination: RiverDestination

    var body: some View {
        VStack(spacing: 0) {
            Text(destination.title)
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textSecondary)
            WordRoll(text: destination.value)
                .font(.geist(18, .medium, relativeTo: .headline))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
            Text(destination.caption)
                .font(.geist(11, .regular, relativeTo: .caption2))
                .foregroundStyle(Palette.textCaption)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }
}

/// Canvas-drawn streamlines. Animatable on `month`, so SwiftUI interpolates seeks; a
/// gentle real-time sway keeps the river alive even when the plan holds steady.
private struct RiverStreamlines: View, Animatable {
    let timeline: ExploreTimeline
    var month: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var animatableData: Double {
        get { month }
        set { month = newValue }
    }

    private static let accent = (r: 168.0, g: 230.0, b: 161.0)
    private static let blue = (r: 127.0, g: 166.0, b: 222.0)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { clock in
            canvas(time: clock.date.timeIntervalSinceReferenceDate)
        }
        .accessibilityHidden(true)
    }

    private func canvas(time: Double) -> some View {
        Canvas { context, size in
            draw(in: &context, size: size, time: time)
        }
    }

    /// The streamline drawing, kept out of the `Canvas` closure and in one numeric type
    /// (CGFloat) so the compiler can type-check it quickly.
    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let scale: CGFloat = size.width / MoneyRiverLayout.referenceWidth
        let bottom: CGFloat = size.height * 179 / 190
        let centers: [CGFloat] = MoneyRiverLayout.columnCenters(width: size.width)

        // Hairline down the middle destination.
        var guide = Path()
        guide.move(to: CGPoint(x: centers[1], y: 0))
        guide.addLine(to: CGPoint(x: centers[1], y: bottom))
        context.stroke(guide, with: .color(Palette.textCaption.opacity(0.2)), lineWidth: 1)

        // The river is never still: its shape follows the playhead month continuously
        // (every month reads differently, not only at dated states) and sways gently in
        // real time. Reduce Motion freezes the sway; scrubbing still reshapes it.
        let m = CGFloat(month)
        let clock: CGFloat = reduceMotion ? 0 : CGFloat(time)
        let drift: CGFloat = sin(m * 0.21) * 0.6 + sin(m * 0.53 + 1.3) * 0.4
        let sway: CGFloat = sin(m * 0.37 + 0.6) + 0.35 * sin(clock * 0.9)
        let spread: CGFloat = 1 + 0.14 * sway
        let waistFraction: CGFloat = 102 / 179 + 0.045 * drift + 0.012 * sin(clock * 0.7)
        let waist: CGFloat = bottom * waistFraction
        let sourceWobble: CGFloat = 7 * sin(m * 0.29 + 2.1) + 2.5 * sin(clock * 0.55)
        let sourceShift: CGFloat = scale * sourceWobble

        let segment = timeline.segment(at: month)
        let t = CGFloat(segment.t)
        let from = Self.ends(segment.from, centers: centers, scale: scale, spread: spread)
        let to = Self.ends(segment.to, centers: centers, scale: scale, spread: spread)
        let count = ExploreTimeline.streamCount
        let sourceSpacing: CGFloat = 1.82 * scale
        let sourceStart: CGFloat = size.width / 2 + sourceShift - sourceSpacing * CGFloat(count - 1) / 2

        for i in 0..<count {
            let index = CGFloat(i)
            let x: CGFloat = from[i].x + (to[i].x - from[i].x) * t
            let warmth: CGFloat = from[i].warmth + (to[i].warmth - from[i].warmth) * t
            let source: CGFloat = sourceStart + index * sourceSpacing
            // Each stream ripples on its own phase so the braid shimmers as it moves.
            let rippleWave: CGFloat = 2.4 * sin(clock * 1.1 + index * 0.31) + 1.6 * sin(m * 0.8 + index * 0.17)
            let ripple: CGFloat = scale * rippleWave
            let mid: CGFloat = (source + x) / 2 + ripple

            var path = Path()
            path.move(to: CGPoint(x: source, y: 0))
            path.addCurve(to: CGPoint(x: mid, y: waist),
                          control1: CGPoint(x: source, y: waist * 50 / 102),
                          control2: CGPoint(x: source + ripple * 0.5, y: waist * 72 / 102))
            path.addCurve(to: CGPoint(x: x, y: bottom),
                          control1: CGPoint(x: x, y: bottom * 137 / 179),
                          control2: CGPoint(x: x, y: bottom * 154 / 179))

            let color = Self.mix(warmth)
            let gradient = Gradient(stops: [
                .init(color: color.opacity(0.08), location: 0),
                .init(color: color.opacity(0.95), location: 0.5),
                .init(color: color.opacity(0.38), location: 1)
            ])
            let top = CGPoint(x: x, y: 0)
            let base = CGPoint(x: x, y: bottom)
            context.stroke(path, with: .linearGradient(gradient, startPoint: top, endPoint: base), lineWidth: 1.2)
        }
    }


    /// Each streamline's end x and colour (0 accent … 1 blue) for a keyframe.
    private static func ends(_ keyframe: RiverKeyframe, centers: [CGFloat], scale: CGFloat,
                             spread: CGFloat) -> [(x: CGFloat, warmth: CGFloat)] {
        let spacing = 1.7 * scale * spread
        var result: [(CGFloat, CGFloat)] = []
        for (column, count) in keyframe.counts.enumerated() {
            for k in 0..<count {
                let x = centers[column] + (CGFloat(k) - CGFloat(count - 1) / 2) * spacing
                result.append((x, column == 0 ? 0 : 1))
            }
        }
        return result
    }

    /// Accent-to-blue at `t`.
    private static func mix(_ t: CGFloat) -> Color {
        let t = Double(t)
        func channel(_ a: Double, _ b: Double) -> Double { (a + (b - a) * t) / 255 }
        return Color(.sRGB,
                     red: channel(accent.r, blue.r),
                     green: channel(accent.g, blue.g),
                     blue: channel(accent.b, blue.b))
    }
}
