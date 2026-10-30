import AppKit
import SwiftUI

// The shared look of every surface: main window, settings, setup guide, menu, floating panel and
// rail. Tokens first (type, spacing, corners, fills), then the components built from them. Compact
// surfaces (panel, rail, menu) and window surfaces differ by `controlSize`: `.small` and below is
// compact, the rest regular.

/// Type scale. Compact surfaces use the lower half, windows the upper.
enum TextSize: CGFloat {
    case micro = 9, caption = 10, footnote = 11, callout = 12, body = 13, headline = 15, title = 20, display = 24
}

extension Font {
    static func ui(_ size: TextSize, _ weight: Font.Weight = .regular) -> Font { .system(size: size.rawValue, weight: weight) }
    /// Numbers that are the point of a view (figures, counts): the system face at its normal width,
    /// semibold, with fixed-width digits so they don't jitter as they change.
    static func figure(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

/// Spacing on a 4-pt grid, with 2 and 6 for tight compact rows.
enum Space {
    static let xxs: CGFloat = 2, xs: CGFloat = 4, s: CGFloat = 6, m: CGFloat = 8, l: CGFloat = 12, xl: CGFloat = 16, xxl: CGFloat = 20
    /// Margin of a window page (settings, dashboard, detail, guide).
    static let page: CGFloat = 32
    /// Inside an Overview card; a chart bleeding to the card's edges undoes it.
    static let widget: CGFloat = 16
}

/// Corner radii, from chips to windows. Nested shapes step down one level.
enum Radius {
    /// Key caps, small tiles, rail cards.
    static let small: CGFloat = 6
    /// Large icon tiles, figure plates, notices.
    static let medium: CGFloat = 8
    /// Session cards, sidebar rows, dashboard tiles.
    static let card: CGFloat = 12
    /// Grouped cards and sections in a window.
    static let group: CGFloat = 14
    /// The floating panel.
    static let panel: CGFloat = 16
    /// Overview widgets.
    static let widget: CGFloat = 16
    /// An icon or logo tile's corner, in proportion to its size (about 9/40, as app icons).
    static func tile(_ size: CGFloat) -> CGFloat { (size * 0.25).rounded() }
}

extension Color {
    /// One color for the light appearance, another for the dark.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light })
    }

    /// The soft wash behind a tinted badge, chip or notice.
    func soft(_ hover: Bool = false) -> Color { opacity(hover ? 0.2 : 0.13) }
}

/// Neutral surface levels over whatever is behind (glass, material or window background). Surfaces
/// part by fill and space, not lines: in the light appearance cards lift off the background in
/// white, in the dark they are a lighter veil.
enum Fill {
    /// Behind a window page's cards: a light gray, so white cards lift off it.
    static let canvas = Color(light: NSColor(white: 0.955, alpha: 1), dark: .windowBackgroundColor)
    /// A card or group at rest.
    static let card = Color(light: .white.withAlphaComponent(0.85), dark: .white.withAlphaComponent(0.06))
    static let cardHover = Color(light: .white, dark: .white.withAlphaComponent(0.09))
    /// Secondary buttons, key caps, search fields.
    static let control = Color.primary.opacity(0.07)
    static let controlHover = Color.primary.opacity(0.13)
    /// The chosen item in a list or tab row the app draws itself: flat and neutral, so only session
    /// cards carry color.
    static let selected = Color(light: .black.withAlphaComponent(0.07), dark: .white.withAlphaComponent(0.1))
    /// A control's chosen segment, lifted off its track.
    static let raised = Color(light: .white, dark: .white.withAlphaComponent(0.16))
    /// Behind an agent's white logo: dark in both appearances, so the logo always reads.
    static let logo = Color(light: NSColor(white: 0.17, alpha: 1), dark: NSColor(white: 0.3, alpha: 1))
}

/// The brand's green (the logo's dot), for identity moments only; actions use the accent color.
enum Brand {
    static let green = Color(red: 0.06, green: 0.73, blue: 0.51), lime = Color(red: 0.29, green: 0.87, blue: 0.5)
    static let gradient = LinearGradient(colors: [green, lime], startPoint: .top, endPoint: .bottom)
}

// MARK: Finish

/// A solid tint, deep at the top and lighter at the bottom: tiles, primary buttons.
struct Plate<S: Shape>: View {
    let shape: S
    let tint: Color

