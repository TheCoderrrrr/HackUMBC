import Foundation

// Fictional demo fixtures from BACKEND.md §12 (as of 2026-09-26).
// These are display values for the saved Balanced plan. The backend owns every
// calculation; nothing here computes a recommendation.

enum Disclosure {
    static let fictional = "Fictional customer • Synthetic data • Not affiliated with or endorsed by T. Rowe Price."
    static let illustrative = "Illustrative projection"
    static let allocationLabel = "Illustrative allocation — not a specific T. Rowe Price fund"
    static let allocationCopy = "This prototype retains an illustrative target-date allocation. Your financial context changes contributions and cash priorities; it does not establish a suitable alternative portfolio."
}

enum DataMode: String {
    case saved = "Saved demo calculation"
    case live = "Live calculation"
    case lastLive = "Last live calculation"
    /// Hand-typed fixture values with no engine calculation behind them (REPORT B1).
    case preview = "Illustrative preview"
}

enum DecisionOrigin: String {
    case ai = "AI-assisted priorities"
    case rules = "Rules fallback"
    case savedAI = "Saved AI-assisted priorities"
    /// No decision produced these values; they are hand-typed fixtures (REPORT B1).
    case none = "Not calculated yet"
}

struct Debt: Identifiable, Hashable {
    let id: String
    let name: String
    let balanceCents: Int64
    let apr: Double
    let minimumCents: Int64
    let extraCents: Int64
}

struct CashPriority: Identifiable, Hashable {
    enum Kind { case retirement, debt, emergency, remaining }
    let id: String
    let kind: Kind
    let title: String
    let amountCents: Int64
}

struct ExplanationFact: Identifiable, Hashable {
    var id: String { label }
    let label: String
    let value: String
}

struct Explanation: Hashable {
    let headline: String
    let narrative: String
    let priorities: [String]
    let facts: [ExplanationFact]
    let tradeoff: String
    let checks: [(String, Bool)]

    static func == (l: Explanation, r: Explanation) -> Bool { l.headline == r.headline }
    func hash(into h: inout Hasher) { h.combine(headline) }
}

struct Profile: Identifiable, Hashable {
    let id: String
    let name: String
    let initials: String
    let subtitle: String
    let age: Int
    let retirementAge: Int
    let annualSalaryCents: Int64
    let monthlyTakeHomeCents: Int64
    let monthlyLivingCents: Int64

    // Balances
    let retirementBalanceCents: Int64
    let emergencyCashCents: Int64
    let emergencyMonths: Double
    let starterTargetMonths: Int
    let fullTargetMonths: Int
    let debts: [Debt]

    // Contributions
    let currentEmployeeRate: Double
    let adaptiveEmployeeRate: Double
    let employeeMonthlyCents: Int64
    let employerMonthlyCents: Int64
    let takeHomeCostCents: Int64
    let matchCaptured: Bool

    // Plan
    let primaryActionTitle: String
    let primaryActionDetail: String
    let primaryActionAmountCents: Int64?
    let cashPriorities: [CashPriority]
    let equityWeight: Double
    let explanation: Explanation
    let origin: DecisionOrigin
    /// Backend evaluation this profile was built from; nil for the bundled fixture.
    var evaluation: API.Evaluation? = nil

    var totalDebtCents: Int64 { debts.reduce(0) { $0 + $1.balanceCents } }
    var yearsToRetirement: Int { retirementAge - age }
}

extension Profile {
    static let morgan = Profile(
        id: "morgan", name: "Morgan", initials: "M",
        subtitle: "Competing priorities",
        age: 35, retirementAge: 67,
        annualSalaryCents: 8_400_000, monthlyTakeHomeCents: 480_000, monthlyLivingCents: 360_000,
        retirementBalanceCents: 3_500_000, emergencyCashCents: 360_000, emergencyMonths: 1.0,
        starterTargetMonths: 1, fullTargetMonths: 3,
        debts: [Debt(id: "morgan-card", name: "Credit card", balanceCents: 1_800_000, apr: 0.25,
                     minimumCents: 40_000, extraCents: 96_380)],
        currentEmployeeRate: 0.08, adaptiveEmployeeRate: 0.05,
        employeeMonthlyCents: 35_000, employerMonthlyCents: 35_000, takeHomeCostCents: 27_300,
        matchCaptured: true,
        primaryActionTitle: "Pay $963.80 extra toward your credit card",
        primaryActionDetail: "Keeps your full employer match while clearing 25% APR debt faster.",
        primaryActionAmountCents: 96_380,
        cashPriorities: [
            CashPriority(id: "ret", kind: .retirement, title: "Retirement cost", amountCents: 27_300),
            CashPriority(id: "debt", kind: .debt, title: "Additional debt payment", amountCents: 96_380),
            CashPriority(id: "emg", kind: .emergency, title: "Emergency savings", amountCents: 0),
            CashPriority(id: "rem", kind: .remaining, title: "Remaining cash", amountCents: 0)
        ],
        equityWeight: 0.90,
        explanation: Explanation(
            headline: "Match first, then the 25% card",
            narrative: "One month of expenses is already set aside, so the plan keeps your 5% contribution to capture the full employer match and sends the rest of your available cash to the credit card. At 25% APR, each extra dollar there removes more cost than it would likely earn elsewhere. Once the card is paid off, cash builds toward three months of reserves before contributions rise.",
            priorities: ["Capture employer match", "Pay down 25% APR card", "Build three-month reserve"],
            facts: [
                ExplanationFact(label: "Take-home before contribution", value: "$5,236.80"),
                ExplanationFact(label: "Living expenses", value: "$3,600.00"),
                ExplanationFact(label: "Card minimum", value: "$400.00"),
                ExplanationFact(label: "5% contribution cost after tax", value: "$273.00"),
                ExplanationFact(label: "Extra card payment", value: "$963.80")
            ],
            tradeoff: "Lowering your contribution from 8% to 5% slows retirement saving for now. The full match is preserved, so no employer money is left behind.",
            checks: [("Full employer match preserved", true), ("Living costs covered", true),
                     ("Starter reserve funded", true), ("Card minimum paid", true)]
        ),
        origin: .none
    )

