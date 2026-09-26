import SwiftUI

// Illustrative money-river timeline for Explore.
//
// The backend does not yet expose monthly allocator cash flows or a projection
// calendar anchor (FRONTEND.md, Explore tab), so the dated states below are the
// Figma prototype's illustrative states — labelled on screen as "not calculated
// results". Swap `ExploreTimeline.illustrative(for:)` for engine data once the
// monthly allocation fields exist. Nothing here computes a recommendation.

/// Where one month's cash goes, as shown under the river.
struct RiverDestination: Hashable {
    let title: String
    let value: String
    let caption: String
}

/// A dated state of the river: how many of the streamlines reach each destination.
struct RiverKeyframe {
    /// Months after the opening month.
    let month: Int
    /// Streamline counts for [retirement, reserves, third column]; sums to `ExploreTimeline.streamCount`.
    let counts: [Int]
}

struct Milestone: Identifiable, Hashable {
    var id: Int { month }
    let month: Int
    let title: String
}

/// Interval bars drawn on the three timeline tracks, in months.
struct TimelineTracks {
    var retirementIncreaseFrom: Int?
    var debtPayoff: ClosedRange<Int>?
    var reserveFunding: ClosedRange<Int>?
}

struct ExploreTimeline {
    static let streamCount = 44
    /// Opening month: Sep 2026 (fixtures are as of 2026-09-26).
    static let startYear = 2026
    static let startMonth = 9

    /// Last selectable month index (inclusive).
    let lastMonth: Int
    let keyframes: [RiverKeyframe]
    let milestones: [Milestone]
    let tracks: TimelineTracks
    /// Title of the third river column ("Extra debt" or "Remaining").
    let thirdColumnTitle: String
    private let destinationsByPhase: [(from: Int, values: [RiverDestination])]
    private let contextByPhase: [(from: Int, text: String)]
    private let exactMonthContext: [Int: String]

    /// Months over which the river glides into the next dated state, ending on it.
    static let transitionMonths = 4.0

    // MARK: Lookups

    func destinations(at month: Int) -> [RiverDestination] {
        destinationsByPhase.last(where: { $0.from <= month })?.values ?? destinationsByPhase[0].values
    }

    func context(at month: Int) -> String {
        if let exact = exactMonthContext[month] { return exact }
        return contextByPhase.last(where: { $0.from <= month })?.text ?? ""
    }

    func milestone(at month: Int) -> Milestone? { milestones.first { $0.month == month } }

    /// The keyframe pair bracketing `month` and the eased 0…1 progress between them.
    func segment(at month: Double) -> (from: RiverKeyframe, to: RiverKeyframe, t: Double) {
        guard let index = keyframes.lastIndex(where: { Double($0.month) <= month }) else {
            return (keyframes[0], keyframes[0], 0)
        }
        let from = keyframes[index]
        guard index + 1 < keyframes.count else { return (from, from, 0) }
        let to = keyframes[index + 1]
        let start = Double(to.month) - Self.transitionMonths
        guard month > start else { return (from, from, 0) }
        let raw = min(max((month - start) / Self.transitionMonths, 0), 1)
        return (from, to, raw * raw * (3 - 2 * raw))
    }

    // MARK: Calendar

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let fullMonthNames = ["January", "February", "March", "April", "May", "June", "July",
                                         "August", "September", "October", "November", "December"]

    static func label(forMonth month: Int) -> String {
        let absolute = startMonth - 1 + month
        return "\(monthNames[absolute % 12]) \(startYear + absolute / 12)"
    }

    static func spokenLabel(forMonth month: Int) -> String {
        let absolute = startMonth - 1 + month
        return "\(fullMonthNames[absolute % 12]) \(startYear + absolute / 12)"
    }

    #if DEBUG
    /// Parses "2028-09" into a month index, for the `-month` launch argument.
    static func monthIndex(from string: String) -> Int? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return (parts[0] - startYear) * 12 + (parts[1] - startMonth)
    }
    #endif
}

// MARK: - Illustrative fixtures

extension ExploreTimeline {
    static func illustrative(for profile: Profile) -> ExploreTimeline {
        profile.id == Profile.morgan.id ? morgan(profile) : steady(profile)
    }