    var body: some View {
        shape.fill(tint)
            .overlay(shape.fill(LinearGradient(colors: [.black.opacity(0.2), .white.opacity(0.14)], startPoint: .top, endPoint: .bottom)))
    }
}

extension View {
    /// A neutral drawn surface: its fill, and a soft drop that lifts it in the light appearance.
    func surface<S: Shape>(_ shape: S, fill: Color = Fill.card) -> some View {
        background(shape.fill(fill).shadow(color: .black.opacity(0.06), radius: 3, y: 1))
    }

    /// A tinted surface (a session card that wants you), deep at the top and light at the bottom.
    func tinted<S: Shape>(_ shape: S, _ tint: Color, strength: Double = 1) -> some View {
        background(TintWash(shape: shape, tint: tint, strength: strength))
    }
}

private struct TintWash<S: Shape>: View {
    let shape: S
    let tint: Color
    let strength: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // More tint reads deeper over a light background but lighter over a dark one, so the dark
        // appearance runs the stops the other way round to keep the top the deep end.
        let more = 0.12 * strength, less = 0.05 * strength
        shape.fill(LinearGradient(colors: [tint.opacity(scheme == .dark ? less : more), tint.opacity(scheme == .dark ? more : less)],
                                  startPoint: .top, endPoint: .bottom))
    }
}

// MARK: Components

/// A capsule with a state: status, integration, permission. Tinted text on a soft wash.
struct Badge: View {
    let text: String
    var symbol: String?
    let tint: Color
    /// The panel and card size; windows use the regular one.
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.ui(compact ? .caption : .footnote, compact ? .semibold : .medium))
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 6 : 8).padding(.vertical, compact ? 2 : 3)
        .background(tint.soft(), in: Capsule())
        .fixedSize()
    }
}

/// The app's buttons, drawn by hand so they look the same on glass, materials and windows that
/// aren't key. Primary is filled, secondary a soft wash of its tint, ghost only shows on hover.
/// A destructive action is a secondary one tinted red.
struct ActionButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }
    /// Small for cards and the panel, regular for window rows, large for a window's footer.
    enum Size { case small, regular, large }
    var kind = Kind.secondary
    var tint: Color?
    var size = Size.regular

    func makeBody(configuration: Configuration) -> some View {
        ActionBody(configuration: configuration, kind: kind, size: size,
             tint: tint ?? (kind == .primary ? .accentColor : kind == .ghost ? .secondary : .primary))
    }

    private struct ActionBody: View {
        let configuration: Configuration
        let kind: Kind
        let size: Size
        let tint: Color
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(font)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, size == .small ? 9 : size == .regular ? 12 : 18)
                .padding(.vertical, size == .small ? 4 : 5)
                .frame(minWidth: size == .large ? 120 : nil, minHeight: size == .large ? 40 : size == .regular ? 24 : nil)
                .foregroundStyle(kind == .primary ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
                .background { background }
                .contentShape(Capsule())
                .brightness(kind == .primary && hover && enabled ? 0.06 : configuration.isPressed ? -0.05 : 0)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(enabled ? 1 : 0.45)
                .animation(.snappy(duration: 0.15), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hover)
                .onHover { hover = $0 && enabled }
        }

        private var font: Font {
            switch size {
            case .small: .ui(.footnote, .medium)
            case .regular: .ui(.callout, .medium)
            case .large: .system(size: 14, weight: .semibold)
            }
        }

        @ViewBuilder private var background: some View {
            switch kind {
            case .primary:
                Plate(shape: Capsule(), tint: tint)
                    .shadow(color: tint.opacity(size == .large ? 0.3 : 0.18), radius: size == .large ? 6 : 2.5, y: size == .large ? 3 : 1)
            case .secondary:
                Capsule().fill(tint.opacity(hover ? 0.15 : 0.08))
            case .ghost:
                Capsule().fill(tint.opacity(hover ? 0.1 : 0))
            }
        }
    }
}

extension ButtonStyle where Self == ActionButtonStyle {
    static func action(_ kind: ActionButtonStyle.Kind = .secondary, tint: Color? = nil,
                       size: ActionButtonStyle.Size = .regular) -> ActionButtonStyle {
        ActionButtonStyle(kind: kind, tint: tint, size: size)
    }
}