    static let jordan = Profile(
        id: "jordan", name: "Jordan", initials: "J",
        subtitle: "Financially established",
        age: 35, retirementAge: 67,
        annualSalaryCents: 12_000_000, monthlyTakeHomeCents: 690_000, monthlyLivingCents: 440_000,
        retirementBalanceCents: 15_000_000, emergencyCashCents: 2_640_000, emergencyMonths: 6.0,
        starterTargetMonths: 1, fullTargetMonths: 3,
        debts: [Debt(id: "jordan-student", name: "Student loan", balanceCents: 1_500_000, apr: 0.04,
                     minimumCents: 20_000, extraCents: 0)],
        currentEmployeeRate: 0.10, adaptiveEmployeeRate: 0.10,
        employeeMonthlyCents: 100_000, employerMonthlyCents: 50_000, takeHomeCostCents: 78_000,
        matchCaptured: true,
        primaryActionTitle: "Keep contributing 10%",
        primaryActionDetail: "Reserves are full and your loan rate is low. Maintain the plan.",
        primaryActionAmountCents: nil,
        cashPriorities: [
            CashPriority(id: "ret", kind: .retirement, title: "Retirement cost", amountCents: 78_000),
            CashPriority(id: "debt", kind: .debt, title: "Additional debt payment", amountCents: 0),
            CashPriority(id: "emg", kind: .emergency, title: "Emergency savings", amountCents: 0),
            CashPriority(id: "rem", kind: .remaining, title: "Remaining cash", amountCents: 230_000)
        ],
        equityWeight: 0.90,
        explanation: Explanation(
            headline: "Maintain — nothing urgent",
            narrative: "Six months of expenses are in reserve and the only debt is a 4% student loan, so the plan keeps your 10% contribution and the loan minimum. Remaining cash stays yours to direct.",
            priorities: ["Maintain contribution", "Pay loan minimum", "Remaining cash to savings"],
            facts: [
                ExplanationFact(label: "Emergency reserve", value: "6.0 months"),
                ExplanationFact(label: "Student loan APR", value: "4%"),
                ExplanationFact(label: "Employer match", value: "Full")
            ],
            tradeoff: "Paying the 4% loan faster would reduce interest slightly but is unlikely to outpace long-term saving.",
            checks: [("Full employer match preserved", true), ("Living costs covered", true), ("Loan minimum paid", true)]
        ),
        origin: .none
    )

    static let casey = Profile(
        id: "casey", name: "Casey", initials: "C",
        subtitle: "Approaching retirement",
        age: 58, retirementAge: 65,
        annualSalaryCents: 11_000_000, monthlyTakeHomeCents: 590_000, monthlyLivingCents: 450_000,
        retirementBalanceCents: 85_000_000, emergencyCashCents: 3_600_000, emergencyMonths: 8.0,
        starterTargetMonths: 1, fullTargetMonths: 3,
        debts: [],
        currentEmployeeRate: 0.12, adaptiveEmployeeRate: 0.12,
        employeeMonthlyCents: 110_000, employerMonthlyCents: 45_833, takeHomeCostCents: 85_800,
        matchCaptured: true,
        primaryActionTitle: "Keep contributing 12%",
        primaryActionDetail: "No debt and eight months in reserve. Your plan is on course to maintain.",
        primaryActionAmountCents: nil,
        cashPriorities: [
            CashPriority(id: "ret", kind: .retirement, title: "Retirement cost", amountCents: 85_800),
            CashPriority(id: "debt", kind: .debt, title: "Additional debt payment", amountCents: 0),
            CashPriority(id: "emg", kind: .emergency, title: "Emergency savings", amountCents: 0),
            CashPriority(id: "rem", kind: .remaining, title: "Remaining cash", amountCents: 140_000)
        ],
        equityWeight: 0.605,
        explanation: Explanation(
            headline: "Maintain — seven years to go",
            narrative: "With no debt and eight months of reserves, the plan keeps your 12% contribution. The illustrative allocation is more conservative as retirement approaches.",
            priorities: ["Maintain contribution", "Hold reserves"],
            facts: [
                ExplanationFact(label: "Emergency reserve", value: "8.0 months"),
                ExplanationFact(label: "Years to retirement", value: "7"),
                ExplanationFact(label: "Illustrative equity", value: "60.5%")
            ],
            tradeoff: "A higher balance does not by itself indicate retirement adequacy.",
            checks: [("Full employer match preserved", true), ("Living costs covered", true)]
        ),
        origin: .none
    )

