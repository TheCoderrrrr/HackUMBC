import Foundation

/// Labels and formatters for the Funds tab and scenario history. Display only: every value
/// comes from the server response. Copy matches the desktop app (`desktop/src/views/Funds.tsx`).
enum FundCopy {
    // MARK: Numbers

    /// Expense ratio, always two decimals: 0.0009 → "0.09%".
    static func fee(_ rate: Double) -> String { String(format: "%.2f%%", rate * 100) }

    /// One decimal: 0.6 → "60.0%".
    static func pct1(_ rate: Double) -> String { String(format: "%.1f%%", rate * 100) }

    /// Signed, one decimal, with a true minus: 0.072 → "+7.2%", -0.031 → "−3.1%".
    static func signed(_ rate: Double) -> String { (rate < 0 ? "\u{2212}" : "+") + pct1(abs(rate)) }

    // MARK: Dates

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "2026-06-30" → "Jun 30, 2026". Anything unparseable is shown as sent.
    static func asOf(_ isoDate: String) -> String {
        let parts = isoDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return isoDate }
        return "\(months[parts[1] - 1]) \(parts[2]), \(parts[0])"
    }

    /// Server timestamps carry fractional seconds from Postgres, but not always.
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    /// A run's `created_at` as "Sep 27, 3:04 PM" in the device's time zone.
    static func savedAt(_ timestamp: String) -> String {
        guard let date = isoFractional.date(from: timestamp) ?? isoPlain.date(from: timestamp) else { return timestamp }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    // MARK: Inputs

    static func title(_ account: API.Funds.AccountType) -> String {
        switch account {
        case .k401: "401(k)"
        case .ira: "IRA"
        }
    }

    static func title(_ risk: API.Funds.RiskTolerance) -> String {
        switch risk {
        case .conservative: "Conservative"
        case .moderate: "Moderate"
        case .growth: "Growth"
        }
    }

    // MARK: Results

    /// Chip text, and whether the availability is actually confirmed (accent tint) or not (muted).
    static func availability(_ label: API.Funds.AvailabilityLabel) -> (text: String, confirmed: Bool) {
        switch label {
        case .inSuppliedPlanMenu: ("In your plan menu", true)
        case .researchCandidate: ("Research candidate · plan menu not confirmed", false)
        case .notConfirmedPurchasable: ("Availability not confirmed · check your brokerage", false)
        case .unrecognized: ("Availability not confirmed", false)
        }
    }

    static func exclusion(_ reason: API.Funds.ExclusionReason) -> String {
        switch reason {
        case .notInPlanMenu: "Not in your plan menu"
        case .unavailable: "Marked unavailable"
        case .incompleteFacts: "Missing verified fee or allocation data"
        case .staleFacts: "Verified data is too old to rank"
        case .notTargetDate: "Not a target-date fund"
        case .nonUSD: "Not priced in US dollars"
        case .poorHorizonFit: "Target year too far from yours"
        case .poorRiskFit: "Stock mix too far from your risk choice"
        case .unrecognized: "Didn't pass a check"
        }
    }

    /// "low" → "Low".
    static func scenarioLabel(_ label: String) -> String { label.prefix(1).uppercased() + label.dropFirst() }

    static let intro = "Up to three target-date funds from a small catalog verified against SEC filings. Every number shows its source and date. This is not investment advice."
}