/// Presses in slightly, for a custom-drawn button that is its own label.
struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Round icon button that brightens on hover.
struct IconButton: View {
    let symbol: String
    let help: String
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.ui(.footnote, .semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(hover ? Fill.controlHover : .clear))
                .foregroundStyle(hover ? .primary : .secondary)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(help)
    }
}

/// A white symbol on a rounded square of its tint, as in System Settings: 32 pt beside a title
/// and a detail line, 22 pt beside a title alone.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol).font(.system(size: max(11, size * 0.44), weight: .semibold)).foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5)
            .frame(width: size, height: size)
            .background(Plate(shape: RoundedRectangle(cornerRadius: Radius.tile(size), style: .continuous), tint: tint))
    }
}

/// Row metrics shared by groups: padding, and where the text starts after a 32-pt tile.
enum Row {
    static let padding: CGFloat = 14
    static let textInset: CGFloat = padding + 32 + Space.l
}

/// Rows on one rounded card, parted by their padding rather than dividers.
struct GroupCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
        VStack(spacing: 0) { content }.surface(shape)
    }
}

/// One row of a group: tile, title and an optional detail line, its control at the trailing edge.
/// Without a symbol the text lines up with the titles of rows that have one (a sub-setting).
struct SettingRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var symbol: String?
    var tint: Color
    @ViewBuilder var trailing: Trailing

    init(_ title: String, detail: String? = nil, symbol: String? = nil, tint: Color = .gray,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.detail = detail; self.symbol = symbol; self.tint = tint; self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.l) {
            if let symbol { IconTile(symbol: symbol, tint: tint) }
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title).font(.ui(.body, symbol == nil ? .regular : .medium))
                if let detail {
                    Text(detail).font(.ui(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.m)
            trailing.environment(\.settingTitle, title)
        }
        .padding(.leading, symbol == nil ? Row.textInset : Row.padding).padding(.trailing, Row.padding)
        .padding(.vertical, 13)
    }
}

private struct SettingTitleKey: EnvironmentKey { static let defaultValue = "" }

extension EnvironmentValues {
    /// The title of the setting row a control sits in: its spoken label, as the row shows it.
    var settingTitle: String {
        get { self[SettingTitleKey.self] }
        set { self[SettingTitleKey.self] = newValue }
    }
}

/// A titled group on a window page, with an optional note under it.
struct GroupSection<Content: View>: View {
    var title: Text?
    var footer: Text?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let title { title.font(.ui(.body, .semibold)).padding(.leading, Space.xs) }
            GroupCard { content }
            if let footer {
                footer.font(.ui(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.xs)
            }
        }
    }
}

