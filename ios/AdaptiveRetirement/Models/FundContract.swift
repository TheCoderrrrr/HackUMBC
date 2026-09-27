import Foundation

/// Fund shortlist contract (`backend/app/fund_api.py`, `backend/app/funds.py`).
/// Rates and weights are fractions (0.0009 == 0.09%), except `ReportedCategory.percentOfNetAssets`,
/// which the filing reports as a percent (53.3 == 53.3%). Money is integer cents. Dates are
/// "YYYY-MM-DD" strings. Only fields the app shows are decoded; the rest are ignored.
extension API {
    enum Funds {
        enum AccountType: String, Codable, CaseIterable, Sendable {
            case k401 = "401k"
            case ira
        }

        enum RiskTolerance: String, Codable, CaseIterable, Sendable {
            case conservative, moderate, growth
        }

        /// Where the fund can be bought. Unrecognized server values decode as `.unrecognized`.
        enum AvailabilityLabel: String, Codable, Sendable {
            case inSuppliedPlanMenu = "in_supplied_plan_menu"
            case researchCandidate = "research_candidate_plan_menu_unconfirmed"
            case notConfirmedPurchasable = "discoverable_not_confirmed_purchasable"
            case unrecognized

            init(from decoder: Decoder) throws {
                self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unrecognized
            }
        }

        /// Why a reviewed fund was left out. Unrecognized server values decode as `.unrecognized`.
        enum ExclusionReason: String, Codable, Sendable {
            case notInPlanMenu = "NOT_IN_PLAN_MENU"
            case unavailable = "UNAVAILABLE"
            case incompleteFacts = "INCOMPLETE_FACTS"
            case staleFacts = "STALE_FACTS"
            case notTargetDate = "NOT_TARGET_DATE"
            case nonUSD = "NON_USD"
            case poorHorizonFit = "POOR_HORIZON_FIT"
            case poorRiskFit = "POOR_RISK_FIT"
            case unrecognized

            init(from decoder: Decoder) throws {
                self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unrecognized
            }
        }

        // MARK: Request

        struct Query: Encodable, Sendable {
            var accountType: AccountType
            var retirementYear: Int
            var riskTolerance: RiskTolerance
            /// Catalog `fund_id`s on the user's 401(k) menu; nil means the menu is unknown.
            var planMenuFundIDs: [String]?

            enum CodingKeys: String, CodingKey {
                case accountType = "account_type"
                case retirementYear = "retirement_year"
                case riskTolerance = "risk_tolerance"
                case planMenuFundIDs = "plan_menu_fund_ids"
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(accountType, forKey: .accountType)
                try c.encode(retirementYear, forKey: .retirementYear)
                try c.encode(riskTolerance, forKey: .riskTolerance)
                try c.encode(planMenuFundIDs, forKey: .planMenuFundIDs)
            }
        }

        // MARK: Catalog

        struct CatalogEntry: Decodable, Hashable, Identifiable, Sendable {
            var id: String { fundID }
            var fundID: String
            var name: String
            var issuer: String
            var className: String
            var ticker: String?
            var targetYear: Int

            enum CodingKeys: String, CodingKey {
                case name, issuer, ticker
                case fundID = "fund_id"
                case className = "class_name"
                case targetYear = "target_year"
            }
        }

        struct CatalogSummary: Decodable, Sendable {
            var catalogVersion: String
            var publishedOn: String
            var reviewedBy: String
            var reviewNote: String
            var funds: [CatalogEntry]

            enum CodingKeys: String, CodingKey {
                case funds
                case catalogVersion = "catalog_version"
                case publishedOn = "published_on"
                case reviewedBy = "reviewed_by"
                case reviewNote = "review_note"
            }
        }

        // MARK: Shortlist

        struct Envelope: Decodable, Sendable {
            var catalogVersion: String
            var unmatchedPlanMenuIDs: [String]
            var shortlist: Shortlist
            /// Keyed by `fund_id`; one entry per recommendation.
            var details: [String: Detail]

            enum CodingKeys: String, CodingKey {
                case shortlist, details
                case catalogVersion = "catalog_version"
                case unmatchedPlanMenuIDs = "unmatched_plan_menu_ids"
            }
        }

        struct Shortlist: Decodable, Sendable {
            var asOfDate: String
            var recommendations: [Recommendation]
            var excluded: [Excluded]
            var assumptionSetVersion: String
            var assumptionSetAsOfDate: String
            var hypotheticalDisclosure: String

            /// Every reviewed fund was left out only because its verified facts are too old,
            /// e.g. after the 90-day holdings window. The server sends no separate flag for it.
            var isEntirelyStale: Bool {
                recommendations.isEmpty && !excluded.isEmpty && excluded.allSatisfy { $0.reasonCode == .staleFacts }
            }

            enum CodingKeys: String, CodingKey {
                case recommendations, excluded
                case asOfDate = "as_of_date"
                case assumptionSetVersion = "assumption_set_version"
                case assumptionSetAsOfDate = "assumption_set_as_of_date"
                case hypotheticalDisclosure = "hypothetical_disclosure"
            }
        }

