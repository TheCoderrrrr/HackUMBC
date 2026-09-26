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

    enum Priority: String, Codable, Sendable {
        case starterReserve = "starter_reserve"
        case highAprDebt = "high_apr_debt"
        case fullReserve = "full_reserve"
    }

    struct FinancialProfile: Codable, Hashable, Identifiable, Sendable {
        enum Source: String, Codable, Sendable {
            case demo
            case plaidSandbox = "plaid_sandbox"
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
            provenance = try c.decode([String: Provenance].self, forKey: .provenance)
        }
    }

    struct Scenario: Codable, Hashable, Sendable {
        var retirementAge: Int
        /// nil applies the adaptive policy at that age; a value fixes the election.
        var employeeContributionRate: Double?

        enum CodingKeys: String, CodingKey {
            case retirementAge = "retirement_age"
            case employeeContributionRate = "employee_contribution_rate"
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(retirementAge, forKey: .retirementAge)
            try c.encode(employeeContributionRate, forKey: .employeeContributionRate)
        }
    }

    struct EvaluateRequest: Encodable, Sendable {
        var profile: FinancialProfile
        var scenario: Scenario?
        var previousDecisionID: String?

        enum CodingKeys: String, CodingKey {
            case profile, scenario
            case previousDecisionID = "previous_decision_id"
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(profile, forKey: .profile)
            try c.encode(scenario, forKey: .scenario)
            try c.encode(previousDecisionID, forKey: .previousDecisionID)
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

        enum CodingKeys: String, CodingKey {
            case strategy, feasible, points
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

        enum CodingKeys: String, CodingKey {
            case plan, assumptions, projections, warnings, explanation
            case schemaVersion = "schema_version"
            case modelVersion = "model_version"
            case policyVersion = "policy_version"
            case profileID = "profile_id"
            case inputHash = "input_hash"
            case financialState = "financial_state"
            case decisionSummary = "decision_summary"
        }
    }

    struct Health: Codable, Hashable, Sendable {
        var status: String
        var schemaVersion: String
        var modelVersion: String
        var policyVersion: String
        var plaidEnabled: Bool

        enum CodingKeys: String, CodingKey {
            case status
            case schemaVersion = "schema_version"
            case modelVersion = "model_version"
            case policyVersion = "policy_version"
            case plaidEnabled = "plaid_enabled"
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