/// Top of a window page: tile and title, and a lead line under them.
struct PageHeader: View {
    let title: String
    var symbol: String?
    var tint: Color = .accentColor
    var lead: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.l) {
                if let symbol { IconTile(symbol: symbol, tint: tint, size: 36) }
                Text(title).font(.ui(.title, .bold)).tracking(-0.2)
            }
            if let lead { Text(lead).font(.ui(.body)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// The sections of a window page as a row of pills under its header (settings' Agents, Alerts,
/// Panel…). The chosen one sits on the neutral selection fill.
struct PageTabs<Tab: Hashable>: View {
    let tabs: [(tab: Tab, title: String, symbol: String)]
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(tabs, id: \.tab) { item in
                let on = item.tab == selection
                Button { selection = item.tab } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.ui(.callout, on ? .semibold : .medium))
                        .foregroundStyle(on ? .primary : .secondary)
                        .padding(.horizontal, Space.l).frame(height: 28)
                        .background { if on { Capsule().fill(Fill.selected) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(Pressable())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// A choice of a few short options (Day / Week / Month): the chosen one lifts off its track.
struct Segmented<Item: Hashable>: View {
    let items: [(item: Item, title: String)]
    @Binding var selection: Item

    var body: some View {
        HStack(spacing: Space.xxs) {
            ForEach(items, id: \.item) { i in
                let on = i.item == selection
                Button { selection = i.item } label: {
                    Text(i.title).font(.ui(.callout, on ? .semibold : .medium)).foregroundStyle(on ? .primary : .secondary)
                        .padding(.horizontal, Space.l).frame(height: 22)
                        .background { if on { Capsule().fill(Fill.raised).shadow(color: .black.opacity(0.1), radius: 1.5, y: 0.5) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(Pressable())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(Space.xxs)
        .background(Fill.control, in: Capsule())
    }
}

// MARK: Overview

/// One hue at the strengths an Overview card draws with: deeper in the light appearance, brighter
/// in the dark. It lights the card's label, units and chart; figures stay in the primary ink.
struct Ramp {
    let hue: Color
    var mid: Color { hue.opacity(0.6) }
    var dim: Color { hue.opacity(0.2) }
    var faint: Color { hue.opacity(0.1) }

    private init(_ light: (CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat)) {
        hue = Color(light: NSColor(red: light.0, green: light.1, blue: light.2, alpha: 1),
                    dark: NSColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1))
    }

    /// Agent work and what it produced.
    static let work = Ramp((0.1, 0.64, 0.34), (0.3, 0.86, 0.5))
    /// Agents running.
    static let run = Ramp((0.1, 0.46, 0.96), (0.32, 0.64, 1))
    /// An agent waiting on you.
    static let wait = Ramp((0.9, 0.24, 0.21), (1, 0.4, 0.36))
    /// You answering.
    static let reply = Ramp((0.93, 0.52, 0), (1, 0.66, 0.2))
}

/// Text on an Overview card at three strengths.
enum Ink {
    static let primary = Color.primary.opacity(0.9), secondary = Color.primary.opacity(0.55), tertiary = Color.primary.opacity(0.36)
}

extension Fill {
    /// An Overview card: white on the light canvas, a lifted gray on the dark one.
    static let widget = Color(light: .white, dark: NSColor(white: 0.165, alpha: 1))
}

/// An Overview card's surface, with a soft two-part shadow in the light appearance.
struct WidgetSurface: View {
    var radius: CGFloat = Radius.widget
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Fill.widget)
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 1, y: 1)
            .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 14, y: 6)
    }
}

/// One Overview card: its label row and content at one padding, clipped to the card so a chart
/// can bleed to its edges. A card is as tall as its content, or as the tallest beside it.
struct Widget<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(Space.widget)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: Radius.widget, style: .continuous))
            .background(WidgetSurface())
    }
}

/// The label row a card opens with: what it is in its hue, what it means behind the ⓘ, the context
/// opposite in gray.
struct WidgetHead: View {
    let title: String
    let ramp: Ramp
    var info: String?
    var context: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: Space.xs) {
                Text(title).font(.ui(.body, .semibold)).foregroundStyle(ramp.hue).lineLimit(1)
                if let info { InfoTip(title: title, text: info) }
            }
            Spacer(minLength: Space.m)
            if let context { Text(context).font(.figure(TextSize.callout.rawValue, .medium)).foregroundStyle(Ink.secondary).lineLimit(1) }
        }
        .frame(height: 15)
    }
}

/// A quiet ⓘ that, hovered a moment, shows what a figure means in a popover (its own window, so a
/// card's clip doesn't cut it).
struct InfoTip: View {
    let title: String
    let text: String
    @State private var hovering = false
    @State private var shown = false
    @State private var pending: Task<Void, Never>?

    var body: some View {
        Image(systemName: "info.circle").font(.system(size: 11, weight: .medium))
            .foregroundStyle(hovering || shown ? Ink.secondary : Ink.tertiary)
            .contentShape(Rectangle().inset(by: -3))
            .onHover { inside in
                hovering = inside
                pending?.cancel()
                if inside {
                    pending = Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        if !Task.isCancelled { shown = true }
                    }
                } else {
                    shown = false
                }
            }
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title).font(.ui(.callout, .semibold)).foregroundStyle(Ink.primary)
                    Text(text).font(.ui(.callout)).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 260, alignment: .leading)
                .padding(Space.l)
            }
    }
}

/// Figure sizes: every card's, the two accents', and a row's.
enum FigureSize { static let card: CGFloat = 28, accent: CGFloat = 38, row: CGFloat = 14 }

/// A formatted figure ("9.6h", "3m 40s", "81%", "2.4×") with its digits in the primary ink and its
/// units half as large in the card's hue, a thin space before them.
func figure(_ text: String, _ ramp: Ramp, _ size: CGFloat = FigureSize.card) -> Text {
    var out = Text(verbatim: "")
    var afterDigits = false
    for run in figureRuns(text) {
        if run.figure {
            out = out + Text(verbatim: run.text).font(.figure(size)).tracking(-size * 0.02).foregroundStyle(Ink.primary)
        } else {
            let unit = afterDigits && !run.text.hasPrefix(" ") ? "\u{2009}" + run.text : run.text
            out = out + Text(verbatim: unit).font(.system(size: (size * 0.5).rounded(), weight: .semibold)).foregroundStyle(ramp.hue)
        }
        afterDigits = run.figure
    }
    return out
}

