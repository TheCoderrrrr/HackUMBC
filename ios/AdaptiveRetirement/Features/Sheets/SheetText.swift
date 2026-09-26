import SwiftUI

/// Prose with Medium-weight numeric runs, marked with `**`:
/// `"Your **5%** contribution adds **$350**."`
struct EmphasizedText: View {
    let source: String
    var size: CGFloat = 16
    var weight: GeistWeight = .regular
    var emphasis: GeistWeight = .medium
    var style: Font.TextStyle = .body
    var color: Color = Palette.textSecondary
    var lineSpacing: CGFloat = 0

    init(_ source: String, size: CGFloat = 16, weight: GeistWeight = .regular, emphasis: GeistWeight = .medium,
         style: Font.TextStyle = .body, color: Color = Palette.textSecondary, lineSpacing: CGFloat = 0) {
        self.source = source
        self.size = size
        self.weight = weight
        self.emphasis = emphasis
        self.style = style
        self.color = color
        self.lineSpacing = lineSpacing
    }

    var body: some View {
        Text(attributed)
            .foregroundStyle(color)
            .lineSpacing(lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for (index, part) in source.components(separatedBy: "**").enumerated() {
            var run = AttributedString(part)
            run.font = .geist(size, index.isMultiple(of: 2) ? weight : emphasis, relativeTo: style)
            result += run
        }
        return result
    }
}

/// Section title inside a sheet ("The tradeoff", "Supporting inputs").
struct SheetSectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.geist(20, .semibold, relativeTo: .title3))
            .foregroundStyle(Palette.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A 36 pt input row: Regular secondary label, SemiBold value with an optional Medium unit.
struct InputRow: View {
    let label: String
    let value: String
    var unit: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text(label)
                .font(.geist(15, .regular, relativeTo: .subheadline))
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: Space.m)
            Text(valueText)
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }

    private var valueText: AttributedString {
        var result = AttributedString(value)
        result.font = .geist(16, .semibold, relativeTo: .body)
        if let unit {
            var suffix = AttributedString(" \(unit)")
            suffix.font = .geist(16, .medium, relativeTo: .body)
            result += suffix
        }
        return result
    }
}

/// Small muted source / date caption.
struct SourceCaption: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines, id: \.self) { line in
                EmphasizedText(line, size: 12, style: .caption, color: Palette.textCaption, lineSpacing: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum SheetCopy {
    /// Fixture as-of date (BACKEND.md §12).
    static let asOf = "As of September **26, 2026**"

    static func source(_ profile: Profile) -> String {
        "Source: synthetic \(profile.name) fixture"
    }

    /// 0.25 → "25%", 0.605 → "60.5%".
    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0...1)))
    }

    static func months(_ value: Double) -> String {
        let count = value.formatted(.number.precision(.fractionLength(0...1)))
        return value == 1 ? "\(count) month" : "\(count) months"
    }
}

/// Primary action pinned under a sheet's scrolling content.
struct SheetFooterAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Space.xl)
            .padding(.vertical, 14)
            .background(Palette.sheet)
    }
}