        struct Excluded: Decodable, Hashable, Sendable {
            var fundID: String
            var reasonCode: ExclusionReason

            enum CodingKeys: String, CodingKey {
                case fundID = "fund_id"
                case reasonCode = "reason_code"
            }
        }

        struct ScoreComponents: Decodable, Hashable, Sendable {
            var horizonFit: Double
            var riskFit: Double
            var feeFit: Double

            enum CodingKeys: String, CodingKey {
                case horizonFit = "horizon_fit"
                case riskFit = "risk_fit"
                case feeFit = "fee_fit"
            }
        }

        struct HypotheticalScenario: Decodable, Hashable, Sendable {
            /// "low", "base" or "high".
            var label: String
            var annualNetReturnRate: Double
            var years: Int
            var hypotheticalStartCents: Int64
            var hypotheticalEndCents: Int64

            enum CodingKeys: String, CodingKey {
                case label, years
                case annualNetReturnRate = "annual_net_return_rate"
                case hypotheticalStartCents = "hypothetical_start_cents"
                case hypotheticalEndCents = "hypothetical_end_cents"
            }
        }

        struct HistoricalReturn: Decodable, Hashable, Sendable {
            var periodYears: Int
            var annualizedReturnRate: Double
            var asOfDate: String

            enum CodingKeys: String, CodingKey {
                case periodYears = "period_years"
                case annualizedReturnRate = "annualized_return_rate"
                case asOfDate = "as_of_date"
            }
        }

        struct Recommendation: Decodable, Hashable, Identifiable, Sendable {
            var id: String { fundID }
            var fundID: String
            var shareClassID: String
            var name: String
            var availabilityLabel: AvailabilityLabel
            var factsAsOfDate: String
            var expenseRatio: Double
            var equityWeight: Double
            var bondWeight: Double
            var otherWeight: Double
            var riskBand: Int
            var targetYear: Int
            var scoreComponents: ScoreComponents
            var hypotheticalScenarios: [HypotheticalScenario]
            var historicalReturns: [HistoricalReturn]

            enum CodingKeys: String, CodingKey {
                case name
                case fundID = "fund_id"
                case shareClassID = "share_class_id"
                case availabilityLabel = "availability_label"
                case factsAsOfDate = "facts_as_of_date"
                case expenseRatio = "expense_ratio"
                case equityWeight = "equity_weight"
                case bondWeight = "bond_weight"
                case otherWeight = "other_weight"
                case riskBand = "risk_band"
                case targetYear = "target_year"
                case scoreComponents = "score_components"
                case hypotheticalScenarios = "hypothetical_scenarios"
                case historicalReturns = "historical_returns"
            }
        }

        // MARK: Sourced detail

        struct DocumentLink: Decodable, Hashable, Sendable {
            var title: String
            var form: String
            var filedDate: String
            var url: String

            enum CodingKeys: String, CodingKey {
                case title, form, url
                case filedDate = "filed_date"
            }
        }

        struct FeeDetail: Decodable, Hashable, Sendable {
            var grossExpenseRatio: Double
            var acquiredFundFees: Double
            var feeWaiver: Double
            var appliedExpenseRatio: Double
            var waiverActive: Bool
            var waiverEnds: String?
            var waiverTerms: String
            var asOfDate: String
            var evidenceURL: String

            enum CodingKeys: String, CodingKey {
                case grossExpenseRatio = "gross_expense_ratio"
                case acquiredFundFees = "acquired_fund_fees"
                case feeWaiver = "fee_waiver"
                case appliedExpenseRatio = "applied_expense_ratio"
                case waiverActive = "waiver_active"
                case waiverEnds = "waiver_ends"
                case waiverTerms = "waiver_terms"
                case asOfDate = "as_of_date"
                case evidenceURL = "evidence_url"
            }
        }

        struct ReportedCategory: Decodable, Hashable, Sendable {
            var label: String
            /// A percent as filed (53.3 == 53.3%), not a fraction.
            var percentOfNetAssets: Double
            /// "equity", "bond" or "other".
            var bucket: String

            enum CodingKeys: String, CodingKey {
                case label, bucket
                case percentOfNetAssets = "percent_of_net_assets"
            }
        }

        struct AllocationDetail: Decodable, Hashable, Sendable {
            var asOfDate: String
            var reportedCategories: [ReportedCategory]
            var mappingNote: String
            var evidenceURL: String

            enum CodingKeys: String, CodingKey {
                case asOfDate = "as_of_date"
                case reportedCategories = "reported_categories"
                case mappingNote = "mapping_note"
                case evidenceURL = "evidence_url"
            }
        }

        struct Detail: Decodable, Hashable, Sendable {
            var fundID: String
            var issuer: String
            var className: String
            var ticker: String?
            var fees: FeeDetail
            var allocation: AllocationDetail
            var glidePath: String
            var prospectus: DocumentLink
            var holdingsReport: DocumentLink
            var caveats: [String]

            enum CodingKeys: String, CodingKey {
                case issuer, ticker, fees, allocation, prospectus, caveats
                case fundID = "fund_id"
                case className = "class_name"
                case glidePath = "glide_path"
                case holdingsReport = "holdings_report"
            }
        }
    }
}
