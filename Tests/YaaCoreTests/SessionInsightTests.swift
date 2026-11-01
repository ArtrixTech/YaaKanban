import Foundation
import Testing
@testable import YaaCore

private let t0 = Date(timeIntervalSince1970: 2_000_000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

private func tool(_ id: String, _ name: String, _ summary: String, at s: TimeInterval, error: Bool = false) -> ToolCall {
    ToolCall(id: id, name: name, summary: summary, input: "", output: nil, isError: error, startedAt: at(s), endedAt: at(s + 1))
}

@Suite struct ToolKinds {
    @Test func byName() {
        #expect(ToolKind.of("Read") == .explore)
        #expect(ToolKind.of("grep") == .explore)
        #expect(ToolKind.of("Edit") == .edit)
        #expect(ToolKind.of("apply_patch") == .edit)
        #expect(ToolKind.of("WebSearch") == .web)
        #expect(ToolKind.of("mcp__codex_apps__github__fetch") == .web)
        #expect(ToolKind.of("Agent") == .delegate)
        #expect(ToolKind.of("collaborationspawn_agent") == .delegate)
        #expect(ToolKind.of("AskUserQuestion") == .ask)
        #expect(ToolKind.of("TodoWrite") == .other)
        #expect(ToolKind.of("mcp__fusion-mcp__execute_python") == .run)
    }

    @Test func shellCommands() {
        #expect(ToolKind.of("Bash", summary: "make test") == .verify)
        #expect(ToolKind.of("bash", summary: "cd ~/x && swift build 2>&1 | tail") == .verify)
        #expect(ToolKind.of("Bash", summary: "rtk bypass grep -rn foo Sources | cut -c1-100") == .explore)
        #expect(ToolKind.of("Bash", summary: "cd /x && git status --short; git log --oneline -3") == .explore)
        #expect(ToolKind.of("Bash", summary: "ls 2>/dev/null | head") == .explore)
        #expect(ToolKind.of("Bash", summary: "cat > a.py <<'EOF'") == .run)
        #expect(ToolKind.of("Bash", summary: "sed -i '' 's/a/b/' f") == .run)
        #expect(ToolKind.of("Bash", summary: "python3 script.py") == .run)
        #expect(ToolKind.of("Bash", summary: "git commit -m x") == .run)
    }

    @Test func buildsAndTestsOnlyAtACommandsHead() {
        #expect(ToolKind.of("Bash", summary: "npx tsc --noEmit") == .verify)
        #expect(ToolKind.of("Bash", summary: "FOO=1 make test") == .verify)
        #expect(ToolKind.of("Bash", summary: "cat tsconfig.json") == .explore)
        #expect(ToolKind.of("Bash", summary: "rg eslint src") == .explore)
        #expect(ToolKind.of("Bash", summary: "grep -n 'make test' Makefile") == .explore)
    }

    @Test func files() {
        #expect(ToolKind.touchesFile("Read"))
        #expect(ToolKind.touchesFile("MultiEdit"))
        #expect(!ToolKind.touchesFile("Bash"))
        #expect(!ToolKind.touchesFile("Grep"))
    }
}

@Suite struct Insights {
    private func session() -> SessionState {
        var s = SessionState(agent: .claudeCode, sessionId: "s", at: at(0))
        s.turns = [Turn(id: 1, prompt: "look", startedAt: at(0), endedAt: at(100), toolCount: 3),
                   Turn(id: 2, prompt: "fix", startedAt: at(200), endedAt: nil, toolCount: 3)]
        s.tools = [tool("a", "Read", "~/x/A.swift", at: 1), tool("b", "Read", "~/x/A.swift", at: 2),
                   tool("c", "Bash", "ls", at: 3),
                   tool("d", "Edit", "~/x/A.swift", at: 201), tool("e", "Edit", "~/x/B.swift", at: 202, error: true),
                   tool("f", "Bash", "make test", at: 203)]
        return s
    }

    @Test func turnsGetTheirTools() {
        let i = SessionInsight(session())
        #expect(i.turns.map(\.tools.count) == [3, 3])
        #expect(i.turns[0].phases.map(\.kind) == [.explore])
        #expect(i.turns[0].phases.first?.count == 3)
        #expect(i.turns[1].phases.map(\.kind) == [.edit, .verify])
        #expect(i.turns[1].editedFiles == ["~/x/A.swift", "~/x/B.swift"])
        #expect(i.turns[1].failures == 1)
        #expect(i.turns[1].commands == 1)
        #expect(i.turns[0].followedAt == at(200))
        #expect(i.turns.allSatisfy { $0.complete })
        #expect(!i.truncated)
    }

    @Test func filesAndFailures() {
        let i = SessionInsight(session())
        #expect(i.files.map(\.path) == ["~/x/A.swift", "~/x/B.swift"])
        #expect(i.files[0].reads == 2 && i.files[0].edits == 1)
        #expect(i.files[1].failed == 1)
        #expect(i.failures.map(\.id) == ["e"])
        #expect(i.kinds.first?.kind == .explore)
    }

    @Test func droppedToolsMarkTurnsIncomplete() {
        var s = session()
        s.tools.removeFirst(2)
        let i = SessionInsight(s)
        #expect(!i.turns[0].complete)
        #expect(i.truncated)
    }

    @Test func injectedPromptsAreNotTheUsers() {
        func turn(_ p: String) -> Turn { Turn(id: 1, prompt: p, startedAt: at(0), endedAt: nil, toolCount: 0) }
        #expect(turn("fix it").byUser)
        #expect(!turn("").byUser)
        #expect(!turn("<command-name>/clear</command-name>").byUser)
        #expect(!turn("<task-notification>\n<task-id>x</task-id>").byUser)
        #expect(turn("<task-notification>\n<task-id>x</task-id>").reportsTask)
        #expect(!turn("fix it").reportsTask)
    }

    @Test func unstoppedTurnsEndAtTheNextPrompt() {
        var s = session()
        s.status = .idle
        s.lastEventAt = at(250)
        // An interrupt: no Stop for turn 1; turn 2 never stopped either, and the session went idle.
        s.turns[0].endedAt = nil
        let i = SessionInsight(s)
        #expect(i.turns[0].duration(now: at(99_999)) == 200)
        #expect(i.turns[1].duration(now: at(99_999)) == 50)
        #expect(i.agentTime(now: at(99_999)) == 250)
        #expect(i.turns[0].followedAt == at(200))
        // A background task reporting back is not the user coming back.
        s.turns[1].prompt = "<task-notification>"
        #expect(SessionInsight(s).turns[0].followedAt == nil)
        // Rebuilt spans meet, never overlap.
        let t = SessionTimeline(rows: [], session: s, now: at(99_999))
        #expect(t.spans.map(\.end) == [at(200), at(250)])
        // Calls after an early Stop still belong to the turn's time.
        s.turns[0].endedAt = at(1)
        #expect(SessionInsight(s).turns[0].duration(now: at(0)) == 4)
        // A late Stop before its own prompt is not a negative time; its calls still count.
        s.turns[0].endedAt = at(-10)
        #expect(SessionInsight(s).turns[0].duration(now: at(0)) == 4)
        // Calls never stretch a turn past the next prompt.
        s.turns[0].endedAt = nil
        s.tools[1].endedAt = at(300)
        #expect(SessionInsight(s).turns[0].duration(now: at(0)) == 200)
    }

    @Test func subagentCallsLeftOut() {
        var s = session()
        s.tools[0].subagentId = "sub"
        let t = SessionInsight(s).turns[0]
        #expect(t.tools.count == 2)
        // Its sub-agent's call still counts toward the turn's calls: nothing was dropped.
        #expect(t.complete)
    }
}

@Suite struct Timelines {
    private func lane(_ s: TimeInterval, _ l: Lane?) -> ActivityRow {
        ActivityRow(at: at(s), session: "claude-code:s", kind: .lane, text: l?.rawValue ?? "")
    }

    @Test func spansFromLaneRows() {
        var s = SessionState(agent: .claudeCode, sessionId: "s", at: at(0))
        s.status = .running
        let rows = [lane(0, .running), lane(60, .needsInput), lane(90, .running), lane(150, .review), lane(400, nil),
                    lane(5000, .running),
                    ActivityRow(at: at(90), session: "claude-code:s", kind: .reply, value: 30)]
        let t = SessionTimeline(rows: rows, session: s, now: at(5100))
        #expect(t.spans.map(\.lane) == [.running, .needsInput, .running, .review, .running])
        #expect(t.total(.running) == 60 + 60 + 100)
        #expect(t.total(.needsInput) == 30)
        #expect(t.answered == 1)
        #expect(t.meanReply == 30)
        #expect(!t.rebuilt)
        let p = t.pieces(fold: 600)
        // The long gap after review folds; the bar keeps every span.
        #expect(p.map(\.lane) == [.running, .needsInput, .running, .review, nil, .running])
        #expect(p[4].folded && p[4].weight == 600)
        #expect(SessionTimeline.fraction(at(0), in: p) == 0)
        #expect(SessionTimeline.fraction(at(5100), in: p) == 1)
        let mid = SessionTimeline.fraction(at(60), in: p)
        #expect(abs(mid - 60.0 / (400 + 600 + 100)) < 1e-9)
    }

    @Test func storeReadsOneSessionsLanesAndReplies() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yaak-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try Store(path: url)
        store.record([ActivityRow(at: at(10), session: "a", kind: .lane, text: "running"),
                      ActivityRow(at: at(5), session: "a", kind: .lane, text: "needsInput"),
                      ActivityRow(at: at(20), session: "a", kind: .reply, value: 15),
                      ActivityRow(at: at(20), session: "a", kind: .turn, value: 3),
                      ActivityRow(at: at(30), session: "b", kind: .lane, text: "running"),
                      ActivityRow(at: at(40), session: "", kind: .away, value: 60)])
        let rows = store.activity(session: "a")
        #expect(rows.map(\.kind) == [.lane, .lane, .reply])
        #expect(rows.map(\.at) == [at(5), at(10), at(20)])
    }

    @Test func anAskCutShortByAPromptIsNotAnAnswer() {
        var s = SessionState(agent: .claudeCode, sessionId: "s", at: at(0))
        s.status = .running
        s.turns = [Turn(id: 1, prompt: "a", startedAt: at(0), endedAt: nil, toolCount: 0),
                   Turn(id: 2, prompt: "b", startedAt: at(90), endedAt: nil, toolCount: 0)]
        let rows = [lane(0, .running), lane(30, .needsInput), lane(50, .running), lane(60, .needsInput), lane(90, .running)]
        // Answered at 50; at 90 the user typed a new prompt instead.
        #expect(SessionTimeline(rows: rows, session: s, now: at(100)).answered == 1)
    }

    @Test func rebuiltFromTurns() {
        var s = SessionState(agent: .claudeCode, sessionId: "s", at: at(0))
        s.status = .idle
        s.lastEventAt = at(50)
        s.turns = [Turn(id: 1, prompt: "a", startedAt: at(0), endedAt: at(40), toolCount: 0)]
        let t = SessionTimeline(rows: [], session: s, now: at(1000))
        #expect(t.rebuilt)
        #expect(t.spans == [.init(lane: .running, start: at(0), end: at(40))])
    }

    @Test func openLaneEndsAtLastEventOnceOffTheBoard() {
        var s = SessionState(agent: .claudeCode, sessionId: "s", at: at(0))
        s.status = .idle
        s.lastEventAt = at(30)
        let t = SessionTimeline(rows: [lane(0, .running)], session: s, now: at(1000))
        #expect(t.spans.last?.end == at(30))
    }
}