    /// Opening-month destinations from the saved plan's cash priorities.
    private static func opening(_ profile: Profile) -> (counts: [Int], destinations: [RiverDestination], third: String) {
        func amount(_ kind: CashPriority.Kind) -> Int64 {
            profile.cashPriorities.first { $0.kind == kind }?.amountCents ?? 0
        }
        let retirement = amount(.retirement)
        let reserves = amount(.emergency)
        let debt = amount(.debt)
        let remaining = amount(.remaining)
        let usesDebt = debt > 0 || remaining == 0
        let third = usesDebt ? debt : remaining
        let thirdTitle = usesDebt ? "Extra debt" : "Remaining"

        let counts = streamCounts([retirement, reserves, third])
        let destinations = [
            RiverDestination(title: "Retirement", value: display(retirement), caption: "take-home cost"),
            RiverDestination(title: "Reserves", value: display(reserves), caption: "this month"),
            RiverDestination(title: thirdTitle, value: display(third),
                             caption: usesDebt ? "additional payment" : "yours to direct")
        ]
        return (counts, destinations, thirdTitle)
    }

    /// Whole dollars when exact, otherwise cents ("$273", "$963.80").
    private static func display(_ cents: Int64) -> String {
        cents % 100 == 0 ? Money.whole(cents) : Money.exact(cents)
    }

    /// Largest-remainder split of the streamlines, proportional to amounts.
    private static func streamCounts(_ amounts: [Int64]) -> [Int] {
        let total = amounts.reduce(0, +)
        guard total > 0 else { return [streamCount, 0, 0] }
        let exact = amounts.map { Double($0) / Double(total) * Double(streamCount) }
        var counts = exact.map { Int($0) }
        let order = exact.indices.sorted { exact[$0] - Double(counts[$0]) > exact[$1] - Double(counts[$1]) }
        for i in order.prefix(streamCount - counts.reduce(0, +)) { counts[i] += 1 }
        return counts
    }

    /// Morgan: the three dated Figma states — card cleared Sep 2028, reserve target Jan 2030.
    private static func morgan(_ profile: Profile) -> ExploreTimeline {
        let open = opening(profile)
        let debtCleared = 24, reserveMet = 40
        return ExploreTimeline(
            lastMonth: 48,
            keyframes: [
                RiverKeyframe(month: 0, counts: open.counts),
                RiverKeyframe(month: debtCleared, counts: [open.counts[0], streamCount - open.counts[0], 0]),
                RiverKeyframe(month: reserveMet, counts: [streamCount, 0, 0])
            ],
            milestones: [
                Milestone(month: debtCleared, title: "Debt cleared"),
                Milestone(month: reserveMet, title: "Reserve target reached")
            ],
            tracks: TimelineTracks(retirementIncreaseFrom: reserveMet,
                                   debtPayoff: 0...debtCleared,
                                   reserveFunding: debtCleared...reserveMet),
            thirdColumnTitle: open.third,
            destinationsByPhase: [
                (0, open.destinations),
                (1, [RiverDestination(title: "Retirement", value: "Full match", caption: "contribution policy"),
                     RiverDestination(title: "Reserves", value: "Starter held", caption: "emergency savings"),
                     RiverDestination(title: "Extra debt", value: "Paying down", caption: "credit card")]),
                (debtCleared, [RiverDestination(title: "Retirement", value: "Full match", caption: "contribution policy"),
                               RiverDestination(title: "Reserves", value: "Build buffer", caption: "emergency savings"),
                               RiverDestination(title: "Extra debt", value: "Cleared", caption: "remaining debt")]),
                (reserveMet, [RiverDestination(title: "Retirement", value: "Increase", caption: "contribution policy"),
                              RiverDestination(title: "Reserves", value: "Target met", caption: "emergency savings"),
                              RiverDestination(title: "Extra debt", value: "Cleared", caption: "remaining debt")])
            ],
            contextByPhase: [
                (0, "Opening month"),
                (1, "Paying down the card"),
                (debtCleared, "Building reserves"),
                (reserveMet, "Contribution increased")
            ],
            exactMonthContext: [
                0: "Opening month",
                debtCleared: "Debt cleared · building reserves",
                reserveMet: "Reserve target reached"
            ]
        )
    }

    /// Jordan and Casey: the saved plan maintains its opening allocation.
    private static func steady(_ profile: Profile) -> ExploreTimeline {
        let open = opening(profile)
        return ExploreTimeline(
            lastMonth: 48,
            keyframes: [RiverKeyframe(month: 0, counts: open.counts)],
            milestones: [],
            tracks: TimelineTracks(),
            thirdColumnTitle: open.third,
            destinationsByPhase: [
                (0, open.destinations),
                (1, [RiverDestination(title: "Retirement", value: "Maintain", caption: "contribution policy"),
                     RiverDestination(title: "Reserves", value: "Target met", caption: "emergency savings"),
                     RiverDestination(title: open.third, value: open.destinations[2].value,
                                      caption: open.destinations[2].caption)])
            ],
            contextByPhase: [(0, "Opening month"), (1, "Plan maintained")],
            exactMonthContext: [0: "Opening month"]
        )
    }
}