    /// The cash-first demonstration variant (BACKEND.md §12): Morgan's inputs with a
    /// `cash_security` planning preference and a saved, reviewed AI decision. Not in `all` —
    /// reached from the profile picker's demonstration link (REPORT B7).
    static let morganCashSecurity = Profile(
        id: "morgan-cash-security", name: "Morgan", initials: "M",
        subtitle: "Cash-first preference",
        age: 35, retirementAge: 67,
        annualSalaryCents: 8_400_000, monthlyTakeHomeCents: 480_000, monthlyLivingCents: 360_000,
        retirementBalanceCents: 3_500_000, emergencyCashCents: 360_000, emergencyMonths: 1.0,
        starterTargetMonths: 1, fullTargetMonths: 3,
        debts: [Debt(id: "morgan-card", name: "Credit card", balanceCents: 1_800_000, apr: 0.25,
                     minimumCents: 40_000, extraCents: 96_380)],
        currentEmployeeRate: 0.08, adaptiveEmployeeRate: 0.05,
        employeeMonthlyCents: 35_000, employerMonthlyCents: 35_000, takeHomeCostCents: 27_300,
        matchCaptured: true,
        primaryActionTitle: "Pay $963.80 extra toward your credit card",
        primaryActionDetail: "A saved AI decision kept the 25% APR card ahead of the full reserve, even with a cash-first preference.",
        primaryActionAmountCents: 96_380,
        cashPriorities: [
            CashPriority(id: "ret", kind: .retirement, title: "Retirement cost", amountCents: 27_300),
            CashPriority(id: "debt", kind: .debt, title: "Additional debt payment", amountCents: 96_380),
            CashPriority(id: "emg", kind: .emergency, title: "Emergency savings", amountCents: 0),
            CashPriority(id: "rem", kind: .remaining, title: "Remaining cash", amountCents: 0)
        ],
        equityWeight: 0.90,
        explanation: Explanation(
            headline: "Cash-first, but the card still wins",
            narrative: "With a cash-first preference the default order would build the full reserve before extra debt payments. The saved AI decision kept the 25% APR card ahead of the larger reserve: each extra dollar there removes more cost than the cushion is worth while the card balance lasts.",
            priorities: ["Starter reserve", "Pay down 25% APR card", "Build three-month reserve"],
            facts: [
                ExplanationFact(label: "Planning preference", value: "Cash security"),
                ExplanationFact(label: "Extra card payment", value: "$963.80")
            ],
            tradeoff: "The full three-month reserve builds later than a cash-first default would.",
            checks: [("Starter reserve funded first", true), ("Full employer match preserved", true)]
        ),
        origin: .none
    )

    static let all: [Profile] = [.morgan, .jordan, .casey]
}

// MARK: - Onboarding focus

enum Focus: String, CaseIterable, Identifiable {
    case debt, cash, retirement
    var id: String { rawValue }

    var title: String {
        switch self {
        case .debt: "Pay down debt"
        case .cash: "Build a cash buffer"
        case .retirement: "Save for retirement"
        }
    }

    var detail: String {
        switch self {
        case .debt: "See how extra payments shorten your card balance"
        case .cash: "See how much of a cushion you have today"
        case .retirement: "See what goes into your account each month"
        }
    }

    var symbol: String {
        switch self {
        case .debt: "creditcard"
        case .cash: "shield.lefthalf.filled"
        case .retirement: "leaf"
        }
    }
}

// MARK: - Illustrative projection (schematic, not engine output)

enum IllustrativeProjection {
    /// Normalised 0…1 schematic curve points, Today → age 67.
    static func adaptive(count: Int = 64) -> [Double] {
        (0..<count).map { i in
            let x = Double(i) / Double(count - 1)
            return 0.06 + 0.94 * pow(x, 1.85) * (0.9 + 0.1 * x)
        }
    }

    static func current(count: Int = 64) -> [Double] {
        (0..<count).map { i in
            let x = Double(i) / Double(count - 1)
            return 0.06 + 0.84 * pow(x, 1.7) * (0.92 + 0.08 * x)
        }
    }
}
