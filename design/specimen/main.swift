import AppKit
import SwiftUI

// Style specimen for the design-system proposal. Compiled with Sources/YaaKanban/DesignSystem.swift.

/// The app's Resources, found from this file's place in the repo (design/specimen/).
let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources").standardized.path
/// Where the renders go: the first argument, else /tmp/yaak-ds.
let out = CommandLine.arguments.dropFirst().first ?? "/tmp/yaak-ds"
func svg(_ path: String) -> NSImage? { NSImage(contentsOfFile: "\(repo)/\(path)") }

struct Logo: View {
    let name: String
    var size: CGFloat = 18
    var ink: Color = .white
    var body: some View {
        if let i = svg("AgentIcons/\(name).svg") {
            Image(nsImage: i).renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                .frame(width: size, height: size).foregroundStyle(ink)
        }
    }
}

struct LogoTile: View {
    let name: String
    var size: CGFloat = 32
    var body: some View {
        Logo(name: name, size: size * 0.56).frame(width: size, height: size)
            .background(Plate(shape: RoundedRectangle(cornerRadius: Radius.tile(size), style: .continuous), tint: Fill.logo))
    }
}

enum St: CaseIterable { case needs, stuck, review, running, done
    var label: String { ["需要输入", "可能卡住", "待验收", "运行中", "已验收"][St.allCases.firstIndex(of: self)!] }
    var tint: Color { [Color.red, .orange, .green, .blue, .secondary][St.allCases.firstIndex(of: self)!] }
    var symbol: String { ["hand.raised.fill", "exclamationmark.triangle.fill", "checkmark.seal.fill", "circle.dotted", "checkmark.circle"][St.allCases.firstIndex(of: self)!] }
    var loud: Bool { self == .needs || self == .stuck || self == .review }
}

struct Glyph: View {
    let st: St
    var size: CGFloat = 22
    var body: some View {
        ZStack {
            Circle().fill(st.tint.opacity(st.loud ? 0.18 : 0.10))
            if st == .running {
                Circle().trim(from: 0, to: 0.7).stroke(st.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round)).padding(size * 0.22)
            } else {
                Image(systemName: st.symbol).font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(st.tint)
            }
        }.frame(width: size, height: size)
    }
}

struct CardSurface: ViewModifier {
    let st: St
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        if st.loud { content.tinted(shape, st.tint) } else { content.surface(shape) }
    }
}

struct Caption: View {
    let t: String
    var body: some View { Text(t).font(.ui(.footnote, .semibold)).foregroundStyle(.secondary).textCase(.uppercase) }
}

struct Block<C: View>: View {
    let title: String
    @ViewBuilder var c: C
    var body: some View { VStack(alignment: .leading, spacing: 10) { Caption(t: title); c } }
}
/// Candidate figure faces, harder than the rounded one.
let figures: [(String, (CGFloat) -> Font)] = [
    ("figure · SF Pro 半粗，常规宽度，等宽数字", { .figure($0) }),
]

