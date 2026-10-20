import Foundation

/// Sessions of one project directory, in board order.
public struct BoardGroup: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var sessions: [SessionState]
}

/// Board layout: status tiers, then start order or the user's, grouped by project.
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

    /// Groups come in the tier of their most urgent session, cards within a group by tier; inside a
    /// tier, sessions the user placed keep their place and the rest follow by start time.
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
        var groups: [BoardGroup] = []
        var index: [String: Int] = [:]
        for s in ordered {
            let key = s.groupDir ?? s.id
            if let i = index[key] {
                groups[i].sessions.append(s)
            } else {
                index[key] = groups.count
                groups.append(BoardGroup(id: key, name: s.projectName ?? s.agent.displayName, sessions: [s]))
            }
        }
        for i in groups.indices {
            // Stable sort: manual / start order survives within a tier.
            groups[i].sessions = groups[i].sessions.enumerated()
                .sorted { (tier($0.element.display), $0.offset) < (tier($1.element.display), $1.offset) }.map(\.element)
        }
        return groups.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    private static func rank(_ g: BoardGroup) -> Int { g.sessions.map { tier($0.display) }.min() ?? 3 }

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
