import AppKit
import ServiceManagement
import SwiftUI
import YaaCore
import YaaIntegrations

/// Menu-bar popover: active sessions plus shortcuts.
struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let panel: FloatingPanelController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("YaaKanban").font(.headline)
                Spacer()
                if model.attentionCount > 0 {
                    Text("\(model.attentionCount) 个待处理").font(.caption).foregroundStyle(.red)
                }
            }
            if let err = model.serverError { Text(err).font(.caption).foregroundStyle(.red) }
            if model.activeSessions.isEmpty {
                Text("没有活跃的 agent 会话").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.activeSessions) { s in
                            SessionRow(session: s)
                                .onTapGesture { open(s) }
                            Divider()
                        }
                    }
                }.frame(maxHeight: 420)
            }
            HStack {
                Button("主界面") { open(nil) }
                Button(panel.isVisible ? "隐藏悬浮窗" : "显示悬浮窗") { panel.toggle() }
                    .help("⌥⌘K")
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 380)
    }

    private func open(_ s: SessionState?) {
        model.selection = s?.id ?? model.selection
        openWindow(id: "main")
        NSApp.activate()
    }
}

struct FloatingPanelView: View {
    @Environment(AppModel.self) private var model
    @State private var expanded: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Agents").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if model.attentionCount > 0 {
                    Text("\(model.attentionCount)").font(.caption2.bold()).padding(.horizontal, 6)
                        .background(Capsule().fill(model.hasNeedsInput ? .red : .orange)).foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
            if model.activeSessions.isEmpty {
                Text("空闲").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.activeSessions) { s in
                            SessionRow(session: s, expanded: expanded == s.id)
                                .padding(.horizontal, 10)
                                .opacity(s.status == .idle ? 0.55 : 1)
                                .onTapGesture { withAnimation(.snappy) { expanded = expanded == s.id ? nil : s.id } }
                            Divider().padding(.leading, 10)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }
}

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @State private var filter: AgentKind?
    @State private var query = ""

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                section("活跃", model.activeSessions)
                section("历史", model.allSessions.filter { s in !model.activeSessions.contains { $0.id == s.id } })
            }
            .searchable(text: $query, placement: .sidebar, prompt: "项目 / prompt")
            .toolbar {
                Picker("Agent", selection: $filter) {
                    Text("全部").tag(AgentKind?.none)
                    ForEach(AgentKind.allCases, id: \.self) { Text($0.displayName).tag(AgentKind?.some($0)) }
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if let id = model.selection, let s = model.sessions[id] {
                SessionDetail(session: s)
            } else {
                Text("选择一个会话").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    @ViewBuilder
    private func section(_ title: String, _ list: [SessionState]) -> some View {
        let shown = list.filter(matches)
        if !shown.isEmpty {
            Section(title) {
                ForEach(shown) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: s.agent.symbol).foregroundStyle(.secondary)
                            Text(s.projectName ?? s.agent.displayName).fontWeight(.medium)
                            Spacer()
                            StatusBadge(status: s.status)
                        }
                        Text(s.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text(s.lastEventAt, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .tag(s.id)
                    .contextMenu { Button("从历史删除", role: .destructive) { model.remove(s.id) } }
                }
            }
        }
    }

    private func matches(_ s: SessionState) -> Bool {
        if let filter, s.agent != filter { return false }
        guard !query.isEmpty else { return true }
        let q = query.lowercased()
        return [s.cwd, s.title, s.sessionId].compactMap { $0?.lowercased() }.contains { $0.contains(q) }
            || s.turns.contains { $0.prompt.lowercased().contains(q) }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    let panel: FloatingPanelController
    @State private var integrationMessage: String?
    @State private var refresh = 0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Agent 接入") {
                ForEach(Integrations.all, id: \.agent) { i in
                    let status = i.status(home: Paths.home())
                    HStack {
                        Text(i.agent.displayName)
                        Spacer()
                        Text(statusLabel(status)).foregroundStyle(status == .installed ? .green : .secondary).font(.caption)
                        if status == .installed {
                            Button("卸载") { apply(i, install: false) }
                        } else if status == .notInstalled {
                            Button("安装") { apply(i, install: true) }
                        }
                    }
                }
                .id(refresh)
                if let m = integrationMessage { Text(m).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            Section("提醒") {
                LabeledContent("卡住阈值") { Stepper("\(Int(settings.stuckMinutes)) 分钟", value: $settings.stuckMinutes, in: 1...60) }
                LabeledContent("审批等待") { Stepper("\(Int(settings.approvalTimeout)) 秒", value: $settings.approvalTimeout, in: 5...25) }
                Toggle("Wave 在前台时不发系统通知", isOn: $settings.suppressWhenWaveFrontmost)
            }
            Section("悬浮窗") {
                LabeledContent("已完成会话显示") { Stepper("\(Int(settings.idleVisibleMinutes)) 分钟", value: $settings.idleVisibleMinutes, in: 0...240, step: 5) }
                Slider(value: $settings.panelOpacity, in: 0.4...1) { Text("透明度") }
                    .onChange(of: settings.panelOpacity) { panel.applyOpacity() }
                Text("⌥⌘K 显示 / 隐藏").font(.caption).foregroundStyle(.secondary)
            }
            Section("Wave Terminal") {
                Toggle("实验：跳转时切换到对应标签页（需要辅助功能权限，仅前 9 个标签）", isOn: $settings.waveTabSwitching)
            }
            Section {
                Toggle("登录时启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { integrationMessage = "登录项设置失败：\(error.localizedDescription)" }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
    }

    private func statusLabel(_ s: IntegrationStatus) -> String {
        switch s { case .installed: "已安装"; case .notInstalled: "未安装"; case .notDetected: "未检测到" }
    }

    private func apply(_ i: any Integration, install: Bool) {
        let yaak = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/yaak").path
        do {
            try Installer.apply(try i.plan(install: install, home: Paths.home(), yaak: yaak))
            integrationMessage = "\(i.agent.displayName) 已\(install ? "安装" : "卸载")。" + (install ? (i.postInstallNote ?? "") : "")
        } catch {
            integrationMessage = "\(i.agent.displayName)：\(error)"
        }
        refresh += 1
    }
}
