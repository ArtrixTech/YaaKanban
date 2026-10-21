import Foundation

/// Board layout: one list, most urgent first. Status decides the order; within a status, sessions
/// the user placed keep their place and the rest follow by start time.
public enum Board {
    /// Status tier, most urgent first: waiting on the user, to review, running, reviewed.
    public static func tier(_ s: DisplayStatus) -> Int {
        switch s {
        case .needsInput, .stuck: 0
        case .review: 1
        case .running: 2
        case .done, .ended: 3
        }
    }

    public static func ordered(_ sessions: [SessionState], manualOrder: [String]) -> [SessionState] {
        let pos = Dictionary(manualOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return sessions.sorted { a, b in
            let ta = tier(a.display), tb = tier(b.display)
            if ta != tb { return ta < tb }
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
}