/// Column 1: tokens.
struct Tokens: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Block(title: "A · 字号（30 种 → 8 级）") {
                ForEach([(TextSize.display, "display 24", Font.Weight.bold), (.title, "title 20", .bold), (.headline, "headline 15", .semibold),
                         (.body, "body 13 · 窗口正文", .regular), (.callout, "callout 12 · 窗口按钮", .medium),
                         (.footnote, "footnote 11 · 说明 / 面板回复", .regular), (.caption, "caption 10 · 时钟 / 紧凑徽章", .regular),
                         (.micro, "micro 9 · 坐标轴", .regular)], id: \.1) { s, name, w in
                    Text(name).font(.ui(s, w))
                }
                ForEach(figures, id: \.0) { name, f in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("3.4×").font(f(28)); Text("2h 15m").font(f(18)); Text("47").font(f(15))
                        Text(name).font(.ui(.footnote)).foregroundStyle(.secondary)
                    }
                }
            }
            Block(title: "B · 圆角（10 种 → 5 级，嵌套逐级减小）") {
                HStack(spacing: 12) {
                    ForEach([(Radius.small, "6 small"), (Radius.medium, "8 medium"), (Radius.card, "12 card"),
                             (Radius.group, "14 group"), (Radius.panel, "16 panel")], id: \.1) { r, n in
                        VStack(spacing: 4) {
                            Color.clear.frame(width: 64, height: 46).surface(RoundedRectangle(cornerRadius: r, style: .continuous))
                            Text(n).font(.ui(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Block(title: "C · 表面层级（无描边，靠填充和留白分层）") {
                HStack(spacing: 12) {
                    ForEach([(Fill.card, "card"), (Fill.cardHover, "cardHover"), (Fill.control, "control"),
                             (Fill.controlHover, "controlHover"), (Fill.selected, "selected")], id: \.1) { f, n in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(f).frame(width: 64, height: 36)
                            Text(n).font(.ui(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Block(title: "D · 颜色语义") {
                HStack(spacing: 10) {
                    ForEach(St.allCases, id: \.self) { s in HStack(spacing: 5) { Glyph(st: s, size: 20); Text(s.label).font(.ui(.footnote)) } }
                }
                HStack(spacing: 14) {
                    HStack(spacing: 5) { Circle().fill(Color.accentColor).frame(width: 10); Text("操作 = 系统强调色").font(.ui(.footnote)) }
                    HStack(spacing: 5) { Circle().fill(Brand.gradient).frame(width: 10); Text("品牌绿 = 只用于 logo、趋势线").font(.ui(.footnote)) }
                }
            }
            Block(title: "E · 徽章（StatusPill / GuideBadge / StatusBadge → Badge）") {
                HStack(spacing: 6) { ForEach(St.allCases, id: \.self) { Badge(text: $0.label, tint: $0.tint, compact: true) } }
                Text("紧凑：卡片、面板").font(.ui(.caption)).foregroundStyle(.tertiary)
                HStack(spacing: 6) {
                    Badge(text: "已连接", symbol: "checkmark.circle.fill", tint: .green)
                    Badge(text: "等待首次使用", symbol: "clock", tint: .secondary)
                    Badge(text: "待授权", symbol: "exclamationmark.circle.fill", tint: .orange)
                    Badge(text: "有更新", symbol: "arrow.up.circle.fill", tint: .orange)
                    Badge(text: "未安装", tint: .secondary)
                }
                Text("常规：窗口（引导和设置共用同一套 Agent 状态）").font(.ui(.caption)).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Column 2: components.
struct Components: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Block(title: "F · 按钮（PillButtonStyle / PillButton / .borderedProminent → ActionButtonStyle）") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        Text("").frame(width: 50)
                        ForEach(["primary", "secondary", "ghost", "destructive"], id: \.self) { Text($0).font(.ui(.caption)).foregroundStyle(.secondary) }
                    }
                    ForEach([(ActionButtonStyle.Size.small, "small"), (.regular, "regular"), (.large, "large")], id: \.1) { size, n in
                        GridRow {
                            Text(n).font(.ui(.caption)).foregroundStyle(.secondary)
                            Button("跳转") {}.buttonStyle(.action(.primary, size: size))
                            Button("复制") {}.buttonStyle(.action(.secondary, size: size))
                            Button("跳过") {}.buttonStyle(.action(.ghost, size: size))
                            Button("删除") {}.buttonStyle(.action(.secondary, tint: .red, size: size))
                        }
                    }
                    GridRow {
                        Text("tinted").font(.ui(.caption)).foregroundStyle(.secondary)
                        Button("允许一次") {}.buttonStyle(.action(.primary, tint: .green, size: .small))
                        Button("拒绝") {}.buttonStyle(.action(.secondary, tint: .red, size: .small))
                        Button("禁用") {}.buttonStyle(.action(.primary)).disabled(true)
                        HStack(spacing: 2) { IconButton(symbol: "gearshape", help: "") {}; IconButton(symbol: "xmark", help: "") {} }
                    }
                }
            }
            Block(title: "G · 图标砖（SettingLabel 22 / 引导 32 → IconTile、LogoTile）") {
                HStack(spacing: 10) {
                    IconTile(symbol: "bell.badge.fill", tint: .red); IconTile(symbol: "hourglass", tint: .orange)
                    IconTile(symbol: "eye.fill", tint: .green); IconTile(symbol: "command", tint: .indigo)
                    IconTile(symbol: "power", tint: .gray)
                    LogoTile(name: "claudecode"); LogoTile(name: "codex"); LogoTile(name: "cursor")
                    IconTile(symbol: "bell.badge.fill", tint: .red, size: 22); LogoTile(name: "pi", size: 22)
                }
            }
            Block(title: "H · 横幅（引导横幅 / UpdateNotice → Banner）") {
                Banner("每个 Agent 都已连接。", symbol: "checkmark.seal.fill", tint: .green)
                Banner(text: "1.4.0 已可安装", symbol: "arrow.down.circle.fill", tint: .blue, compact: true) {
                    Button("重启更新") {}.buttonStyle(.action(.ghost, tint: .blue, size: .small))
                }.frame(width: 320)
            }
            Block(title: "J · 分组行（无分隔线，引导和设置共用）") {
                GroupCard {
                    agentRow("claudecode", "Claude Code", Badge(text: "已连接", symbol: "checkmark.circle.fill", tint: .green)) {
                        Button("卸载") {}.buttonStyle(.action(.ghost))
                    }
                    agentRow("codex", "Codex", Badge(text: "待授权", symbol: "exclamationmark.circle.fill", tint: .orange)) {
                        Button("卸载") {}.buttonStyle(.action(.ghost))
                    }
                    agentRow("cursor", "Cursor", Badge(text: "未安装", tint: .secondary)) {
                        Button("安装") {}.buttonStyle(.action(.primary))
                    }
                }
            }
            Block(title: "I · 主按钮（引导的「连接全部 Agent」）") {
                HStack(spacing: 14) {
                    Image(systemName: "link.circle.fill").font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("连接全部 Agent").font(.system(size: 16, weight: .bold))
                        Text("推荐 · 一次为下面所有 Agent 安装 hook").font(.ui(.footnote)).opacity(0.85)
                    }
                    Spacer(); Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 14)
                .background(Plate(shape: RoundedRectangle(cornerRadius: Radius.group, style: .continuous), tint: .accentColor))
                .shadow(color: Color.accentColor.opacity(0.3), radius: 10, y: 4)
            }
        }
    }
}
/// The main window with the custom sidebar and a settings page in it.
struct MainMock: View {
    var overview = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 280)
                .background(Color(nsColor: .underPageBackgroundColor))
            Group { if overview { OverviewPage() } else { settingsPage } }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Fill.canvas)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let l = svg("Brand/logo.svg") { Image(nsImage: l).resizable().frame(width: 22, height: 22) }
                Text(verbatim: "YaaKanban").font(.ui(.body, .bold))
                Spacer()
                chip(1, .red); chip(2, .green); chip(3, .blue)
            }.padding(.horizontal, 8).padding(.top, 34).padding(.bottom, 8)
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").font(.ui(.footnote)).foregroundStyle(.secondary)
                    Text("项目 / 提示词").font(.ui(.callout)).foregroundStyle(.tertiary); Spacer()
                }.padding(.horizontal, 8).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Fill.control))
                IconButton(symbol: "line.3.horizontal.decrease.circle", help: "") {}
            }.padding(.horizontal, 6).padding(.bottom, 8)
            nav("概览", "chart.xyaxis.line", .accentColor, selected: overview)
            section("进行中", 4)
            card(.needs, "修复登录回调竞态", "YaaKanban", "claudecode", "2 分钟")
            card(.review, "整理设计系统 token", "YaaKanban", "codex", "14 分钟")
            card(.running, "迁移 Settings 到主窗口", "artrix-skills", "claudecode", "运行 6 分钟")
            card(.stuck, "跑全量测试", "wave-patch", "cursor", "11 分钟")
            section("历史", nil)
            plain("Dashboard 月视图", "codex", "昨天"); plain("Codex trust hash", "claudecode", "10月25日")
            Spacer(minLength: 0)
            nav("设置", "gearshape.fill", .gray, badge: "1", selected: !overview)
        }.padding(.horizontal, 10).padding(.bottom, 12)
    }

    private func chip(_ n: Int, _ c: Color) -> some View {
        HStack(spacing: 3) { Circle().fill(c).frame(width: 6, height: 6); Text("\(n)").font(.figure(11, .semibold)) }
            .padding(.horizontal, 7).padding(.vertical, 3).background(c.soft(), in: Capsule())
    }
    private func section(_ t: String, _ n: Int?) -> some View {
        HStack(spacing: 6) {
            Text(t).font(.ui(.footnote, .semibold)).foregroundStyle(.secondary)
            if let n { Text("\(n)").font(.figure(10, .semibold)).foregroundStyle(.tertiary) }
        }
            .padding(.horizontal, 8).padding(.top, 16).padding(.bottom, 2)
    }
    private func nav(_ t: String, _ s: String, _ c: Color, badge: String? = nil, selected: Bool = false) -> some View {
        HStack(spacing: 8) {
            IconTile(symbol: s, tint: c, size: 22); Text(t).font(.ui(.body, .medium)); Spacer()
            if let badge { Badge(text: badge, tint: .orange, compact: true) }
        }.padding(.horizontal, 8).frame(height: 34)
            .background { if selected { RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Fill.selected) } }
    }
    private func card(_ st: St, _ title: String, _ project: String, _ agent: String, _ time: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Glyph(st: st, size: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text(title).font(.ui(.body, .semibold)).lineLimit(1); Spacer(minLength: 2); Text(time).font(.ui(.caption)).foregroundStyle(.tertiary) }
                HStack(spacing: 5) { Logo(name: agent, size: 11, ink: .secondary); Text(project).font(.ui(.footnote)).foregroundStyle(.secondary); Badge(text: st.label, tint: st.tint, compact: true) }
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
        .modifier(CardSurface(st: st))
    }
    private func plain(_ t: String, _ agent: String, _ time: String) -> some View {
        HStack(spacing: 8) {
            Glyph(st: .done, size: 18); Text(t).font(.ui(.callout)).lineLimit(1); Spacer()
            Logo(name: agent, size: 11, ink: .secondary); Text(time).font(.ui(.caption)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 10).frame(height: 28)
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "设置", symbol: "gearshape.fill", tint: .gray)
                PageTabs(tabs: [(0, "Agent 接入", "powerplug"), (1, "提醒", "bell.badge"), (2, "悬浮窗", "rectangle.on.rectangle"),
                                (3, "兼容性", "puzzlepiece.extension"), (4, "通用", "gearshape.2"), (5, "关于", "info.circle")],
                         selection: .constant(1))
            }
            GroupSection(title: Text("提醒")) {
                SettingRow("卡住阈值", detail: "运行中超过这么久没有新事件，视为可能卡住。", symbol: "hourglass", tint: .orange) {
                    value("5 分钟")
                }
                SettingRow("审批等待", detail: "在面板或通知里等你允许或拒绝的时间，超时回到终端。", symbol: "hand.raised.fill", tint: .red) {
                    value("20 秒")
                }
                SettingRow("Wave 在前台时不发系统通知", symbol: "bell.slash.fill", tint: .gray) {
                    Toggle("", isOn: .constant(true)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            GroupSection(title: Text("会话提醒"), footer: Text("闪烁只计你在电脑前的时间（2 分钟无键鼠或睡眠算离开）。")) {
                SettingRow("需要输入时闪烁", symbol: "light.beacon.max.fill", tint: .red) {
                    Toggle("", isOn: .constant(true)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                SettingRow("开始闪烁", detail: "未点击多久后开始") { value("30 秒") }
                SettingRow("终端在前台时标为已验收（beta）", symbol: "eye.fill", tint: .green) {
                    Toggle("", isOn: .constant(true)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .padding(.horizontal, 40).padding(.top, 44)
    }

    private func value(_ t: String) -> some View {
        HStack(spacing: 4) {
            Text(t).font(.ui(.callout, .medium).monospacedDigit())
                .padding(.horizontal, 8).frame(height: 22)
                .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(Fill.control))
            Stepper("", value: .constant(1)).labelsHidden()
        }
    }

}

@MainActor func agentRow(_ logo: String, _ name: String, _ badge: Badge, @ViewBuilder action: () -> some View) -> some View {
    HStack(spacing: Space.l) {
        LogoTile(name: logo); Text(name).font(.ui(.body, .medium)); Spacer(); badge; action()
    }.padding(.horizontal, Row.padding).padding(.vertical, 12)
}

struct Sheet: View {
    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            Tokens().frame(width: 520, alignment: .leading)
            Components().frame(width: 560, alignment: .leading)
        }.padding(36)
    }
}

@MainActor func render(_ view: some View, size: NSSize, dark: Bool, to path: String) {
    let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
    w.contentView = host
    w.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    w.orderOut(nil)
}

/// The finish up close, 3×: tiles, buttons, a badge, a card corner, a key cap.
struct Detail: View {
    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            IconTile(symbol: "hourglass", tint: .orange); IconTile(symbol: "terminal.fill", tint: Fill.logo)
            Button("安装") {}.buttonStyle(.action(.primary)).fixedSize()
            Button("卸载") {}.buttonStyle(.action(.secondary))
            Badge(text: "待授权", symbol: "exclamationmark.circle.fill", tint: .orange)
            KeyCap(keys: "⌥⌘K")
            Text("卡片").font(.ui(.footnote)).frame(width: 70, height: 40).surface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            Text("待验收").font(.ui(.footnote)).frame(width: 70, height: 40).tinted(RoundedRectangle(cornerRadius: Radius.card, style: .continuous), .green)
        }
        .padding(24)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated {
    for dark in [true, false] {
        let m = dark ? "dark" : "light"
        render(Sheet(), size: NSSize(width: 1210, height: 900), dark: dark, to: "\(out)/1-tokens-components-\(m).png")
        let r = ImageRenderer(content: Detail().background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, dark ? .dark : .light))
        r.scale = 4
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            if let cg = r.cgImage { try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/3-detail-4x-\(m).png")) }
        }
        render(MainMock(), size: NSSize(width: 1000, height: 760), dark: dark, to: "\(out)/2-main-settings-\(m).png")
        render(MainMock(overview: true), size: NSSize(width: 1300, height: 1300), dark: dark, to: "\(out)/4-overview-\(m).png")
    }
}
