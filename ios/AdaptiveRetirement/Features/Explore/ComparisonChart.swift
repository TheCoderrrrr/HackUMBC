import SwiftUI
import Charts

/// Schematic Current vs Adaptive comparison: overlapping (unstacked) translucent
/// areas fading to the baseline, a dashed peach contour, a solid lavender contour,
/// and an endpoint dot. Normalised illustrative values only.
struct ComparisonChart: View {
    var adaptive: [Double] = IllustrativeProjection.adaptive()
    var current: [Double] = IllustrativeProjection.current()

    private struct Point: Identifiable {
        let id: Int
        let x: Double
        let y: Double
        let series: String
    }

    var body: some View {
        let yMax = max(adaptive.max() ?? 1, current.max() ?? 1) * 1.04
        ZStack {
            Chart(points) { point in
                AreaMark(x: .value("Progress", point.x), y: .value("Balance", point.y),
                         stacking: .unstacked)
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(by: .value("Series", point.series))
            }
            .chartForegroundStyleScale(domain: ["Current", "Adaptive"],
                                       range: [fade(Palette.peach, top: 0.26, mid: 0.09),
                                               fade(Color(hex: 0x9396F5), top: 0.36, mid: 0.14)])
            .modifier(Axes(yMax: yMax))
            .fillGrain()

            Chart {
                ForEach([0.12, 0.42, 0.72], id: \.self) { y in
                    RuleMark(y: .value("Guide", y * yMax))
                        .foregroundStyle(Palette.hairline)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                ForEach(points) { point in
                    LineMark(x: .value("Progress", point.x), y: .value("Balance", point.y))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(by: .value("Series", point.series))
                        .lineStyle(point.series == "Current"
                                   ? StrokeStyle(lineWidth: 1.15, lineCap: .round, dash: [3, 4])
                                   : StrokeStyle(lineWidth: 1.65, lineCap: .round))
                }
                if let end = adaptive.last {
                    PointMark(x: .value("Progress", 1.0), y: .value("Balance", end))
                        .symbolSize(40)
                        .foregroundStyle(Palette.lavender)
                }
            }
            .chartForegroundStyleScale(domain: ["Current", "Adaptive"],
                                       range: [Palette.peach.opacity(0.9), Palette.lavender])
            .modifier(Axes(yMax: yMax))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Disclosure.illustrative): Adaptive, solid line, compared with Current, dashed line")
    }

    private var points: [Point] {
        func series(_ values: [Double], _ name: String, offset: Int) -> [Point] {
            let last = Double(max(values.count - 1, 1))
            return values.enumerated().map {
                Point(id: offset + $0.offset, x: Double($0.offset) / last, y: $0.element, series: name)
            }
        }
        return series(current, "Current", offset: 0) + series(adaptive, "Adaptive", offset: 10_000)
    }

    private func fade(_ color: Color, top: Double, mid: Double) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: color.opacity(top), location: 0),
            .init(color: color.opacity(mid), location: 0.5),
            .init(color: color.opacity(0), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    private struct Axes: ViewModifier {
        let yMax: Double
        func body(content: Content) -> some View {
            content
                .chartXScale(domain: 0...1)
                .chartYScale(domain: 0...yMax)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
        }
    }
}
