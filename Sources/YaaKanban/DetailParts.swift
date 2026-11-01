import SwiftUI
import YaaCore

// Pieces of the session detail page (`DetailView.swift`): its cards, figures, bars and the
// Markdown an agent replies in.

extension ToolKind {
    var label: String {
        switch self {
        case .explore: String(localized: "Explore")
        case .edit: String(localized: "Edit")
        case .run: String(localized: "Commands")
        case .verify: String(localized: "Build & test")
        case .web: String(localized: "Web")
        case .delegate: String(localized: "Delegate")
        case .ask: String(localized: "Ask you")
        case .other: String(localized: "Other")
        }
    }

    /// Hues apart from the status colors, so a phase never reads as a session state.
    var tint: Color {
        switch self {
        case .explore: .teal
        case .edit: .indigo
        case .run: Color(light: NSColor(white: 0.45, alpha: 1), dark: NSColor(white: 0.62, alpha: 1))
        case .verify: .mint
        case .web: .pink
        case .delegate: .brown
        case .ask: Ramp.wait.hue
        case .other: Color.primary.opacity(0.18)
        }
    }
}

/// A titled card of the detail page: its label and an optional note opposite.
struct DetailCard<Content: View>: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary
    var trailing: String?
    /// The surface: neutral, or the status wash of a card that wants the user.
    var surface: DisplayStatus = .done
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: symbol).font(.ui(.callout, .semibold)).foregroundStyle(tint)
                Spacer(minLength: Space.m)
                if let trailing { Text(trailing).font(.ui(.footnote)).foregroundStyle(.tertiary).lineLimit(1) }
            }
            content
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(surface, radius: Radius.group)
    }
}

/// One of the figures at the top: what it is, the figure, a note under it.
struct StatTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label(title, systemImage: symbol).font(.ui(.footnote, .medium)).foregroundStyle(tint).lineLimit(1)
            unitFigure(value, size: 22)
            Text(note ?? " ").font(.ui(.footnote)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, Space.xl).padding(.vertical, Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(.done, radius: Radius.group)
    }
}

/// "2.5M", "4m 30s": digits in the primary ink, units smaller and gray.
func unitFigure(_ text: String, size: CGFloat) -> Text {
    var out = Text(verbatim: "")
    var run = "", digits = true
    func flush() {
        guard !run.isEmpty else { return }
        out = out + (digits ? Text(verbatim: run).font(.figure(size)).foregroundStyle(.primary)
                            : Text(verbatim: run).font(.system(size: (size * 0.55).rounded(), weight: .semibold)).foregroundStyle(.secondary))
        run = ""
    }
    for c in text {
        let d = "0123456789.,:".contains(c)
        if d != digits { flush(); digits = d }
        run.append(c)
    }
    flush()
    return out
}

/// A short fact under a turn: "3 files edited", "2 failed".
struct Fact: View {
    let symbol: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: symbol).font(.ui(.footnote, .medium)).foregroundStyle(tint).lineLimit(1)
            .labelStyle(FactLabel())
    }

    private struct FactLabel: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 3) { configuration.icon.font(.system(size: 9.5, weight: .semibold)); configuration.title }
        }
    }
}

/// The facts of one turn, as a row.
struct TurnFacts: View {
    let turn: TurnInsight
    var now = Date()

    var body: some View {
        HStack(spacing: Space.l) {
            Fact(symbol: "clock", text: duration(turn.duration(now: now)))
            if turn.turn.toolCount > 0 { Fact(symbol: "wrench.and.screwdriver", text: String(localized: "\(turn.turn.toolCount) tools")) }
            let files = turn.editedFiles.count
            if files > 0 { Fact(symbol: "pencil", text: files == 1 ? String(localized: "1 file edited") : String(localized: "\(files) files edited")) }
            if turn.commands > 0 { Fact(symbol: "terminal", text: String(localized: "\(turn.commands) commands")) }
            if turn.failures > 0 { Fact(symbol: "xmark.circle", text: String(localized: "\(turn.failures) failed"), tint: .red) }
        }
    }
}

