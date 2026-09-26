import SwiftUI
import CoreText

// MARK: - Color tokens (DESIGN.md dark palette)

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Palette {
    /// Page background.
    static let page = Color(hex: 0x101114)
    /// Sheets and raised surfaces.
    static let sheet = Color(hex: 0x191A1F)
    /// Slightly lifted fill for pressed rows / controls on sheets.
    static let raised = Color(hex: 0x22232A)

    static let textPrimary = Color(hex: 0xF3F3F5)
    static let textSecondary = Color(hex: 0xB1B3BF)
    static let textCaption = Color(hex: 0x9497A5)
    static let textQuiet = Color(hex: 0x6E7180)

    /// Links, selection, chart emphasis.
    static let accent = Color(hex: 0xA8E6A1)
    /// Primary actions.
    static let accentStrong = Color(hex: 0x2F9E5E)
    static let accentDeep = Color(hex: 0x1F6B40)
    /// Comparison series / debt.
    static let blue = Color(hex: 0x8FB8F5)
    static let blueMid = Color(hex: 0x5E8FD6)
    static let blueDeep = Color(hex: 0x2F5A96)

    static let positive = Color(hex: 0x8FD6B4)

    /// Hairline separators.
    static let hairline = Color.white.opacity(0.08)
    static let hairlineStrong = Color.white.opacity(0.14)
}

// MARK: - Typography (Geist, biased light)

enum GeistWeight: String {
    case thin = "Thin"
    case ultraLight = "UltraLight"
    case light = "Light"
    case regular = "Regular"
    case medium = "Medium"

    var postScriptName: String { "Geist-\(rawValue)" }
}

extension Font {
    /// Geist at a fixed design size that still scales with Dynamic Type.
    static func geist(_ size: CGFloat, _ weight: GeistWeight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.postScriptName, size: size, relativeTo: style)
    }

    /// Figures — balances, amounts, percentages, ages — in Geist with tabular digits so
    /// columns and ticking values stay aligned. Pair with slight negative tracking at display sizes.
    static func numeral(_ size: CGFloat, _ weight: GeistWeight = .medium, relativeTo style: Font.TextStyle = .body) -> Font {
        geist(size, weight, relativeTo: style).monospacedDigit()
    }
}

/// The type scale. Display text sits at Regular, headings at Medium, body at Light/Regular — thinner strokes read as calmer and more trustworthy.
enum TypeScale {
    /// Hero balance numerals ($35,000).
    static let hero = Font.numeral(44, .light, relativeTo: .largeTitle)
    static let heroCents = Font.numeral(20, .light, relativeTo: .title2)
    /// Splash wordmark.
    static let wordmark = Font.geist(46, .regular, relativeTo: .largeTitle)
    /// Screen titles (Plan, Explore, onboarding headings).
    static let title = Font.geist(30, .regular, relativeTo: .largeTitle)
    static let title2 = Font.geist(24, .regular, relativeTo: .title)
    /// Section headings.
    static let headline = Font.geist(17, .medium, relativeTo: .headline)
    /// Key amounts in rows.
    static let amount = Font.numeral(16, .regular, relativeTo: .body)
    static let amountLarge = Font.numeral(26, .light, relativeTo: .title)
    static let body = Font.geist(16, .light, relativeTo: .body)
    static let bodyRegular = Font.geist(16, .regular, relativeTo: .body)
    static let callout = Font.geist(15, .light, relativeTo: .callout)
    static let label = Font.geist(14, .regular, relativeTo: .subheadline)
    static let labelMedium = Font.geist(14, .medium, relativeTo: .subheadline)
    static let caption = Font.geist(12, .regular, relativeTo: .caption)
    /// Uppercase eyebrow labels.
    static let eyebrow = Font.geist(11, .medium, relativeTo: .caption2)
    static let button = Font.geist(17, .medium, relativeTo: .body)
}

enum FontRegistry {
    /// Registers bundled Geist faces once at launch.
    static func registerAll() {
        let names = ["Geist-Thin", "Geist-UltraLight", "Geist-Light", "Geist-Regular",
                     "Geist-Medium"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

// MARK: - Spacing / layout

enum Space {
    static let gutter: CGFloat = 20
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let section: CGFloat = 44
    /// Matching 80 pt navigation header below the status bar.
    static let headerHeight: CGFloat = 80
    static let tabBarClearance: CGFloat = 110
}

// MARK: - Motion

enum Motion {
    /// Figma Smart Animate curve: cubic-bezier(0.77, 0, 0.175, 1), 500 ms.
    static let smart = Animation.timingCurve(0.77, 0, 0.175, 1, duration: 0.5)
    static let smartFast = Animation.timingCurve(0.77, 0, 0.175, 1, duration: 0.35)
    /// Selection feedback, 180 ms.
    static let select = Animation.easeOut(duration: 0.18)
    /// Content reveal, 240 ms.
    static let reveal = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)
    /// Splash → setup handoff, 550 ms.
    static let handoff = Animation.timingCurve(0.65, 0, 0.35, 1, duration: 0.55)
    /// Gentle physical spring for presses / sheets.
    static let press = Animation.spring(response: 0.28, dampingFraction: 0.9)
    static let settle = Animation.spring(response: 0.45, dampingFraction: 0.92)

    /// Returns `animation` unless Reduce Motion is on, in which case a brief crossfade-friendly ease.
    static func respecting(_ reduceMotion: Bool, _ animation: Animation) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : animation
    }
}

// MARK: - Formatting

enum Money {
    private static let whole: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }()

    private static let cents: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    /// "$35,000"
    static func whole(_ cents: Int64) -> String {
        whole.string(from: NSNumber(value: Double(cents) / 100)) ?? "$0"
    }

    /// "$963.80"
    static func exact(_ value: Int64) -> String {
        cents.string(from: NSNumber(value: Double(value) / 100)) ?? "$0.00"
    }

    /// Whole-dollar string and two-digit cents, for raised-cents hero display.
    static func split(_ value: Int64) -> (dollars: String, cents: String) {
        let dollars = whole(value - value % 100)
        return (dollars, String(format: "%02lld", abs(value % 100)))
    }
}
