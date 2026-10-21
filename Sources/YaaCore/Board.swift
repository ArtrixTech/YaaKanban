import Foundation

/// A run of cards of one project directory, next to each other on the board.
public struct BoardGroup: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var sessions: [SessionState]
}

/// Board layout: one list, most urgent first. Status decides the order; within a status, cards of
/// one project sit together, so they read as a group without any box around them.
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

    /// Cards by tier; inside a tier, projects in the order of their first card (sessions the user
    /// placed keep their place, the rest follow by start time), each project's cards together. A
    /// project that ends one tier opens the next, so its run carries on across. Consecutive cards
    /// of one project form a group; a project can have groups in several tiers.
    public static func groups(_ sessions: [SessionState], manualOrder: [String]) -> [BoardGroup] {
        let pos = Dictionary(manualOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let ordered = sessions.sorted { a, b in
            switch (pos[a.id], pos[b.id]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return (a.startedAt, a.id) < (b.startedAt, b.id)
            }
        }
        func key(_ s: SessionState) -> String { s.groupDir ?? s.id }
        var flat: [SessionState] = []
        for t in 0...3 {
            var clusters: [[SessionState]] = []
            var index: [String: Int] = [:]
            for s in ordered where tier(s.display) == t {
                if let i = index[key(s)] { clusters[i].append(s) } else { index[key(s)] = clusters.count; clusters.append([s]) }
            }
            if let last = flat.last, let i = index[key(last)], i > 0 { clusters.insert(clusters.remove(at: i), at: 0) }
            flat += clusters.joined()
        }
        var groups: [BoardGroup] = []
        for s in flat {
            if let g = groups.last, g.sessions.first.map(key) == key(s) {
                groups[groups.count - 1].sessions.append(s)
            } else {
                groups.append(BoardGroup(id: key(s) + "#" + s.id, name: s.projectName ?? s.agent.displayName, sessions: [s]))
            }
        }
        return groups
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
