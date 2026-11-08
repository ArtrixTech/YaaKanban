import Foundation

/// Board layout: one list. Pinned sessions come first, newest pin on top unless the user arranged
/// them; then status, most urgent first, decides the order. Finished sessions (to review,
/// reviewed) are freshest first: the latest of their last event and the user's last click, or,
/// for one the user dragged, the freshness of its new place until it is active again. Within the
/// other statuses, sessions the user placed keep their place and the rest follow by start time.
/// The user moves a session only within its group (`lane`).
public enum Board {
    /// Where the user dragged a finished session: it sorts as if last active at `key` until an
    /// event or a click after `at`.
    public struct Placement: Equatable, Sendable {
        public var key: Date
        public var at: Date
        public init(key: Date, at: Date) { self.key = key; self.at = at }
    }

    /// Status tier, most urgent first: waiting on the user, to review, running, reviewed.
    public static func tier(_ s: DisplayStatus) -> Int {
        switch s {
        case .needsInput, .stuck: 0
        case .review: 1
        case .running: 2
        case .done, .ended: 3
        }
    }

    /// Whether the user can place sessions of this status by hand (finished ones sort by freshness).
    public static func keepsManualOrder(_ s: DisplayStatus) -> Bool { tier(s) == tier(.running) || tier(s) == tier(.needsInput) }

    /// What a finished session sorts by: its freshness, or the place it was dragged to.
    public static func freshness(_ s: SessionState, placed: [String: Placement]) -> Date {
        if let p = placed[s.id], s.quietSince <= p.at { return p.key }
        return s.quietSince
    }

    public static func ordered(_ sessions: [SessionState], manualOrder: [String], pinned: [String] = [],
                               placed: [String: Placement] = [:]) -> [SessionState] {
        let pos = Dictionary(manualOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let pin = Dictionary(pinned.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return sessions.sorted { a, b in
            switch (pin[a.id], pin[b.id]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): break
            }
            let ta = tier(a.display), tb = tier(b.display)
            if ta != tb { return ta < tb }
            if !keepsManualOrder(a.display) {
                let (fa, fb) = (freshness(a, placed: placed), freshness(b, placed: placed))
                if fa != fb { return fa > fb }
                return a.id < b.id
            }
            switch (pos[a.id], pos[b.id]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return (a.startedAt, a.id) < (b.startedAt, b.id)
            }
        }
    }

    /// New manual order after dropping `moving` before `target` (nil: to the end). Ids not on the
    /// board are kept at the end so a session that comes back finds its place.
    public static func move(_ moving: [String], before target: String?, board: [String], manualOrder: [String]) -> [String] {
        let set = Set(moving)
        var order = board.filter { !set.contains($0) }
        let at = target.flatMap { order.firstIndex(of: $0) } ?? order.endIndex
        order.insert(contentsOf: moving.filter(board.contains), at: at)
        let onBoard = Set(board)
        return order + manualOrder.filter { !onBoard.contains($0) }
    }

    /// The sessions `id` can trade places with on `board`, itself included, in board order: the
    /// pinned ones, or the unpinned ones of its status tier.
    public static func lane(of id: String, board: [SessionState], pinned: [String]) -> [String] {
        guard let s = board.first(where: { $0.id == id }) else { return [] }
        let pins = Set(pinned)
        if pins.contains(id) { return board.filter { pins.contains($0.id) }.map(\.id) }
        let t = tier(s.display)
        return board.filter { !pins.contains($0.id) && tier($0.display) == t }.map(\.id)
    }

    /// Placement that sorts a finished session between two neighbours' freshness (nil past an end).
    public static func placement(between above: Date?, and below: Date?, now: Date) -> Placement {
        let key: Date = switch (above, below) {
        case let (a?, b?): Date(timeIntervalSinceReferenceDate: (a.timeIntervalSinceReferenceDate + b.timeIntervalSinceReferenceDate) / 2)
        case let (a?, nil): a.addingTimeInterval(-1)
        case let (nil, b?): b.addingTimeInterval(1)
        case (nil, nil): now
        }
        return Placement(key: key, at: now)
    }
}