private func figureRuns(_ text: String) -> [(text: String, figure: Bool)] {
    var out: [(text: String, figure: Bool)] = []
    for c in text {
        let figure = "0123456789.,:–".contains(c)
        if out.last?.figure == figure { out[out.count - 1].text.append(c) } else { out.append((String(c), figure)) }
    }
    return out
}

/// A card's figure line: the figure, then its change and a note beside it on the figure's baseline.
struct FigureLine: View {
    let figure: Text
    var change: Text?
    var note: String?

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: Space.l) {
            figure.lineLimit(1).fixedSize()
            VStack(alignment: .leading, spacing: Space.xxs) {
                if let change { change.font(.figure(TextSize.callout.rawValue, .medium)).lineLimit(1) }
                if let note { Text(note).font(.ui(.callout, .medium)).foregroundStyle(Ink.secondary).lineLimit(2) }
            }
            .padding(.bottom, 2)
            Spacer(minLength: 0)
        }
        .padding(.top, Space.s)
    }
}

/// A chart's key: a swatch and its word.
struct ChartKey<Swatch: View>: View {
    let text: String
    @ViewBuilder var swatch: Swatch

    var body: some View {
        HStack(spacing: Space.s) { swatch; Text(text).font(.ui(.footnote, .medium)).foregroundStyle(Ink.secondary).lineLimit(1) }
    }
}

/// A small Overview card with one count: a glyph in its hue, the word, the figure, what it means
/// behind the ⓘ at the end.
struct StatChip: View {
    let symbol: String
    let title: String
    let value: String
    let ramp: Ramp
    var info: String?

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol).font(.ui(.footnote, .semibold)).foregroundStyle(ramp.hue)
                .frame(width: 26, height: 26).background(Circle().fill(ramp.faint))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.ui(.footnote, .medium)).foregroundStyle(Ink.secondary).lineLimit(1).minimumScaleFactor(0.85)
                Text(value).font(.figure(15)).foregroundStyle(Ink.primary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let info { InfoTip(title: title, text: info) }
        }
        .statChip()
    }
}

extension View {
    /// A chip's size and surface.
    func statChip() -> some View {
        padding(.horizontal, Space.m).frame(maxWidth: .infinity).frame(height: 46).background(WidgetSurface(radius: Radius.group))
    }
}

/// A notice on a soft wash of its tint, with an optional action at the end. Compact is the
/// floating panel's one-line version.
struct Banner<Trailing: View>: View {
    let text: String
    let symbol: String
    let tint: Color
    var compact = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: compact ? Space.s : 10) {
            Image(systemName: symbol).font(compact ? .ui(.footnote, .semibold) : .system(size: 18)).foregroundStyle(tint)
            Text(text).font(compact ? .ui(.footnote) : .ui(.body, .medium))
                .foregroundStyle(compact ? .secondary : .primary).lineLimit(compact ? 1 : nil)
            Spacer(minLength: Space.xs)
            trailing
        }
        .padding(.leading, compact ? 9 : Space.xl).padding(.trailing, compact ? Space.xxs : Space.xl)
        .padding(.vertical, compact ? 0 : Space.l).frame(minHeight: compact ? 26 : nil)
        .background(RoundedRectangle(cornerRadius: compact ? Radius.medium : Radius.group, style: .continuous).fill(tint.soft()))
    }
}

extension Banner where Trailing == EmptyView {
    init(_ text: String, symbol: String, tint: Color, compact: Bool = false) {
        self.init(text: text, symbol: symbol, tint: tint, compact: compact) { EmptyView() }
    }
}

extension Toggle {
    /// A setting's on/off switch at the trailing edge of its row.
    func switchStyle() -> some View { toggleStyle(.switch).controlSize(.small).labelsHidden() }
}

/// A keyboard shortcut as a key cap.
struct KeyCap: View {
    let keys: String
    var body: some View {
        Text(verbatim: keys).font(.ui(.callout, .medium))
            .padding(.horizontal, 7).padding(.vertical, Space.xxs)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Fill.control))
    }
}
