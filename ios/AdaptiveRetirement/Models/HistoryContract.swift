import Foundation

/// Scenario history contract (`backend/app/analytics/models.py`). Runs are stored as time
/// series in Tiger Data. The app sends a shown result's inputs, never its numbers: the
/// server re-runs the engine and saves only if its `input_hash` matches.
extension API {
    /// A decision as the server accepts it back: every key written, nulls included. The server
    /// requires `model_id` and `fallback_reason` even when null, and the synthesized
    /// `DecisionSummary` encoding would omit them. Used by history saves and scenario reuse.
    struct DecisionPayload: Encodable {
        let summary: DecisionSummary
        init(_ summary: DecisionSummary) { self.summary = summary }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: DecisionSummary.CodingKeys.self)
            try c.encode(summary.decisionID, forKey: .decisionID)
            try c.encode(summary.source, forKey: .source)
            try c.encode(summary.modelID, forKey: .modelID)
            try c.encode(summary.promptVersion, forKey: .promptVersion)
            try c.encode(summary.orderedPriorities, forKey: .orderedPriorities)
            try c.encode(summary.rationale, forKey: .rationale)
            try c.encode(summary.constraintChecks, forKey: .constraintChecks)
            try c.encode(summary.fallbackReason, forKey: .fallbackReason)
        }
    }

    enum History {
        struct Status: Decodable, Sendable {
            /// A database is configured on this server.
            var enabled: Bool
            /// The database answered just now.
            var available: Bool
        }

        struct SaveRunRequest: Encodable, Sendable {
            var profileID: String
            /// nil for the plan as is.
            var scenario: Scenario?
            var decisionSummary: DecisionSummary
            var inputHash: String
            var planningPreference: PlanningPreference? = nil

            enum CodingKeys: String, CodingKey {
                case scenario
                case profileID = "profile_id"
                case decisionSummary = "decision_summary"
                case inputHash = "input_hash"
                case planningPreference = "planning_preference"
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(profileID, forKey: .profileID)
                try c.encode(scenario, forKey: .scenario)
                try c.encode(DecisionPayload(decisionSummary), forKey: .decisionSummary)
                try c.encode(inputHash, forKey: .inputHash)
                try c.encode(planningPreference, forKey: .planningPreference)
            }

        }

        struct RunSummary: Decodable, Hashable, Identifiable, Sendable {
            var id: String { runID }
            var runID: String
            var profileID: String
            /// Built by the server: "Plan as is", "Retire at 69 · adaptive contribution", …
            var label: String
            /// ISO 8601 with a time zone, usually with fractional seconds.
            var createdAt: String
            var asOfDate: String
            var retirementAge: Int
            var finalRetirementBalanceCents: Int64?
            /// "ai" or "rules_fallback".
            var decisionSource: String
            var modelVersion: String
            var policyVersion: String
            var fundID: String?
            var fundName: String?
            var catalogVersion: String?
            var glidePathMode: String?

            var isAIDecision: Bool { decisionSource == "ai" }

            enum CodingKeys: String, CodingKey {
                case label
                case runID = "run_id"
                case profileID = "profile_id"
                case createdAt = "created_at"
                case asOfDate = "as_of_date"
                case retirementAge = "retirement_age"
                case finalRetirementBalanceCents = "final_retirement_balance_cents"
                case decisionSource = "decision_source"
                case modelVersion = "model_version"
                case policyVersion = "policy_version"
                case fundID = "fund_id", fundName = "fund_name", catalogVersion = "catalog_version"
                case glidePathMode = "glide_path_mode"
            }
        }

        struct SaveRunResponse: Decodable, Sendable {
            var run: RunSummary
            /// false when a run with the same `input_hash` was already saved.
            var created: Bool
        }

        struct RunList: Decodable, Sendable {
            /// Newest first, at most 20.
            var runs: [RunSummary]
        }

        struct YearValues: Decodable, Hashable, Sendable {
            var retirementBalanceCents: Int64
            var cashCents: Int64
            var debtCents: Int64

            enum CodingKeys: String, CodingKey {
                case retirementBalanceCents = "retirement_balance_cents"
                case cashCents = "cash_cents"
                case debtCents = "debt_cents"
            }
        }

        /// One sampled point per run. A side is nil where that run has no point (it retired sooner).
        struct ComparisonPoint: Decodable, Hashable, Sendable {
            var month: Int
            var projectedOn: String
            var base: YearValues?
            var other: YearValues?

            enum CodingKeys: String, CodingKey {
                case month, base, other
                case projectedOn = "projected_on"
            }
        }

        struct Comparison: Decodable, Sendable {
            var profileID: String
            var asOfDate: String
            var base: RunSummary
            var other: RunSummary
            /// Every year from 0 to the longer run's last year (month = 12 × year).
            var years: [ComparisonPoint]
            /// 5, 10 and 20 years.
            var horizons: [Horizon]

            enum CodingKeys: String, CodingKey {
                case base, other, years, horizons
                case profileID = "profile_id"
                case asOfDate = "as_of_date"
            }
        }

        struct Horizon: Decodable, Hashable, Sendable {
            var years: Int
            var point: ComparisonPoint

            enum CodingKeys: String, CodingKey { case years }

            init(from decoder: Decoder) throws {
                years = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .years)
                point = try ComparisonPoint(from: decoder)
            }
        }
    }
}
