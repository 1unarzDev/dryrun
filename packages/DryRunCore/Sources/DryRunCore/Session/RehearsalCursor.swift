import Foundation

/// Step-through cursor over a deterministic `RehearsalResult`. The simulated clock is a teaching control:
/// it advances only on user action and stops at unanswered decisions.
public struct RehearsalCursor: Sendable, Equatable {
    public private(set) var result: RehearsalResult
    /// Number of events revealed so far.
    public private(set) var revealed: Int = 0

    public init(result: RehearsalResult) { self.result = result }

    /// Swap in a re-run (e.g. after a choice) without losing the user's place.
    public mutating func replace(result: RehearsalResult) {
        self.result = result
        revealed = min(revealed, result.events.count)
    }

    public var visibleEvents: ArraySlice<SimulationEvent> { result.events.prefix(revealed) }
    public var currentMinute: Int { revealed == 0 ? 0 : result.events[revealed - 1].simMinute }
    public var isFinished: Bool { revealed >= result.events.count && pendingDecision == nil }

    /// The earliest unanswered decision that the cursor has reached: the next event is that decision's own choice event
    /// (`evt.<decisionID>`), or lies after the decision's time. Same-minute events that precede the choice event in the
    /// engine's order (e.g. the smoke alarm) are revealed first.
    public var pendingDecision: DecisionPoint? {
        let next = revealed < result.events.count ? result.events[revealed] : nil
        return result.decisions
            .filter { d in
                guard result.input.choices[d.id] == nil else { return false }
                guard let next else { return true }
                return next.id == "evt.\(d.id)" || next.simMinute > d.simMinute
            }
            .min { ($0.simMinute, $0.id) < ($1.simMinute, $1.id) }
    }

    public mutating func advance() {
        guard pendingDecision == nil, revealed < result.events.count else { return }
        revealed += 1
    }

    public mutating func advanceUntilDecisionOrEnd() {
        while pendingDecision == nil && revealed < result.events.count { revealed += 1 }
    }

    public var snapshotAtCursor: SimulationSnapshot? {
        result.snapshots.last { $0.simMinute <= currentMinute } ?? result.snapshots.first
    }
}

/// Guards asynchronous results: only the newest request whose inputs still match current revisions may apply.
public struct LatestRequestGate: Sendable {
    public struct Ticket: Sendable, Hashable {
        public let sequence: Int
        public let key: RevisionKey
    }
    private var sequence = 0
    public init() {}

    public mutating func begin(for key: RevisionKey) -> Ticket {
        sequence += 1
        return Ticket(sequence: sequence, key: key)
    }

    /// Invalidate all outstanding tickets (e.g. after an edit or delete-all).
    public mutating func invalidate() { sequence += 1 }

    public func shouldApply(_ ticket: Ticket, current: RevisionKey?) -> Bool {
        ticket.sequence == sequence && ticket.key == current
    }
}
