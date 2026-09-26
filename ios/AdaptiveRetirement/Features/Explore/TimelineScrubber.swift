import SwiftUI

/// Video-editor-style dated timeline: a month ruler, retirement / debt / reserve
/// tracks, and a playhead that follows the finger. Taps seek with easing; drags
/// scrub directly. VoiceOver adjusts one month at a time.
struct TimelineScrubber: View {
    let timeline: ExploreTimeline
    @Binding var month: Double
    /// Called when the user starts interacting (pauses playback, dismisses the hint).
    var onInteract: () -> Void = {}
    /// Called for a discrete seek so the parent can animate it.
    var onSeek: (Int) -> Void

    @State private var isDragging = false

    private static let trackTops: [CGFloat] = [28, 54, 80]
    private static let trackHeight: CGFloat = 18
    private static let height: CGFloat = 108

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 25)
                ForEach(["Retirement", "Debt", "Reserves"], id: \.self) { label in
                    Text(label)
                        .font(.geist(11, .regular, relativeTo: .caption2))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(height: 26, alignment: .leading)
                }
            }
            .frame(width: 62, alignment: .leading)
            .accessibilityHidden(true)

            GeometryReader { proxy in
                tracks(width: proxy.size.width)
            }
            .frame(height: Self.height)
        }
    }

    // MARK: Tracks

    private func x(_ month: Double, _ width: CGFloat) -> CGFloat {
        width * CGFloat(month / Double(timeline.lastMonth))
    }

    private func tracks(width: CGFloat) -> some View {
        let last = Double(timeline.lastMonth)
        return ZStack(alignment: .topLeading) {
            // Year labels.
            yearLabel(ExploreTimeline.label(forMonth: 0), at: 0, width: width, anchor: .leading)
            yearLabel("\(ExploreTimeline.startYear + 2)", at: x(24, width), width: width, anchor: .center)
            yearLabel(ExploreTimeline.label(forMonth: timeline.lastMonth), at: width, width: width, anchor: .trailing)

            // Month ruler: a tick every quarter, taller each year.
            ForEach(Array(stride(from: 0, through: timeline.lastMonth, by: 3)), id: \.self) { m in
                Rectangle()
                    .fill(Palette.textCaption)
                    .frame(width: 1, height: m % 12 == 0 ? 7 : 4)
                    .offset(x: x(Double(m), width) - (m == timeline.lastMonth ? 1 : 0), y: 19)
            }

            // Track wells.
            ForEach(Self.trackTops, id: \.self) { top in
                bar(from: 0, to: last, top: top, width: width, fill: Palette.sheet)
            }

            // Retirement: baseline all the way, brighter after the increase.
            bar(from: 0, to: last, top: Self.trackTops[0], width: width, fill: Palette.lavender.opacity(0.33))
            if let increase = timeline.tracks.retirementIncreaseFrom {
                bar(from: Double(increase), to: last, top: Self.trackTops[0], width: width,
                    fill: Palette.lavender.opacity(0.75))
            }
            if let debt = timeline.tracks.debtPayoff {
                bar(from: Double(debt.lowerBound), to: Double(debt.upperBound), top: Self.trackTops[1],
                    width: width, fill: Color(hex: 0xD79C7F, opacity: 0.7))
            }
            if let reserve = timeline.tracks.reserveFunding {
                bar(from: Double(reserve.lowerBound), to: Double(reserve.upperBound), top: Self.trackTops[2],
                    width: width, fill: Palette.textSecondary.opacity(0.5))
            }

            Playhead()
                .offset(x: x(month, width) - 5, y: 12)
        }
        .frame(width: width, height: Self.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(scrub(width: width))
        .sensoryFeedback(.selection, trigger: timeline.milestone(at: Int(month.rounded()))?.month)
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Swipe up or down to move one month.")
        .accessibilityAdjustableAction { direction in
            let current = Int(month.rounded())
            switch direction {
            case .increment: onSeek(min(current + 1, timeline.lastMonth))
            case .decrement: onSeek(max(current - 1, 0))
            @unknown default: break
            }
        }
    }

    private func bar(from: Double, to: Double, top: CGFloat, width: CGFloat, fill: some ShapeStyle) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fill)
            .frame(width: max(x(to, width) - x(from, width), 0), height: Self.trackHeight)
            .offset(x: x(from, width), y: top)
    }

    @ViewBuilder
    private func yearLabel(_ text: String, at position: CGFloat, width: CGFloat, anchor: LabelAnchor) -> some View {
        let label = Text(text)
            .font(.geist(11, .regular, relativeTo: .caption2))
            .foregroundStyle(Palette.textSecondary)
            .fixedSize()
        switch anchor {
        case .leading: label
        case .trailing: label.frame(width: width, alignment: .trailing)
        case .center: label.frame(width: 0).offset(x: position)
        }
    }

    // MARK: Gesture

    private func scrub(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    guard abs(value.translation.width) > 4 else { return }
                    isDragging = true
                    onInteract()
                }
                month = clampedMonth(value.location.x, width)
            }
            .onEnded { value in
                if isDragging {
                    isDragging = false
                    onSeek(Int(clampedMonth(value.location.x, width).rounded()))
                } else {
                    onInteract()
                    onSeek(Int(clampedMonth(value.location.x, width).rounded()))
                }
            }
    }

    private func clampedMonth(_ x: CGFloat, _ width: CGFloat) -> Double {
        min(max(Double(x / width) * Double(timeline.lastMonth), 0), Double(timeline.lastMonth))
    }

    private var accessibilityValue: String {
        let m = Int(month.rounded())
        let date = ExploreTimeline.spokenLabel(forMonth: m)
        return timeline.milestone(at: m).map { "\(date), \($0.title)" } ?? date
    }
}

/// White playhead: a pentagon grip over a hairline.
private struct Playhead: View {
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Palette.textPrimary)
                .frame(width: 1, height: 91)
                .offset(y: 6)
            GripShape()
                .fill(Palette.textPrimary)
                .frame(width: 10, height: 11)
        }
        .frame(width: 10, height: 99, alignment: .top)
        .allowsHitTesting(false)
    }
}

private struct GripShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 6 / 11))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.height * 6 / 11))
        p.closeSubpath()
        return p
    }
}

private enum LabelAnchor { case leading, center, trailing }
