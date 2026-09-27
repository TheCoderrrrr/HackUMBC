import Foundation

extension API {
    struct ManualProfileInput: Encodable, Sendable {
        struct Match: Encodable, Sendable {
            var kind: String
            var upToRate: Double?
            var matchPerDollar: Double?
            enum CodingKeys: String, CodingKey {
                case kind, upToRate = "up_to_rate", matchPerDollar = "match_per_dollar"
            }
        }
        struct Debt: Encodable, Sendable {
            var type: String
            var balanceCents: Int64
            var apr: Double
            var minimumPaymentCents: Int64
            enum CodingKeys: String, CodingKey {
                case type, balanceCents = "balance_cents", apr, minimumPaymentCents = "minimum_payment_cents"
            }
        }
        var name: String
        var age: Int
        var retirementAge: Int
        var annualGrossSalaryCents: Int64
        var monthlyTakeHomeCents: Int64
        var monthlyLivingExpensesCents: Int64
        var employeeContributionRate: Double
        var retirementBalanceCents: Int64
        var emergencyCashCents: Int64
        var match: Match
        var debts: [Debt]
        var fundID: String?
        var fundBalanceConfirmed: Bool
        var fundAccountType: Funds.AccountType?
        var planMenuFundIDs: [String]?

        enum CodingKeys: String, CodingKey {
            case name, age, match, debts
            case retirementAge = "retirement_age"
            case annualGrossSalaryCents = "annual_gross_salary_cents"
            case monthlyTakeHomeCents = "monthly_take_home_cents"
            case monthlyLivingExpensesCents = "monthly_living_expenses_cents"
            case employeeContributionRate = "employee_contribution_rate"
            case retirementBalanceCents = "retirement_balance_cents"
            case emergencyCashCents = "emergency_cash_cents"
            case fundID = "fund_id", fundBalanceConfirmed = "fund_balance_confirmed"
            case fundAccountType = "fund_account_type", planMenuFundIDs = "plan_menu_fund_ids"
        }
    }

    struct ProfileBuild: Decodable, Sendable {
        var profile: FinancialProfile
        var preview: FinancialState
        var blockingIssue: String?
        enum CodingKeys: String, CodingKey {
            case profile, preview, blockingIssue = "blocking_issue"
        }
    }
}
