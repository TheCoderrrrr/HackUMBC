import SwiftUI
import Charts

/// One line on `YearlyComparisonChart`: yearly values (index = years from today).
struct YearlySeries: Identifiable {
    enum Style {
        /// Dashed blue with a faded area: Current, or history's "Compare" run.
        case baseline
        /// Solid accent with a faded area and an endpoint dot: Adaptive, or history's "with" run.
        case primary
        /// Solid bright line with an endpoint dot, no area: the what-if being explored.
        case scenario
    }

    var id: String { name }
    let name: String
    let values: [Double]
    let style: Style
    /// Drawn faintly, e.g. a scenario line while its replacement is being calculated.
    var dimmed = false
}

/// Engine projections on a shared year axis, in the style of the Explore comparison: faded
/// unstacked areas, a dashed blue and a solid accent contour, endpoint dots. Series are not
/// stretched to full width, so a scenario that retires later runs past the others.
struct YearlyComparisonChart: View {
    let series: [YearlySeries]

    private struct Point: Identifiable {
        let id: String
        let year: Int
        let value: Double
    }

    var body: some View {
        let lastYear = Double(max(series.map { $0.values.count }.max() ?? 2, 2) - 1)
        let yMax = max(series.compactMap { $0.values.max() }.max() ?? 1, 1) * 1.04
        ZStack {
            Chart {
                ForEach(series.filter { $0.style != .scenario }) { line in
                    ForEach(points(line)) { point in
                        AreaMark(x: .value("Year", point.year), y: .value("Balance", point.value),
                                 series: .value("Series", line.name), stacking: .unstacked)
                            .interpolationMethod(.monotone)
                            .foregroundStyle(fill(line))
                    }
                }
            }
            .modifier(Axes(lastYear: lastYear, yMax: yMax))
            .fillGrain()

            Chart {
                ForEach([0.12, 0.42, 0.72], id: \.self) { y in
                    RuleMark(y: .value("Guide", y * yMax))
                        .foregroundStyle(Palette.hairline)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                ForEach(series) { line in
                    ForEach(points(line)) { point in
                        LineMark(x: .value("Year", point.year), y: .value("Balance", point.value),
                                 series: .value("Series", line.name))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(stroke(line))
                            .lineStyle(lineStyle(line))
                    }
                    if line.style != .baseline, let end = line.values.last {
                        PointMark(x: .value("Year", line.values.count - 1), y: .value("Balance", end))
                            .symbolSize(40)
                            .foregroundStyle(stroke(line))
                    }
                }
            }
            .modifier(Axes(lastYear: lastYear, yMax: yMax))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(series.map(\.name).joined(separator: ", compared with "))
    }

    private func points(_ line: YearlySeries) -> [Point] {
        line.values.enumerated().map { Point(id: "\(line.name)-\($0.offset)", year: $0.offset, value: $0.element) }
    }

    static func color(_ style: YearlySeries.Style) -> Color {
        switch style {
        case .baseline: Palette.blue
        case .primary: Palette.accent
        case .scenario: Palette.textPrimary
        }
    }

    private func stroke(_ line: YearlySeries) -> Color {
        let color = line.style == .baseline ? Palette.blue.opacity(0.9) : Self.color(line.style)
        return line.dimmed ? color.opacity(0.35) : color
    }

    private func lineStyle(_ line: YearlySeries) -> StrokeStyle {
        switch line.style {
        case .baseline: StrokeStyle(lineWidth: 1.15, lineCap: .round, dash: [3, 4])
        case .primary: StrokeStyle(lineWidth: 1.65, lineCap: .round)
        case .scenario: StrokeStyle(lineWidth: 1.8, lineCap: .round)
        }
    }

    private func fill(_ line: YearlySeries) -> LinearGradient {
        let (color, top, mid) = line.style == .baseline
            ? (Palette.blue, 0.26, 0.09)
            : (Color(hex: 0x86DB8F), 0.36, 0.14)
        return LinearGradient(stops: [
            .init(color: color.opacity(top), location: 0),
            .init(color: color.opacity(mid), location: 0.5),
            .init(color: color.opacity(0), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    private struct Axes: ViewModifier {
        let lastYear: Double
        let yMax: Double
        func body(content: Content) -> some View {
            content
                .chartXScale(domain: 0...lastYear)
                .chartYScale(domain: 0...yMax)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
        }
    }
}

/// A short line sample for legends: dashed for a baseline, solid otherwise.
struct SeriesSwatch: View {
    let color: Color
    let dashed: Bool

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 1))
            p.addLine(to: CGPoint(x: 17, y: 1))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 2] : []))
        .frame(width: 17, height: 2)
        .accessibilityHidden(true)
    }
}
