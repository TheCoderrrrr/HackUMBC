import SwiftUI

// Illustrative money-river timeline for Explore.
//
// The backend does not yet expose monthly allocator cash flows (FRONTEND.md, Explore
// tab), so the river's flows are the Figma prototype's illustrative states. When an
// evaluation is loaded, the opening split and Morgan's milestone months come from it.
// Nothing here computes a recommendation.

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
    /// Plan goals the engine reports as met from the opening month ("Starter reserve"), shown
    /// beside the dated milestones so a finished goal doesn't read as a missing one.
    var alreadyMet: [String] = []
    private let destinationsByPhase: [(from: Int, values: [RiverDestination])]
    private let contextByPhase: [(from: Int, text: String)]
    private let exactMonthContext: [Int: String]

    // MARK: Lookups

    func destinations(at month: Int) -> [RiverDestination] {
        destinationsByPhase.last(where: { $0.from <= month })?.values ?? destinationsByPhase[0].values
    }

    func context(at month: Int) -> String {
        if let exact = exactMonthContext[month] { return exact }
        return contextByPhase.last(where: { $0.from <= month })?.text ?? ""
    }

    func milestone(at month: Int) -> Milestone? { milestones.first { $0.month == month } }

    /// The keyframe pair bracketing `month` and the 0…1 progress between them. The river is
    /// always in motion across the whole span, arriving exactly on each dated state; a half-
    /// smoothstep ease softens the turn at each milestone without ever stopping.
    func segment(at month: Double) -> (from: RiverKeyframe, to: RiverKeyframe, t: Double) {
        guard let index = keyframes.lastIndex(where: { Double($0.month) <= month }) else {
            return (keyframes[0], keyframes[0], 0)
        }
        let from = keyframes[index]
        guard index + 1 < keyframes.count else { return (from, from, 0) }
        let to = keyframes[index + 1]
        let span = Double(max(to.month - from.month, 1))
        let raw = min(max((month - Double(from.month)) / span, 0), 1)
        return (from, to, 0.5 * raw + 0.5 * raw * raw * (3 - 2 * raw))
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
        var timeline = profile.id == Profile.morgan.id ? morgan(profile) : steady(profile)
        timeline.alreadyMet = planEvents(for: profile).alreadyMet
        return timeline
    }

    /// The shortest window that still reads as a plan.
    static let minimumWindow = 48

    /// Plan events from the engine's adaptive projection: dated milestones, the goals already
    /// met today, and the window that holds them. Nothing here is estimated; with no
    /// calculation (the illustrative preview) there are no dated milestones at all.
    static func planEvents(for profile: Profile) -> (milestones: [Milestone], alreadyMet: [String], lastMonth: Int) {
        guard let evaluation = profile.evaluation, evaluation.projections.adaptive.feasible else {
            return ([], [], minimumWindow)
        }
        let adaptive = evaluation.projections.adaptive
        let retirement = evaluation.financialState.monthsUntilRetirement
        var dated: [Milestone] = []
        var met: [String] = []
        // nil means the goal isn't reached before retirement: neither dated nor met.
        for (month, title, metTitle) in [(adaptive.debtFreeMonth, "Debt cleared", "Debt-free"),
                                         (adaptive.starterReserveMonth, "Starter reserve reached", "Starter reserve"),
                                         (adaptive.fullReserveMonth, "Reserve target reached", "Full reserve")] {
            guard let month else { continue }
            if month == 0 { met.append(metTitle) } else { dated.append(Milestone(month: month, title: title)) }
        }
        // Run to the last plan event, rounded up to a whole year; otherwise a short plan
        // shows through retirement (Casey) and a long one shows its first four years.
        var window = minimumWindow
        if let last = dated.map(\.month).max() {
            window = max(window, (last + 11) / 12 * 12)
        } else if retirement <= 120 {
            window = max(window, retirement)
        }
        window = min(window, retirement)
        if retirement <= window { dated.append(Milestone(month: retirement, title: "Retirement")) }
        // Two events in the same month share one marker.
        let unique = Dictionary(dated.map { ($0.month, $0) }, uniquingKeysWith: { a, b in
            Milestone(month: a.month, title: "\(a.title) · \(b.title.lowercased())")
        })
        return (unique.values.sorted { $0.month < $1.month }, met, window)
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

    /// Morgan: the three dated Figma states. Dated milestones appear only when their months
    /// come from the engine's adaptive projection — never from the schematic preview
    /// (REPORT B5). Phase copy follows the validated priority order (REPORT B3).
    private static func morgan(_ profile: Profile) -> ExploreTimeline {
        let open = opening(profile)
        // Schematic phase months keep the river's shape in preview; they carry no dates.
        var debtCleared = 24, reserveMet = 40
        var milestones: [Milestone] = []
        var exactMonthContext: [Int: String] = [0: "Opening month"]
        // What follows high-APR debt in the validated order names the middle phase.
        let order = profile.evaluation?.decisionSummary.orderedPriorities
        let afterDebt = order.flatMap { o in o.firstIndex(of: .highAprDebt).flatMap { o.dropFirst($0 + 1).first } }
        let buildingPhase = afterDebt == .starterReserve ? "Building the starter reserve" : "Building reserves"
        if let adaptive = profile.evaluation?.projections.adaptive,
           let debt = adaptive.debtFreeMonth, let reserve = adaptive.fullReserveMonth,
           0 < debt, debt < reserve, reserve <= 48 {
            debtCleared = debt
            reserveMet = reserve
            milestones = [Milestone(month: debt, title: "Debt cleared"),
                          Milestone(month: reserve, title: "Reserve target reached")]
            exactMonthContext[debt] = "Debt cleared · \(buildingPhase.lowercased())"
            exactMonthContext[reserve] = "Reserve target reached"
        }
        return ExploreTimeline(
            lastMonth: 48,
            keyframes: [
                RiverKeyframe(month: 0, counts: open.counts),
                RiverKeyframe(month: debtCleared, counts: [open.counts[0], streamCount - open.counts[0], 0]),
                RiverKeyframe(month: reserveMet, counts: [streamCount, 0, 0])
            ],
            milestones: milestones,
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
                (debtCleared, buildingPhase),
                (reserveMet, "Contribution increased")
            ],
            exactMonthContext: exactMonthContext
        )
    }

    /// Every profile but Morgan: the plan keeps its opening allocation, and the timeline marks
    /// the engine's own events (e.g. Jordan's loan paid off, Casey's retirement).
    private static func steady(_ profile: Profile) -> ExploreTimeline {
        let open = opening(profile)
        let events = planEvents(for: profile)
        let debtCleared = events.milestones.first { $0.title.hasPrefix("Debt cleared") }?.month
        let retirementMonth = profile.evaluation?.financialState.monthsUntilRetirement
        let retirement = retirementMonth.flatMap { $0 <= events.lastMonth ? $0 : nil }
        var contextByPhase: [(from: Int, text: String)] = [(0, "Opening month"), (1, "Plan maintained")]
        var exactMonthContext: [Int: String] = [0: "Opening month"]
        if let debtCleared {
            contextByPhase.append((debtCleared, "Debt-free · plan maintained"))
        }
        if let retirement {
            contextByPhase.append((retirement, "Retirement"))
        }
        for milestone in events.milestones { exactMonthContext[milestone.month] = milestone.title }
        return ExploreTimeline(
            lastMonth: events.lastMonth,
            keyframes: [RiverKeyframe(month: 0, counts: open.counts)],
            milestones: events.milestones,
            tracks: TimelineTracks(debtPayoff: debtCleared.map { 0...$0 }),
            thirdColumnTitle: open.third,
            destinationsByPhase: [
                (0, open.destinations),
                (1, [RiverDestination(title: "Retirement", value: "Maintain", caption: "contribution policy"),
                     RiverDestination(title: "Reserves", value: "Target met", caption: "emergency savings"),
                     RiverDestination(title: open.third, value: open.destinations[2].value,
                                      caption: open.destinations[2].caption)])
            ],
            contextByPhase: contextByPhase.sorted { $0.from < $1.from },
            exactMonthContext: exactMonthContext
        )
    }
}
