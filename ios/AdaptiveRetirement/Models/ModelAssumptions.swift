import Foundation

// Illustrative nominal assumptions from BACKEND.md §10–11. Display values only:
// the backend owns the simulation that uses them.

struct GlidePathAnchor: Hashable {
    let yearsToRetirement: Int
    let equityWeight: Double
}

struct ModelAssumptions {
    let annualEquityReturn: Double
    let annualBondReturn: Double
    let annualCashReturn: Double
    let annualInflation: Double
    let annualSalaryGrowth: Double
    let annualLivingCostGrowth: Double
    let annualEmployeeLimitGrowth: Double
    let highInterestAPRThreshold: Double
    let retirementTotalSavingTarget: Double
    let criticalReserveCapCents: Int64
    let starterReserveMonths: Int
    let fullReserveMonths: Int
    let returnsNetOfFees: Bool
    let glidePath: [GlidePathAnchor]
    let limitations: [String]

    static let illustrative = ModelAssumptions(
        annualEquityReturn: 0.06,
        annualBondReturn: 0.03,
        annualCashReturn: 0.0,
        annualInflation: 0.025,
        annualSalaryGrowth: 0.025,
        annualLivingCostGrowth: 0.025,
        annualEmployeeLimitGrowth: 0.025,
        highInterestAPRThreshold: 0.10,
        retirementTotalSavingTarget: 0.15,
        criticalReserveCapCents: 100_000,
        starterReserveMonths: 1,
        fullReserveMonths: 3,
        returnsNetOfFees: true,
        glidePath: [
            GlidePathAnchor(yearsToRetirement: 30, equityWeight: 0.90),
            GlidePathAnchor(yearsToRetirement: 20, equityWeight: 0.80),
            GlidePathAnchor(yearsToRetirement: 10, equityWeight: 0.65),
            GlidePathAnchor(yearsToRetirement: 0, equityWeight: 0.50)
        ],
        limitations: [
            "These are illustrative nominal assumptions, not sponsor forecasts.",
            "No market volatility, changing tax brackets, withdrawal taxes, or retirement spending.",
            "Card APRs and minimum payments stay fixed until payoff, with no new borrowing.",
            "Future contribution-limit indexing is an assumption, not future law."
        ]
    )
}
