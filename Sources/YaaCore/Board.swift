import Foundation

/// Sessions of one project directory, in board order.
public struct BoardGroup: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var sessions: [SessionState]
}

/// Board layout: start order, user overrides, and grouping by project.
public enum Board {
    /// Sessions the user placed keep their place; the rest follow by start time. Each project's
    /// sessions are gathered at the position of its first one.
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
