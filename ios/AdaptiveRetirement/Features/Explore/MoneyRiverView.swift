import SwiftUI

/// The money river: one month's take-home cash as fine streamlines flowing from a
/// shared source into three aligned destinations. Indigo reaches retirement; copper
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

/// Canvas-drawn streamlines. Animatable on `month`, so SwiftUI interpolates seeks.
private struct RiverStreamlines: View, Animatable {
    let timeline: ExploreTimeline
    var month: Double

    var animatableData: Double {
        get { month }
        set { month = newValue }
    }

    private static let lavender = (r: 169.0, g: 171.0, b: 255.0)
    private static let copper = (r: 215.0, g: 156.0, b: 127.0)

    var body: some View {
        Canvas { context, size in
            let scale = size.width / MoneyRiverLayout.referenceWidth
            let bottom = size.height * 179 / 190
            let centers = MoneyRiverLayout.columnCenters(width: size.width)

            // Hairline down the middle destination.
            var guide = Path()
            guide.move(to: CGPoint(x: centers[1], y: 0))
            guide.addLine(to: CGPoint(x: centers[1], y: bottom))
            context.stroke(guide, with: .color(Palette.textCaption.opacity(0.2)), lineWidth: 1)

            let segment = timeline.segment(at: month)
            let from = Self.ends(segment.from, centers: centers, scale: scale)
            let to = Self.ends(segment.to, centers: centers, scale: scale)
            let sourceSpacing = 1.82 * scale
            let sourceStart = size.width / 2 - sourceSpacing * CGFloat(ExploreTimeline.streamCount - 1) / 2

            for i in 0..<ExploreTimeline.streamCount {
                let t = segment.t
                let x = from[i].x + (to[i].x - from[i].x) * t
                let warmth = from[i].warmth + (to[i].warmth - from[i].warmth) * t
                let source = sourceStart + CGFloat(i) * sourceSpacing
                let mid = (source + x) / 2

                var path = Path()
                path.move(to: CGPoint(x: source, y: 0))
                path.addCurve(to: CGPoint(x: mid, y: bottom * 102 / 179),
                              control1: CGPoint(x: source, y: bottom * 50 / 179),
                              control2: CGPoint(x: source, y: bottom * 72 / 179))
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
            }
        }
        .accessibilityHidden(true)
    }

    /// Each streamline's end x and colour (0 indigo … 1 copper) for a keyframe.
    private static func ends(_ keyframe: RiverKeyframe, centers: [CGFloat], scale: CGFloat) -> [(x: CGFloat, warmth: CGFloat)] {
        let spacing = 1.7 * scale
        var result: [(CGFloat, CGFloat)] = []
        for (column, count) in keyframe.counts.enumerated() {
            for k in 0..<count {
                let x = centers[column] + (CGFloat(k) - CGFloat(count - 1) / 2) * spacing
                result.append((x, column == 0 ? 0 : 1))
            }
        }
        return result
    }

    private static func mix(_ t: CGFloat) -> Color {
        let t = Double(t)
        return Color(.sRGB,
                     red: (lavender.r + (copper.r - lavender.r) * t) / 255,
                     green: (lavender.g + (copper.g - lavender.g) * t) / 255,
                     blue: (lavender.b + (copper.b - lavender.b) * t) / 255)
    }
}
