import SwiftUI
import Charts

/// Layered translucent area chart for schematic projections (Swift Charts).
///
/// `adaptive` draws a lavender area with a solid contour; the optional `comparison`
/// draws a muted-peach area with a dashed contour. The series overlap — they are
/// alternative scenario totals, not a stack. Both fills fade to transparent at the
/// baseline and carry the fine duotone grain; contours and the marker stay crisp.
///
/// Values are normalised 0…1 and evenly spaced from start to end (see
/// `IllustrativeProjection`). Nothing here implies engine output.
struct ProjectionChart: View {
    var adaptive: [Double]
    var comparison: [Double]? = nil
    /// Optional 0…1 playhead position: a hairline rule with a dot on the adaptive series.
    var marker: Double? = nil
    /// Labels spread evenly under the chart (e.g. "Today", "2058 · Age 67"). Empty hides the axis row.
    var axisLabels: [String] = []
    var adaptiveName = "Adaptive plan"
    var comparisonName = "Current plan"
    var lineWidth: CGFloat = 1.3

    var body: some View {
        VStack(spacing: Space.s) {
            ZStack {
                // Fills: grained, fading into the page.
                chart { series, name, _ in
                    AreaMark(x: .value("Progress", series.x), y: .value("Balance", series.y))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(by: .value("Series", name))
                }
                .chartForegroundStyleScale(domain: seriesNames, range: fills)
                .fillGrain()

                // Contours and marker: crisp.
                chart { series, name, dashed in
                    LineMark(x: .value("Progress", series.x), y: .value("Balance", series.y))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(by: .value("Series", name))
                        .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round,
                                               dash: dashed ? [4, 3] : []))
                }
                .chartForegroundStyleScale(domain: seriesNames, range: strokes)
                .chartOverlay { proxy in markerOverlay(proxy) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)

            if !axisLabels.isEmpty {
                HStack {
                    ForEach(Array(axisLabels.enumerated()), id: \.offset) { index, label in
                        if index > 0 { Spacer(minLength: 0) }
                        Text(label)
                            .font(.geist(12, .regular, relativeTo: .caption))
                            .foregroundStyle(Palette.textCaption)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: Chart plumbing

    private struct Point: Identifiable {
        let id: Int
        let x: Double
        let y: Double
    }

    private var seriesNames: [String] {
        comparison == nil ? [adaptiveName] : [comparisonName, adaptiveName]
    }

    private var fills: [LinearGradient] {
        let adaptive = fade(Color(hex: 0x9396F5), top: 0.40, mid: 0.16)
        return comparison == nil ? [adaptive] : [fade(Palette.peach, top: 0.28, mid: 0.10), adaptive]
    }

    private var strokes: [Color] {
        comparison == nil ? [Palette.lavender] : [Palette.peach.opacity(0.9), Palette.lavender]
    }

    /// Builds one chart over both series with the shared, hidden axes.
    private func chart<Content: ChartContent>(
        @ChartContentBuilder _ mark: @escaping (Point, String, Bool) -> Content
    ) -> some View {
        Chart {
            if let comparison {
                ForEach(points(comparison)) { mark($0, comparisonName, true) }
            }
            ForEach(points(adaptive)) { mark($0, adaptiveName, false) }
        }
        .chartXScale(domain: 0...1)
        .chartYScale(domain: 0...yMax)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { $0.frame(maxWidth: .infinity, maxHeight: .infinity) }
    }

    @ViewBuilder
    private func markerOverlay(_ proxy: ChartProxy) -> some View {
        if let marker, let x = proxy.position(forX: min(max(marker, 0), 1)),
           let y = proxy.position(forY: Self.sample(adaptive, at: marker)) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Palette.textPrimary.opacity(0.35))
                        .frame(width: 1, height: geo.size.height)
                        .position(x: x, y: geo.size.height / 2)
                    Circle()
                        .fill(Palette.lavender)
                        .overlay(Circle().strokeBorder(Palette.page, lineWidth: 2))
                        .frame(width: 10, height: 10)
                        .position(x: x, y: y)
                }
            }
        }
    }

    private var yMax: Double {
        max(adaptive.max() ?? 1, comparison?.max() ?? 0, 0.0001) * 1.02
    }

    private func points(_ values: [Double]) -> [Point] {
        let last = Double(max(values.count - 1, 1))
        return values.enumerated().map { Point(id: $0.offset, x: Double($0.offset) / last, y: $0.element) }
    }

    private func fade(_ color: Color, top: Double, mid: Double) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: color.opacity(top), location: 0),
            .init(color: color.opacity(mid), location: 0.5),
            .init(color: color.opacity(0), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    private var accessibilitySummary: String {
        comparison == nil
            ? "\(Disclosure.illustrative): \(adaptiveName) rising over time"
            : "\(Disclosure.illustrative): \(adaptiveName), solid line, compared with \(comparisonName), dashed line"
    }

    /// Linear interpolation of an evenly spaced normalised series at x ∈ 0…1.
    static func sample(_ values: [Double], at x: Double) -> Double {
        guard values.count > 1 else { return values.first ?? 0 }
        let p = min(max(x, 0), 1) * Double(values.count - 1)
        let i = min(Int(p), values.count - 2)
        return values[i] + (values[i + 1] - values[i]) * (p - Double(i))
    }
}

#Preview {
    ProjectionChart(adaptive: IllustrativeProjection.adaptive(),
                    comparison: IllustrativeProjection.current(),
                    marker: 0.4,
                    axisLabels: ["Today", "Age 67"])
        .frame(height: 220)
        .padding()
        .background(Palette.page)
}