/// A turn's calls as stretches of their kind, in order, each as wide as its share of the calls.
struct PhaseStrip: View {
    let phases: [(kind: ToolKind, count: Int)]
    var height: CGFloat = 5

    var body: some View {
        let total = max(1, phases.reduce(0) { $0 + $1.count })
        GeometryReader { g in
            // Crowded strips lose their gaps and minimum widths rather than run past the card.
            let crowded = CGFloat(phases.count) * 3.5 > g.size.width
            let gap: CGFloat = phases.count > 1 && !crowded ? 1.5 : 0
            let room = max(0, g.size.width - gap * CGFloat(phases.count - 1))
            HStack(spacing: gap) {
                ForEach(phases.indices, id: \.self) { i in
                    Capsule().fill(phases[i].kind.tint)
                        .frame(width: max(crowded ? 0 : 2, room * CGFloat(phases[i].count) / CGFloat(total)))
                }
            }
            .frame(width: g.size.width, alignment: .leading)
            .clipped()
        }
        .frame(height: height)
        .help(phases.map { "\($0.kind.label) ×\($0.count)" }.joined(separator: " → "))
    }
}

/// Shares of a whole as one bar with a key under it: the tool mix, the token parts.
struct ShareBar: View {
    struct Part: Identifiable {
        let id: String
        let label: String
        let value: Double
        let tint: Color
        var note: String?
    }
    let parts: [Part]

    var body: some View {
        let shown = parts.filter { $0.value > 0 }
        let total = max(1, shown.reduce(0) { $0 + $1.value })
        VStack(alignment: .leading, spacing: Space.m) {
            GeometryReader { g in
                let gap: CGFloat = 2
                let room = max(0, g.size.width - gap * CGFloat(max(0, shown.count - 1)))
                HStack(spacing: gap) {
                    ForEach(shown) { p in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(p.tint)
                            .frame(width: max(3, room * p.value / total))
                    }
                }
            }
            .frame(height: 8)
            FlowKeys(parts: shown)
        }
    }

    private struct FlowKeys: View {
        let parts: [Part]
        var body: some View {
            // Two columns read better than one long wrapped row.
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: Space.xs) {
                ForEach(parts) { p in
                    HStack(spacing: Space.s) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(p.tint).frame(width: 8, height: 8)
                        Text(p.label).foregroundStyle(.secondary)
                        Text(p.note ?? "").font(.figure(TextSize.footnote.rawValue, .medium)).foregroundStyle(.primary)
                    }
                    .font(.ui(.footnote)).lineLimit(1)
                }
            }
        }
    }
}

/// The session's states along one bar: running, waiting on you, to review, stuck; long waits and
/// gaps drawn short and hatched. Turn starts tick above it.
struct TimeBar: View {
    let pieces: [SessionTimeline.Piece]
    let ticks: [Date]

    var body: some View {
        let total = pieces.reduce(0) { $0 + $1.weight }
        VStack(spacing: 3) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    ForEach(ticks.indices, id: \.self) { i in
                        Capsule().fill(Color.primary.opacity(0.3)).frame(width: 1.5, height: 6)
                            .offset(x: g.size.width * SessionTimeline.fraction(ticks[i], in: pieces) - 0.75)
                    }
                }
            }
            .frame(height: 6)
            GeometryReader { g in
                HStack(spacing: 0) {
                    ForEach(pieces.indices, id: \.self) { i in
                        piece(pieces[i]).frame(width: total > 0 ? g.size.width * pieces[i].weight / total : 0)
                    }
                }
                .clipShape(Capsule())
                .background(Capsule().fill(Fill.control))
            }
            .frame(height: 12)
        }
    }

    @ViewBuilder private func piece(_ p: SessionTimeline.Piece) -> some View {
        let tint = p.lane?.status.tint ?? .clear
        ZStack {
            Rectangle().fill(tint.opacity(p.lane == nil ? 0 : p.lane == .running ? 0.85 : 0.6))
            if p.folded { Hatch().stroke(p.lane == nil ? Color.primary.opacity(0.18) : Color.white.opacity(0.45), lineWidth: 1) }
        }
        .help(help(p))
    }

    private func help(_ p: SessionTimeline.Piece) -> String {
        let span = duration(p.end.timeIntervalSince(p.start))
        guard let lane = p.lane else { return String(localized: "Nothing going on · \(span)") }
        return "\(lane.status.label) · \(span)"
    }

    /// Diagonal lines: this stretch is drawn shorter than it was.
    private struct Hatch: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            var x = r.minX - r.height
            while x < r.maxX {
                p.move(to: CGPoint(x: x, y: r.maxY))
                p.addLine(to: CGPoint(x: x + r.height, y: r.minY))
                x += 4
            }
            return p
        }
    }
}

