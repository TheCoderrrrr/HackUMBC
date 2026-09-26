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
        let column = (width - columnSpacing * 2) / 3
        return (0..<3).map { column / 2 + CGFloat($0) * (column + columnSpacing) }
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
/// continuous downstream pulse keeps the river flowing even when the plan holds steady.
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

    /// Downstream pulse: length and gap along each path, in points, and speed in points/second.
    private static let pulseLength: CGFloat = 22
    private static let pulseGap: CGFloat = 150
    private static let pulseSpeed: Double = 46

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { clock in
            canvas(time: clock.date.timeIntervalSinceReferenceDate)
        }
        .accessibilityHidden(true)
    }

    private func canvas(time: Double) -> some View {
        Canvas { context, size in
            let scale = size.width / MoneyRiverLayout.referenceWidth
            let bottom = size.height * 179 / 190
            let centers = MoneyRiverLayout.columnCenters(width: size.width)

            // Hairline down the middle destination.
            var guide = Path()
            guide.move(to: CGPoint(x: centers[1], y: 0))
            guide.addLine(to: CGPoint(x: centers[1], y: bottom))
            context.stroke(guide, with: .color(Palette.textCaption.opacity(0.2)), lineWidth: 1)

            // The river is never still: its shape follows the playhead month continuously
            // (every month reads differently, not only at dated states) and sways gently in
            // real time. Reduce Motion freezes the sway; scrubbing still reshapes it.
            let clock = reduceMotion ? 0 : time
            let drift = sin(month * 0.21) * 0.6 + sin(month * 0.53 + 1.3) * 0.4
            let spread = 1 + 0.14 * CGFloat(sin(month * 0.37 + 0.6) + 0.35 * sin(clock * 0.9))
            let waist = bottom * (102 / 179 + 0.045 * CGFloat(drift) + 0.012 * CGFloat(sin(clock * 0.7)))
            let sourceShift = scale * CGFloat(7 * sin(month * 0.29 + 2.1) + 2.5 * sin(clock * 0.55))

            let segment = timeline.segment(at: month)
            let from = Self.ends(segment.from, centers: centers, scale: scale, spread: spread)
            let to = Self.ends(segment.to, centers: centers, scale: scale, spread: spread)
            let sourceSpacing = 1.82 * scale
            let sourceStart = size.width / 2 + sourceShift - sourceSpacing * CGFloat(ExploreTimeline.streamCount - 1) / 2

            for i in 0..<ExploreTimeline.streamCount {
                let t = segment.t
                let x = from[i].x + (to[i].x - from[i].x) * t
                let warmth = from[i].warmth + (to[i].warmth - from[i].warmth) * t
                let source = sourceStart + CGFloat(i) * sourceSpacing
                // Each stream ripples on its own phase so the braid shimmers as it moves.
                let ripple = scale * CGFloat(2.4 * sin(clock * 1.1 + Double(i) * 0.31)
                                             + 1.6 * sin(month * 0.8 + Double(i) * 0.17))
                let mid = (source + x) / 2 + ripple

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
                context.stroke(path,
                               with: .linearGradient(gradient, startPoint: CGPoint(x: x, y: 0),
                                                     endPoint: CGPoint(x: x, y: bottom)),
                               lineWidth: 1.2)

                guard !reduceMotion else { continue }
                // Each stream's pulse is offset by the golden ratio so they never march in step.
                let period = Double(Self.pulseLength + Self.pulseGap)
                let offset = Double(i) * 0.618_034 * period
                let phase = (time * Self.pulseSpeed + offset).truncatingRemainder(dividingBy: period)
                let lifted = Self.mix(warmth, lift: 0.45)
                let glow = Gradient(stops: [
                    .init(color: lifted.opacity(0.1), location: 0),
                    .init(color: lifted.opacity(0.9), location: 0.5),
                    .init(color: lifted.opacity(0.45), location: 1)
                ])
                context.stroke(path,
                               with: .linearGradient(glow, startPoint: CGPoint(x: x, y: 0),
                                                     endPoint: CGPoint(x: x, y: bottom)),
                               style: StrokeStyle(lineWidth: 1.4, lineCap: .round,
                                                  dash: [Self.pulseLength, Self.pulseGap],
                                                  dashPhase: -CGFloat(phase)))
            }
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

    /// Accent-to-blue at `t`, optionally lifted toward white by `lift` (for the pulse).
    private static func mix(_ t: CGFloat, lift: Double = 0) -> Color {
        let t = Double(t)
        func channel(_ a: Double, _ b: Double) -> Double {
            let base = a + (b - a) * t
            return (base + (255 - base) * lift) / 255
        }
        return Color(.sRGB,
                     red: channel(accent.r, blue.r),
                     green: channel(accent.g, blue.g),
                     blue: channel(accent.b, blue.b))
    }
}