@Suite struct MarkdownBlocks {
    @Test func blocks() {
        let md = """
        ## 结论

        CPU 占用 **47–59%**。
        第二行

        1. 主线程重绘
           继续这一项
        2. 写 SQLite
        - [ ] todo

        ```swift
        let a = 1
        ```
        > 引用
        ---
        | a | b |
        |---|:-:|
        | 1 | 2 |
        """
        #expect(Markdown.blocks(md) == [
            .heading(level: 2, text: "结论"),
            .paragraph("CPU 占用 **47–59%**。\n第二行"),
            .listItem(indent: 0, marker: "1.", text: "主线程重绘\n继续这一项"),
            .listItem(indent: 0, marker: "2.", text: "写 SQLite"),
            .listItem(indent: 0, marker: "•", text: "☐ todo"),
            .code(language: "swift", text: "let a = 1"),
            .quote("引用"),
            .rule,
            .table(header: ["a", "b"], rows: [["1", "2"]]),
        ])
    }

    @Test func fences() {
        let nested = "````markdown\n```swift\nlet x = 1\n```\n````\nafter"
        #expect(Markdown.blocks(nested) == [.code(language: "markdown", text: "```swift\nlet x = 1\n```"), .paragraph("after")])
        // A closing fence has no info string; an inline triple-backtick span is not a fence.
        #expect(Markdown.blocks("```\na\n```py\n```") == [.code(language: nil, text: "a\n```py")])
        #expect(Markdown.blocks("```foo``` then\n\nnext") == [.paragraph("```foo``` then"), .paragraph("next")])
        // Unterminated: the rest is code.
        #expect(Markdown.blocks("~~~\nx") == [.code(language: nil, text: "x")])
    }

    @Test func deepIndentsAndTabs() {
        #expect(Markdown.blocks("\t- a") == [.listItem(indent: 1, marker: "•", text: "a")])
        #expect(Markdown.blocks(String(repeating: " ", count: 400) + "- a") == [.listItem(indent: 6, marker: "•", text: "a")])
    }

    @Test func folding() {
        let b: [MarkdownBlock] = [.paragraph(String(repeating: "a", count: 300)), .paragraph(String(repeating: "b", count: 300)), .paragraph("c")]
        #expect(Markdown.folded(b, limit: 400).count == 1)
        #expect(Markdown.folded(b, limit: 1000).count == 3)
        // One block far past the limit is cut, so the reply still folds.
        let one: [MarkdownBlock] = [.code(language: nil, text: String(repeating: "x", count: 900))]
        #expect(Markdown.folded(one, limit: 100) == [.code(language: nil, text: String(repeating: "x", count: 100) + "…")])
    }
}
