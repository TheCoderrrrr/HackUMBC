import Foundation

/// Shared API contract (`contracts/openapi.json`, FRONTEND.md §6).
/// Money is integer cents (Int64); rates are fractions (0.05 == 5%).
/// Keys are mapped explicitly: a snake-case decoding strategy would also rename
/// dictionary keys such as `Reason.facts` and `FinancialProfile.provenance`.
enum API {
    static let schemaVersion = "1"

    // MARK: Scalars

    /// A JSON string, integer, number, boolean, or null (`Reason.facts`, `Change.before/after`).
    enum Scalar: Codable, Hashable, Sendable {
        case string(String)
        case int(Int64)
        case double(Double)
        case bool(Bool)
        case null

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null }
            else if let v = try? c.decode(Bool.self) { self = .bool(v) }
            else if let v = try? c.decode(Int64.self) { self = .int(v) }
            else if let v = try? c.decode(Double.self) { self = .double(v) }
            else { self = .string(try c.decode(String.self)) }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .string(let v): try c.encode(v)
            case .int(let v): try c.encode(v)
            case .double(let v): try c.encode(v)
            case .bool(let v): try c.encode(v)
            case .null: try c.encodeNil()
            }
        }
    }

    // MARK: Profile

    struct MatchTier: Codable, Hashable, Sendable {
        var employeeRateFrom: Double
        var employeeRateTo: Double
        var matchPerEmployeeDollar: Double

        enum CodingKeys: String, CodingKey {
            case employeeRateFrom = "employee_rate_from"
            case employeeRateTo = "employee_rate_to"
            case matchPerEmployeeDollar = "match_per_employee_dollar"
        }
    }

    struct EmployerMatch: Codable, Hashable, Sendable {
        enum Status: String, Codable, Sendable { case confirmed, none, unknown }
        var status: Status
        var fullyVested: Bool
        var tiers: [MatchTier]

        enum CodingKeys: String, CodingKey {
            case status
            case fullyVested = "fully_vested"
            case tiers
        }
    }

    struct Debt: Codable, Hashable, Sendable {
        enum Kind: String, Codable, Sendable {
            case creditCard = "credit_card"
            case studentLoan = "student_loan"
            case other
        }
        var id: String
        var type: Kind
        var balanceCents: Int64
        var apr: Double
        var minimumPaymentCents: Int64

        enum CodingKeys: String, CodingKey {
            case id, type, apr
            case balanceCents = "balance_cents"
            case minimumPaymentCents = "minimum_payment_cents"
        }
    }

    struct Provenance: Codable, Hashable, Sendable {
        enum Source: String, Codable, Sendable {
            case fixture
            case plaidSandbox = "plaid_sandbox"
            case userConfirmed = "user_confirmed"
        }
        var source: Source
        var asOfDate: String

        enum CodingKeys: String, CodingKey {
            case source
            case asOfDate = "as_of_date"
        }
    }

    enum PlanningPreference: String, Codable, CaseIterable, Sendable {
        case balanced
        case cashSecurity = "cash_security"
        case debtReduction = "debt_reduction"
    }

    struct PlanStyles: Decodable, Sendable {
        var asOfDate: String
        var styles: [StyleOutcome]

        enum CodingKeys: String, CodingKey {
            case asOfDate = "as_of_date"
            case styles
        }
    }

    struct StyleOutcome: Decodable, Sendable {
        var style: PlanningPreference?
        var orderedPriorities: [Priority]?
        var debtFreeMonth: Int?
        var fullReserveMonth: Int?

        enum CodingKeys: String, CodingKey {
            case style
            case orderedPriorities = "ordered_priorities"
            case debtFreeMonth = "debt_free_month"
            case fullReserveMonth = "full_reserve_month"
        }
    }

    enum Priority: String, Codable, Sendable {
        case starterReserve = "starter_reserve"
        case highAprDebt = "high_apr_debt"
        case fullReserve = "full_reserve"
    }

    struct FinancialProfile: Codable, Hashable, Identifiable, Sendable {
        enum Source: String, Codable, Sendable {
            case demo
            case plaidSandbox = "plaid_sandbox"
            case manual
        }
        enum TaxTreatment: String, Codable, Sendable { case traditional, roth }

        var schemaVersion: String
        var id: String
        var name: String
        var asOfDate: String
        var currency: String
        var source: Source
        var age: Int
        var retirementAge: Int
        var annualGrossSalaryCents: Int64
        var monthlyTakeHomeCents: Int64
        var monthlyLivingExpensesCents: Int64
        var annualEmployeeLimitCents: Int64
        var employeeContributionRate: Double
        var contributionTaxTreatment: TaxTreatment
        var estimatedMarginalIncomeTaxRate: Double
        var retirementBalanceCents: Int64
        var emergencyCashCents: Int64
        var employerMatch: EmployerMatch
        var debts: [Debt]
        var planningPreference: PlanningPreference
        var fundID: String?
        var fundBalanceConfirmed: Bool
        var fundAccountType: Funds.AccountType?
        var planMenuFundIDs: [String]?
        var provenance: [String: Provenance]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case id, name, currency, source, age, debts, provenance
            case asOfDate = "as_of_date"
            case retirementAge = "retirement_age"
            case annualGrossSalaryCents = "annual_gross_salary_cents"
            case monthlyTakeHomeCents = "monthly_take_home_cents"
            case monthlyLivingExpensesCents = "monthly_living_expenses_cents"
            case annualEmployeeLimitCents = "annual_employee_limit_cents"
            case employeeContributionRate = "employee_contribution_rate"
            case contributionTaxTreatment = "contribution_tax_treatment"
            case estimatedMarginalIncomeTaxRate = "estimated_marginal_income_tax_rate"
            case retirementBalanceCents = "retirement_balance_cents"
            case emergencyCashCents = "emergency_cash_cents"
            case employerMatch = "employer_match"
            case planningPreference = "planning_preference"
            case fundID = "fund_id"
            case fundBalanceConfirmed = "fund_balance_confirmed"
            case fundAccountType = "fund_account_type"
            case planMenuFundIDs = "plan_menu_fund_ids"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try c.decodeIfPresent(String.self, forKey: .schemaVersion) ?? API.schemaVersion
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            asOfDate = try c.decode(String.self, forKey: .asOfDate)
            currency = try c.decode(String.self, forKey: .currency)
            source = try c.decode(Source.self, forKey: .source)
            age = try c.decode(Int.self, forKey: .age)
            retirementAge = try c.decode(Int.self, forKey: .retirementAge)
            annualGrossSalaryCents = try c.decode(Int64.self, forKey: .annualGrossSalaryCents)
            monthlyTakeHomeCents = try c.decode(Int64.self, forKey: .monthlyTakeHomeCents)
            monthlyLivingExpensesCents = try c.decode(Int64.self, forKey: .monthlyLivingExpensesCents)
            annualEmployeeLimitCents = try c.decode(Int64.self, forKey: .annualEmployeeLimitCents)
            employeeContributionRate = try c.decode(Double.self, forKey: .employeeContributionRate)
            contributionTaxTreatment = try c.decode(TaxTreatment.self, forKey: .contributionTaxTreatment)
            estimatedMarginalIncomeTaxRate = try c.decode(Double.self, forKey: .estimatedMarginalIncomeTaxRate)
            retirementBalanceCents = try c.decode(Int64.self, forKey: .retirementBalanceCents)
            emergencyCashCents = try c.decode(Int64.self, forKey: .emergencyCashCents)
            employerMatch = try c.decode(EmployerMatch.self, forKey: .employerMatch)
            debts = try c.decode([Debt].self, forKey: .debts)
            planningPreference = try c.decodeIfPresent(PlanningPreference.self, forKey: .planningPreference) ?? .balanced
            fundID = try c.decodeIfPresent(String.self, forKey: .fundID)
            fundBalanceConfirmed = try c.decodeIfPresent(Bool.self, forKey: .fundBalanceConfirmed) ?? false
            fundAccountType = try c.decodeIfPresent(Funds.AccountType.self, forKey: .fundAccountType)
            planMenuFundIDs = try c.decodeIfPresent([String].self, forKey: .planMenuFundIDs)
            provenance = try c.decode([String: Provenance].self, forKey: .provenance)
        }
    }

    struct Scenario: Codable, Hashable, Sendable {
        var retirementAge: Int
        /// nil applies the adaptive policy at that age; a value fixes the election.
        var employeeContributionRate: Double?
        var extraMonthlyDebtCents: Int64? = nil
        var priorityStyle: PlanningPreference? = nil

        init(retirementAge: Int, employeeContributionRate: Double?, extraMonthlyDebtCents: Int64? = nil,
             priorityStyle: PlanningPreference? = nil) {
            self.retirementAge = retirementAge
            self.employeeContributionRate = employeeContributionRate
            self.extraMonthlyDebtCents = extraMonthlyDebtCents
            self.priorityStyle = priorityStyle
        }

        enum CodingKeys: String, CodingKey {
            case retirementAge = "retirement_age"
            case employeeContributionRate = "employee_contribution_rate"
            case extraMonthlyDebtCents = "extra_monthly_debt_cents"
            case priorityStyle = "priority_style"
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(retirementAge, forKey: .retirementAge)
            try c.encode(employeeContributionRate, forKey: .employeeContributionRate)
            try c.encode(extraMonthlyDebtCents, forKey: .extraMonthlyDebtCents)
            try c.encode(priorityStyle, forKey: .priorityStyle)
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            retirementAge = try c.decode(Int.self, forKey: .retirementAge)
            employeeContributionRate = try c.decodeIfPresent(Double.self, forKey: .employeeContributionRate)
            extraMonthlyDebtCents = try c.decodeIfPresent(Int64.self, forKey: .extraMonthlyDebtCents)
            priorityStyle = try c.decodeIfPresent(PlanningPreference.self, forKey: .priorityStyle)
        }
    }

    struct EvaluateRequest: Encodable, Sendable {
        var profile: FinancialProfile
        var scenario: Scenario?
        var previousDecisionID: String?
        var baseDecisionID: String? = nil

        enum CodingKeys: String, CodingKey {
            case profile, scenario
            case previousDecisionID = "previous_decision_id"
            case baseDecisionID = "base_decision_id"
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(profile, forKey: .profile)
            try c.encode(scenario, forKey: .scenario)
            try c.encode(previousDecisionID, forKey: .previousDecisionID)
            try c.encode(baseDecisionID, forKey: .baseDecisionID)
        }
    }

    // MARK: Derived state

    struct FinancialState: Codable, Hashable, Sendable {
        var monthsUntilRetirement: Int
        var grossMonthlySalaryCents: Int64
        var currentEmployeeContributionCents: Int64
        var currentEmployeeCashCostCents: Int64
        var monthlyResourcesBeforeRetirementCents: Int64
        var monthlyRequiredDebtPaymentsCents: Int64
        var monthlyAllocatableBudgetCents: Int64
        var currentMonthlySurplusCents: Int64
        var emergencyMonths: Double
        var criticalReserveTargetCents: Int64
        var starterReserveTargetCents: Int64
        var fullReserveTargetCents: Int64
        var employeeRateForFullMatch: Double?
        var currentMonthlyEmployerMatchCents: Int64?
        var maximumMonthlyEmployerMatchCents: Int64?
        var matchCaptureFraction: Double?
        var highInterestDebtCents: Int64
        var highestDebtApr: Double?
        var baselineEquityWeight: Double
        var warnings: [String]

        enum CodingKeys: String, CodingKey {
            case monthsUntilRetirement = "months_until_retirement"
            case grossMonthlySalaryCents = "gross_monthly_salary_cents"
            case currentEmployeeContributionCents = "current_employee_contribution_cents"
            case currentEmployeeCashCostCents = "current_employee_cash_cost_cents"
            case monthlyResourcesBeforeRetirementCents = "monthly_resources_before_retirement_cents"
            case monthlyRequiredDebtPaymentsCents = "monthly_required_debt_payments_cents"
            case monthlyAllocatableBudgetCents = "monthly_allocatable_budget_cents"
            case currentMonthlySurplusCents = "current_monthly_surplus_cents"
            case emergencyMonths = "emergency_months"
            case criticalReserveTargetCents = "critical_reserve_target_cents"
            case starterReserveTargetCents = "starter_reserve_target_cents"
            case fullReserveTargetCents = "full_reserve_target_cents"
            case employeeRateForFullMatch = "employee_rate_for_full_match"
            case currentMonthlyEmployerMatchCents = "current_monthly_employer_match_cents"
            case maximumMonthlyEmployerMatchCents = "maximum_monthly_employer_match_cents"
            case matchCaptureFraction = "match_capture_fraction"
            case highInterestDebtCents = "high_interest_debt_cents"
            case highestDebtApr = "highest_debt_apr"
            case baselineEquityWeight = "baseline_equity_weight"
            case warnings
        }
    }

    // MARK: Plan

    struct RecommendationAction: Codable, Hashable, Identifiable, Sendable {
        enum Category: String, Codable, Sendable { case cashFlow = "cash_flow", contribution, emergency, debt, allocation }
        enum Status: String, Codable, Sendable { case action, maintain, blocked, information }
        var id: String
        var rank: Int
        var category: Category
        var status: Status
        var monthlyCashCostCents: Int64
        var employeeContributionCents: Int64?
        var employeeContributionRate: Double?
        var debtID: String?
        var targetBalanceCents: Int64?
        var reasonCodes: [String]

        enum CodingKeys: String, CodingKey {
            case id, rank, category, status
            case monthlyCashCostCents = "monthly_cash_cost_cents"
            case employeeContributionCents = "employee_contribution_cents"
            case employeeContributionRate = "employee_contribution_rate"
            case debtID = "debt_id"
            case targetBalanceCents = "target_balance_cents"
            case reasonCodes = "reason_codes"
        }
    }

    struct Reason: Codable, Hashable, Sendable {
        var code: String
        var templateKey: String
        var facts: [String: Scalar]
        var inputPaths: [String]

        enum CodingKeys: String, CodingKey {
            case code, facts
            case templateKey = "template_key"
            case inputPaths = "input_paths"
        }
    }

    struct Plan: Codable, Hashable, Sendable {
        var primaryActionID: String
        var actions: [RecommendationAction]
        var reasons: [Reason]

        var primaryAction: RecommendationAction? { actions.first { $0.id == primaryActionID } }

        enum CodingKeys: String, CodingKey {
            case actions, reasons
            case primaryActionID = "primary_action_id"
        }
    }

    // MARK: Projections and assumptions

    struct ProjectionPoint: Codable, Hashable, Sendable {
        var month: Int
        var retirementBalanceCents: Int64
        var cashCents: Int64
        var debtCents: Int64

        enum CodingKeys: String, CodingKey {
            case month
            case retirementBalanceCents = "retirement_balance_cents"
            case cashCents = "cash_cents"
            case debtCents = "debt_cents"
        }
    }

    struct Projection: Codable, Hashable, Sendable {
        enum Strategy: String, Codable, Sendable { case current, adaptive, custom }
        var strategy: Strategy
        var retirementAge: Int
        var feasible: Bool
        var shortfallCents: Int64?
        var retirementBalanceNominalCents: Int64?
        var retirementBalanceTodayCents: Int64?
        var cashNominalCents: Int64?
        var debtNominalCents: Int64?
        var cumulativeDebtInterestCents: Int64?
        var debtFreeMonth: Int?
        var starterReserveMonth: Int?
        var fullReserveMonth: Int?
        var points: [ProjectionPoint]
        /// This projection's own warnings (REPORT C3). Optional so older servers and
        /// bundles exported before the field existed still decode.
        var warnings: [String]?

        enum CodingKeys: String, CodingKey {
            case strategy, feasible, points, warnings
            case retirementAge = "retirement_age"
            case shortfallCents = "shortfall_cents"
            case retirementBalanceNominalCents = "retirement_balance_nominal_cents"
            case retirementBalanceTodayCents = "retirement_balance_today_cents"
            case cashNominalCents = "cash_nominal_cents"
            case debtNominalCents = "debt_nominal_cents"
            case cumulativeDebtInterestCents = "cumulative_debt_interest_cents"
            case debtFreeMonth = "debt_free_month"
            case starterReserveMonth = "starter_reserve_month"
            case fullReserveMonth = "full_reserve_month"
        }
    }

    struct Projections: Codable, Hashable, Sendable {
        var current: Projection
        var adaptive: Projection
        var custom: Projection?
    }

    struct GlidePathAnchor: Codable, Hashable, Sendable {
        var yearsToRetirement: Double
        var equityWeight: Double

        enum CodingKeys: String, CodingKey {
            case yearsToRetirement = "years_to_retirement"
            case equityWeight = "equity_weight"
        }
    }

    struct ModelAssumptions: Codable, Hashable, Sendable {
        var annualEquityReturn: Double
        var annualBondReturn: Double
        var annualCashReturn: Double
        var annualInflation: Double
        var annualSalaryGrowth: Double
        var annualLivingCostGrowth: Double
        var annualEmployeeLimitGrowth: Double
        var highInterestAprThreshold: Double
        var retirementTotalSavingTarget: Double
        var criticalReserveCapCents: Int64
        var starterReserveMonths: Double
        var fullReserveMonths: Double
        var returnsNetOfFees: Bool
        var glidePath: [GlidePathAnchor]
        var limitations: [String]
        var fundModel: FundModel?

        enum CodingKeys: String, CodingKey {
            case annualEquityReturn = "annual_equity_return"
            case annualBondReturn = "annual_bond_return"
            case annualCashReturn = "annual_cash_return"
            case annualInflation = "annual_inflation"
            case annualSalaryGrowth = "annual_salary_growth"
            case annualLivingCostGrowth = "annual_living_cost_growth"
            case annualEmployeeLimitGrowth = "annual_employee_limit_growth"
            case highInterestAprThreshold = "high_interest_apr_threshold"
            case retirementTotalSavingTarget = "retirement_total_saving_target"
            case criticalReserveCapCents = "critical_reserve_cap_cents"
            case starterReserveMonths = "starter_reserve_months"
            case fullReserveMonths = "full_reserve_months"
            case returnsNetOfFees = "returns_net_of_fees"
            case glidePath = "glide_path"
            case limitations
            case fundModel = "fund_model"
        }
    }

    struct FundModel: Codable, Hashable, Sendable {
        var fundID: String
        var fundName: String
        var catalogVersion: String
        var shareClassID: String
        var targetYear: Int
        var appliedExpenseRatio: Double
        var feeAsOfDate: String
        var feeSourceURL: String
        var glidePathSourceURL: String
        var glidePathMode: String
        var glidePath: [GlidePathAnchor]
        var limitation: String?

        enum CodingKeys: String, CodingKey {
            case fundID = "fund_id", fundName = "fund_name", catalogVersion = "catalog_version"
            case shareClassID = "share_class_id", targetYear = "target_year"
            case appliedExpenseRatio = "applied_expense_ratio", feeAsOfDate = "fee_as_of_date"
            case feeSourceURL = "fee_source_url", glidePathSourceURL = "glide_path_source_url"
            case glidePathMode = "glide_path_mode", glidePath = "glide_path", limitation
        }
    }

    // MARK: AI decision and explanation

    struct Rationale: Codable, Hashable, Sendable {
        var priority: String
        var summary: String
        var evidencePaths: [String]
        var tradeoff: String

        enum CodingKeys: String, CodingKey {
            case priority, summary, tradeoff
            case evidencePaths = "evidence_paths"
        }
    }

    struct ConstraintCheck: Codable, Hashable, Sendable {
        var code: String
        var passed: Bool
    }

    struct DecisionSummary: Codable, Hashable, Sendable {
        enum Source: String, Codable, Sendable {
            case ai
            case rulesFallback = "rules_fallback"
        }
        var decisionID: String
        var source: Source
        var modelID: String?
        var promptVersion: String
        var orderedPriorities: [Priority]
        var rationale: [Rationale]
        var constraintChecks: [ConstraintCheck]
        var fallbackReason: String?

        enum CodingKeys: String, CodingKey {
            case source, rationale
            case decisionID = "decision_id"
            case modelID = "model_id"
            case promptVersion = "prompt_version"
            case orderedPriorities = "ordered_priorities"
            case constraintChecks = "constraint_checks"
            case fallbackReason = "fallback_reason"
        }
    }

    struct Change: Codable, Hashable, Sendable {
        var fieldPath: String
        var before: Scalar
        var after: Scalar

        enum CodingKeys: String, CodingKey {
            case before, after
            case fieldPath = "field_path"
        }
    }

    struct Explanation: Codable, Hashable, Sendable {
        enum Source: String, Codable, Sendable { case ai, template }
        var stateSummary: String
        var narrative: String
        var source: Source
        var changes: [Change]

        enum CodingKeys: String, CodingKey {
            case narrative, source, changes
            case stateSummary = "state_summary"
        }
    }

    // MARK: Evaluation and other responses

    struct Evaluation: Codable, Hashable, Sendable {
        var schemaVersion: String
        var modelVersion: String
        var policyVersion: String
        var profileID: String
        var inputHash: String
        var financialState: FinancialState
        var plan: Plan
        var assumptions: ModelAssumptions
        var projections: Projections
        var warnings: [String]
        var decisionSummary: DecisionSummary
        var explanation: Explanation
        var rulesComparison: RulesComparison?

        enum CodingKeys: String, CodingKey {
            case plan, assumptions, projections, warnings, explanation
            case schemaVersion = "schema_version"
            case modelVersion = "model_version"
            case policyVersion = "policy_version"
            case profileID = "profile_id"
            case inputHash = "input_hash"
            case financialState = "financial_state"
            case decisionSummary = "decision_summary"
            case rulesComparison = "rules_comparison"
        }
    }

    struct RulesComparison: Codable, Hashable, Sendable {
        var basis: String
        var rulesPriorities: [Priority]
        var aiPriorities: [Priority]
        var rulesRetirementBalanceCents: Int64?
        var aiRetirementBalanceCents: Int64?
        var differenceCents: Int64?
        var outcome: String

        enum CodingKeys: String, CodingKey {
            case basis, outcome
            case rulesPriorities = "rules_priorities", aiPriorities = "ai_priorities"
            case rulesRetirementBalanceCents = "rules_retirement_balance_cents"
            case aiRetirementBalanceCents = "ai_retirement_balance_cents"
            case differenceCents = "difference_cents"
        }
    }

    struct Health: Codable, Hashable, Sendable {
        var status: String
        var schemaVersion: String
        var modelVersion: String
        var policyVersion: String
        var plaidEnabled: Bool
        /// Whether the server has credentials for its selected AI provider. Optional so
        /// older servers without the field still decode.
        var aiAvailable: Bool?

        enum CodingKeys: String, CodingKey {
            case status
            case schemaVersion = "schema_version"
            case modelVersion = "model_version"
            case policyVersion = "policy_version"
            case plaidEnabled = "plaid_enabled"
            case aiAvailable = "ai_available"
        }
    }

    struct DemoProfiles: Codable, Hashable, Sendable {
        var schemaVersion: String
        var profiles: [FinancialProfile]

        enum CodingKeys: String, CodingKey {
            case profiles
            case schemaVersion = "schema_version"
        }
    }

    struct ErrorBody: Codable, Hashable, Sendable {
        var code: String
        var message: String
        var fieldPaths: [String]
        var retryable: Bool

        enum CodingKeys: String, CodingKey {
            case code, message, retryable
            case fieldPaths = "field_paths"
        }
    }

    struct ErrorEnvelope: Codable, Hashable, Sendable {
        var error: ErrorBody
    }
}