/// What an agent replied, drawn from its Markdown.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ForEach(blocks.indices, id: \.self) { i in block(blocks[i]) }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func block(_ b: MarkdownBlock) -> some View {
        switch b {
        case .heading(let level, let text):
            Text(inline(text)).font(.ui(level <= 2 ? .headline : .body, .semibold)).padding(.top, Space.xs)
        case .paragraph(let text):
            Text(inline(text)).font(.ui(.body)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        case .listItem(let indent, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(marker).font(.ui(.body, marker == "•" ? .bold : .medium)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(minWidth: 14, alignment: .trailing)
                Text(inline(text)).font(.ui(.body)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .code(_, let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text).font(.system(size: 11.5, design: .monospaced)).padding(Space.m)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Fill.control, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        case .quote(let text):
            Text(inline(text)).font(.ui(.body)).foregroundStyle(.secondary)
                .padding(.leading, Space.m)
                .overlay(alignment: .leading) { Capsule().fill(Color.primary.opacity(0.15)).frame(width: 3) }
        case .table(let header, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: Space.l, verticalSpacing: Space.xs) {
                    GridRow { ForEach(header.indices, id: \.self) { Text(inline(header[$0])).font(.ui(.callout, .semibold)) } }
                    ForEach(rows.indices, id: \.self) { r in
                        GridRow { ForEach(rows[r].indices, id: \.self) { Text(inline(rows[r][$0])).font(.ui(.callout)) } }
                    }
                }
                .padding(Space.m)
            }
            .background(Fill.control.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        case .rule:
            Capsule().fill(Color.primary.opacity(0.1)).frame(height: 1)
        }
    }

    private func inline(_ text: String) -> AttributedString { MarkdownCache.inline(text) }
}

/// Parsed replies, so drawing the page again does not parse them again.
@MainActor enum MarkdownCache {
    private static var cache: [String: [MarkdownBlock]] = [:]

    private static var inlines: [String: AttributedString] = [:]

    static func blocks(_ text: String) -> [MarkdownBlock] {
        if let b = cache[text] { return b }
        if cache.count > 64 { cache.removeAll() }
        let b = Markdown.blocks(text)
        cache[text] = b
        return b
    }

    /// Bold, italics, links and code spans inside a block. Links open only on the web: an agent's
    /// text is not trusted to open files or apps.
    static func inline(_ text: String) -> AttributedString {
        if let a = inlines[text] { return a }
        if inlines.count > 1024 { inlines.removeAll() }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var a = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        for run in a.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                a[run.range].font = .system(size: 12, design: .monospaced)
                a[run.range].backgroundColor = Color.primary.opacity(0.07)
            }
            if let url = run.link, !["http", "https"].contains(url.scheme?.lowercased() ?? "") { a[run.range].link = nil }
        }
        inlines[text] = a
        return a
    }
}

/// A reply drawn from its Markdown, folded to its first blocks until opened.
struct ReplyText: View {
    let text: String
    var limit = 700
    @State private var open = false

    var body: some View {
        let all = MarkdownCache.blocks(text)
        let folded = Markdown.folded(all, limit: limit)
        VStack(alignment: .leading, spacing: Space.s) {
            MarkdownView(blocks: open ? all : folded)
            if folded != all {
                Button { withAnimation(.snappy) { open.toggle() } } label: {
                    Label(open ? String(localized: "Show less") : String(localized: "Show the whole reply"),
                          systemImage: open ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.action(.ghost, size: .small))
            }
        }
    }
}
