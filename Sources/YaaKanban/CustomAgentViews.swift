import AppKit
import SwiftUI
import UniformTypeIdentifiers
import YaaCore

/// Section inside Settings › Agent integrations for user-defined custom agents.
struct CustomAgentsSection: View {
    @Environment(AppModel.self) private var model
    @State private var sheet: SheetTarget?
    @State private var pendingDelete: CustomAgent?
    @State private var errorMessage: String?

    struct SheetTarget: Identifiable {
        let id = UUID()
        var existing: CustomAgent?
        var prefillId: String?
        var initialTab: CustomAgentSheet.Tab
    }

    var body: some View {
        let registered = model.customAgents
        let unregistered = model.unregisteredCustomIds
        let connected = model.connectedCustomIds

        GroupSection(
            title: Text("Custom agents"),
            footer: Text("Connect any other coding agent or script via `yaak hook custom`. Unregistered IDs are accepted automatically; register one here to customize its name, icon, protocol, and resume command.")
        ) {
            if registered.isEmpty && unregistered.isEmpty {
                HStack(spacing: Space.l) {
                    IconTile(symbol: "puzzlepiece.extension.fill", tint: Fill.logo)
                    Text("No custom agents registered yet. Add one to get a ready-to-use CLI snippet and AI integration prompt.")
                        .font(.ui(.callout)).foregroundStyle(.secondary)
                    Spacer(minLength: Space.m)
                    addRow
                }
                .padding(Row.padding)
            } else {
                ForEach(registered) { agent in
                    registeredRow(agent, isConnected: connected.contains(agent.id))
                }
                ForEach(unregistered, id: \.self) { uid in
                    unregisteredRow(uid)
                }
                HStack(spacing: Space.m) {
                    addRow
                    Spacer()
                    if FileManager.default.fileExists(atPath: model.paths.customAgents.path) {
                        Button("Reveal config") {
                            NSWorkspace.shared.activateFileViewerSelecting([model.paths.customAgents])
                        }
                        .buttonStyle(.action(.ghost, size: .small))
                    }
                }
                .padding(Row.padding)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.ui(.footnote)).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Row.padding).padding(.bottom, Row.padding)
            }
        }
        .sheet(item: $sheet) { target in
            CustomAgentSheet(existing: target.existing, prefillId: target.prefillId, initialTab: target.initialTab)
                .environment(model)
        }
        .alert(
            String(localized: "Delete custom agent?"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { agent in
            Button("Delete", role: .destructive) {
                do {
                    try model.deleteCustomAgent(id: agent.id)
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { agent in
            Text("Removes \(agent.name) (\(agent.id)) from custom agents. Past sessions stay in History.")
        }
    }

    private var addRow: some View {
        Button {
            sheet = SheetTarget(existing: nil, prefillId: nil, initialTab: .configure)
        } label: {
            Label("Add Custom Agent", systemImage: "plus")
        }
        .buttonStyle(.action(.primary, size: .small))
    }

    private func registeredRow(_ agent: CustomAgent, isConnected: Bool) -> some View {
        HStack(spacing: Space.l) {
            LogoTile(agent: .custom, customId: agent.id, custom: agent)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s) {
                    Text(agent.name).font(.ui(.body, .medium)).lineLimit(1)
                    if isConnected {
                        Badge(text: String(localized: "Connected"), tint: .green, compact: true)
                    }
                }
                HStack(spacing: Space.xs) {
                    Text(verbatim: agent.id).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Text(verbatim: "·").foregroundStyle(.tertiary)
                    Text(agent.protocol == .claude ? String(localized: "Claude hooks") : String(localized: "Generic"))
                        .font(.ui(.footnote)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Space.m)
            Button("Connect") {
                sheet = SheetTarget(existing: agent, prefillId: nil, initialTab: .connect)
            }
            .buttonStyle(.action(.secondary, size: .small))
            Button("Edit") {
                sheet = SheetTarget(existing: agent, prefillId: nil, initialTab: .configure)
            }
            .buttonStyle(.action(.ghost, size: .small))
            IconButton(symbol: "trash", help: String(localized: "Delete")) {
                pendingDelete = agent
            }
        }
        .padding(Row.padding)
    }

    private func unregisteredRow(_ id: String) -> some View {
        HStack(spacing: Space.l) {
            LogoTile(agent: .custom, customId: id)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s) {
                    Text(verbatim: id).font(.ui(.body, .medium)).lineLimit(1)
                    Badge(text: String(localized: "Unregistered"), tint: .orange, compact: true)
                }
                Text("Received events automatically; register to customize icon and resume command.")
                    .font(.ui(.footnote)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.m)
            Button("Register…") {
                sheet = SheetTarget(existing: nil, prefillId: id, initialTab: .configure)
            }
            .buttonStyle(.action(.primary, size: .small))
        }
        .padding(Row.padding)
    }
}

/// Modal sheet to configure a custom agent and copy its AI integration prompt / CLI snippet / test it.
struct CustomAgentSheet: View {
    enum Tab: String, CaseIterable { case configure, connect }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let existing: CustomAgent?
    let prefillId: String?

    @State private var tab: Tab
    @State private var name: String
    @State private var slug: String
    @State private var slugEdited: Bool
    @State private var proto: CustomAgentProtocol
    @State private var supportsApproval: Bool
    @State private var resumeTemplate: String
    @State private var iconKind: CustomAgentIcon.Kind
    @State private var monogramText: String
    @State private var symbolName: String
    @State private var imageFilename: String?
    @State private var pickedImageURL: URL?
    @State private var iconColor: CustomAgentColor

    @State private var savedAgent: CustomAgent?
    @State private var validationError: String?
    @State private var copiedPrompt = false
    @State private var copiedSnippet = false
    @State private var testSent = false

    private static let curatedSymbols = [
        "terminal.fill", "cpu", "sparkles", "bolt.fill", "wand.and.stars", "hammer.fill",
        "wrench.and.screwdriver.fill", "brain", "cube.fill", "atom", "ant.fill", "flame.fill",
        "paperplane.fill", "command", "chevron.left.forwardslash.chevron.right", "curlybraces",
        "network", "gearshape.fill"
    ]

    init(existing: CustomAgent?, prefillId: String?, initialTab: Tab) {
        self.existing = existing
        self.prefillId = prefillId
        _tab = State(initialValue: existing == nil ? .configure : initialTab)
        let base = existing ?? CustomAgent(
            id: prefillId ?? "",
            name: prefillId ?? ""
        )
        _name = State(initialValue: base.name)
        _slug = State(initialValue: base.id)
        _slugEdited = State(initialValue: existing != nil || (prefillId != nil && !prefillId!.isEmpty))
        _proto = State(initialValue: base.protocol)
        _supportsApproval = State(initialValue: base.supportsApproval)
        _resumeTemplate = State(initialValue: base.resumeCommandTemplate ?? "")
        _iconKind = State(initialValue: base.icon.kind)
        _monogramText = State(initialValue: base.icon.kind == .monogram ? (base.icon.value ?? "") : "")
        _symbolName = State(initialValue: base.icon.kind == .symbol ? (base.icon.value ?? "terminal.fill") : "terminal.fill")
        _imageFilename = State(initialValue: base.icon.kind == .image ? base.icon.value : nil)
        _iconColor = State(initialValue: base.icon.color)
        _savedAgent = State(initialValue: existing)
    }

    private var cleanId: String { CustomAgent.sanitizeId(slug) }

    private var draftAgent: CustomAgent {
        let iconVal: String? = switch iconKind {
        case .monogram: monogramText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : monogramText.trimmingCharacters(in: .whitespacesAndNewlines)
        case .symbol: symbolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "terminal.fill" : symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image: imageFilename
        }
        let trimmedResume = resumeTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        return CustomAgent(
            id: cleanId.isEmpty ? "my-agent" : cleanId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (cleanId.isEmpty ? "My Agent" : cleanId) : name.trimmingCharacters(in: .whitespacesAndNewlines),
            protocol: proto,
            supportsApproval: supportsApproval,
            resumeCommandTemplate: trimmedResume.isEmpty ? nil : trimmedResume,
            icon: CustomAgentIcon(kind: iconKind, value: iconVal, color: iconColor),
            createdAt: savedAgent?.createdAt ?? Date()
        )
    }

    private var activeAgent: CustomAgent { savedAgent ?? draftAgent }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    switch tab {
                    case .configure: configureBody
                    case .connect: connectBody
                    }
                }
                .padding(Space.xxl)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 580)
        .background(Fill.canvas)
    }

    // MARK: Header & Footer

    private var header: some View {
        HStack(spacing: Space.l) {
            previewTile
            VStack(alignment: .leading, spacing: 2) {
                Text(draftAgent.name).font(.ui(.headline, .semibold)).lineLimit(1)
                HStack(spacing: Space.xs) {
                    Text(verbatim: cleanId.isEmpty ? "my-agent" : cleanId)
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Badge(text: proto == .claude ? String(localized: "Claude hooks") : String(localized: "Generic"),
                          tint: .accentColor, compact: true)
                }
            }
            Spacer()
            if savedAgent != nil {
                Segmented(items: [
                    (item: Tab.configure, title: String(localized: "Settings")),
                    (item: Tab.connect, title: String(localized: "Connect & Test"))
                ], selection: $tab)
            }
        }
        .padding(.horizontal, Space.xxl).padding(.vertical, Space.l)
    }

    @ViewBuilder private var previewTile: some View {
        if iconKind == .image, let pickedImageURL, let img = NSImage(contentsOf: pickedImageURL) {
            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: Radius.tile(38), style: .continuous).fill(Fill.control))
        } else {
            LogoTile(agent: .custom, customId: draftAgent.id, custom: draftAgent, size: 38)
        }
    }

    private var footer: some View {
        HStack {
            if let validationError {
                Text(validationError).font(.ui(.footnote)).foregroundStyle(.red).lineLimit(2)
            }
            Spacer()
            if tab == .configure {
                Button("Cancel") { dismiss() }.buttonStyle(.action(.secondary))
                Button(savedAgent == nil ? "Save & Continue" : "Save") { save(advanceToConnect: savedAgent == nil) }
                    .buttonStyle(.action(.primary))
                    .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button("Done") { dismiss() }.buttonStyle(.action(.primary))
            }
        }
        .padding(.horizontal, Space.xxl).padding(.vertical, Space.l)
    }

    // MARK: Configure tab

    private var configureBody: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            GroupCard {
                VStack(alignment: .leading, spacing: Space.l) {
                    labeledField(String(localized: "Display name")) {
                        TextField("My Agent", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: name) { _, newVal in
                                if !slugEdited { slug = CustomAgent.sanitizeId(newVal) }
                            }
                    }
                    labeledField(String(localized: "Agent ID")) {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField(text: $slug, prompt: Text(verbatim: "my-agent")) { EmptyView() }
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .onChange(of: slug) { _, _ in slugEdited = true; validationError = nil }
                            Text("Lowercase letters, numbers, hyphens, dots, or underscores. Passed via `--id`.")
                                .font(.ui(.footnote)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(Row.padding)
            }

            GroupCard {
                VStack(alignment: .leading, spacing: Space.l) {
                    HStack {
                        Text("Icon").font(.ui(.body, .medium))
                        Spacer()
                        Segmented(items: [
                            (item: CustomAgentIcon.Kind.monogram, title: String(localized: "Monogram")),
                            (item: CustomAgentIcon.Kind.symbol, title: String(localized: "SF Symbol")),
                            (item: CustomAgentIcon.Kind.image, title: String(localized: "Image"))
                        ], selection: $iconKind)
                    }

                    switch iconKind {
                    case .monogram:
                        labeledField(String(localized: "Letters (optional)")) {
                            TextField(CustomAgent.monogram(from: name.isEmpty ? "MA" : name), text: $monogramText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .onChange(of: monogramText) { _, val in
                                    if val.count > 2 { monogramText = String(val.prefix(2)) }
                                }
                        }
                        colorPickerRow
                    case .symbol:
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 9), spacing: Space.s) {
                            ForEach(Self.curatedSymbols, id: \.self) { sym in
                                Button { symbolName = sym } label: {
                                    Image(systemName: sym)
                                        .font(.system(size: 14, weight: .medium))
                                        .frame(width: 34, height: 30)
                                        .background(
                                            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                                .fill(symbolName == sym ? Color.accentColor.opacity(0.18) : Fill.control)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                                .strokeBorder(symbolName == sym ? Color.accentColor : .clear, lineWidth: 1.5)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        labeledField(String(localized: "SF Symbol name")) {
                            TextField(text: $symbolName, prompt: Text(verbatim: "terminal.fill")) { EmptyView() }
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        colorPickerRow
                    case .image:
                        HStack(spacing: Space.m) {
                            Button("Choose SVG / PNG…") { pickImage() }
                                .buttonStyle(.action(.secondary, size: .small))
                            if let url = pickedImageURL {
                                Text(url.lastPathComponent).font(.ui(.footnote)).foregroundStyle(.secondary).lineLimit(1)
                            } else if let file = imageFilename {
                                Text(file).font(.ui(.footnote)).foregroundStyle(.secondary).lineLimit(1)
                            } else {
                                Text("Supports SVG, PNG, JPEG, WebP").font(.ui(.footnote)).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if pickedImageURL != nil || imageFilename != nil {
                                Button("Clear") {
                                    pickedImageURL = nil
                                    imageFilename = nil
                                }
                                .buttonStyle(.action(.ghost, size: .small))
                            }
                        }
                    }
                }
                .padding(Row.padding)
            }

            GroupCard {
                VStack(alignment: .leading, spacing: Space.l) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Event protocol").font(.ui(.body, .medium))
                            Text(proto == .claude
                                 ? "Compatible with Claude Code hooks JSON (`SessionStart`, `PreToolUse`, `Stop`, `PermissionRequest`)."
                                 : "YaaKanban's neutral JSON & CLI flags (`prompt`, `tool_start`, `tool_end`, `permission`, `turn_end`).")
                                .font(.ui(.footnote)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Segmented(items: [
                            (item: CustomAgentProtocol.generic, title: String(localized: "Generic")),
                            (item: CustomAgentProtocol.claude, title: String(localized: "Claude hooks"))
                        ], selection: $proto)
                    }

                    Toggle(isOn: $supportsApproval) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Interactive permission approval").font(.ui(.body, .medium))
                            Text("Permission events pause briefly so you can click Allow or Deny from YaaKanban or notifications.")
                                .font(.ui(.footnote)).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    labeledField(String(localized: "Resume command (optional)")) {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField(text: $resumeTemplate, prompt: Text(verbatim: "myagent --resume {session_id}")) { EmptyView() }
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                            Text("Use `{session_id}` as a placeholder; it is shell-quoted automatically when resuming.")
                                .font(.ui(.footnote)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(Row.padding)
            }
        }
    }

    private var colorPickerRow: some View {
        HStack(spacing: Space.s) {
            Text("Color").font(.ui(.callout)).foregroundStyle(.secondary)
            Spacer()
            ForEach(CustomAgentColor.allCases, id: \.self) { c in
                Button { iconColor = c } label: {
                    ZStack {
                        if c == .auto {
                            Circle()
                                .fill(AngularGradient(colors: [.blue, .purple, .pink, .orange, .green, .blue], center: .center))
                                .frame(width: 18, height: 18)
                        } else {
                            Circle().fill(c.swiftUIColor).frame(width: 18, height: 18)
                        }
                        if iconColor == c {
                            Circle().strokeBorder(.white, lineWidth: 2).frame(width: 14, height: 14)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .background(Circle().strokeBorder(iconColor == c ? Color.primary : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .help(c.rawValue)
            }
        }
    }

    // MARK: Connect & Test tab

    private var connectBody: some View {
        let agent = activeAgent
        let yaak = AppModel.yaakPath
        let snippet = agent.hookSnippet(yaakPath: yaak)
        return VStack(alignment: .leading, spacing: Space.xl) {
            GroupCard {
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(spacing: Space.m) {
                        IconTile(symbol: "sparkles", tint: .purple, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Let an AI wire it up for you").font(.ui(.body, .semibold))
                            Text("Copy a self-contained prompt with the exact CLI path, agent ID, and event schema, then paste it into any coding agent.")
                                .font(.ui(.footnote)).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: Space.m) {
                        Button {
                            copyToClipboard(agent.aiPrompt(yaakPath: yaak))
                            copiedPrompt = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedPrompt = false }
                        } label: {
                            Label(copiedPrompt ? "Copied!" : "Copy AI Integration Prompt",
                                  systemImage: copiedPrompt ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.action(.primary))

                        Button {
                            model.sendTestEvent(for: agent)
                            testSent = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { testSent = false }
                        } label: {
                            Label("Send Test Event", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(.action(.secondary))
                    }
                    if testSent {
                        HStack(spacing: Space.xs) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Test session sent — check the floating panel or sidebar.")
                                .font(.ui(.footnote)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(Row.padding)
            }

            GroupCard {
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack {
                        Text("Hook / CLI snippet").font(.ui(.body, .semibold))
                        Spacer()
                        Button {
                            copyToClipboard(snippet)
                            copiedSnippet = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedSnippet = false }
                        } label: {
                            Label(copiedSnippet ? "Copied!" : "Copy",
                                  systemImage: copiedSnippet ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.action(.secondary, size: .small))
                    }
                    ScrollView([.horizontal, .vertical]) {
                        Text(verbatim: snippet)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 220)
                    .padding(10)
                    .background(Fill.control, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                }
                .padding(Row.padding)
            }
        }
    }

    // MARK: Actions

    private func labeledField<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label).font(.ui(.callout, .medium)).foregroundStyle(.secondary)
            content()
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.svg, .png, .jpeg, .webP, .icns, .tiff]
        if panel.runModal() == .OK, let url = panel.url {
            pickedImageURL = url
        }
    }

    private func save(advanceToConnect: Bool) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationError = String(localized: "Please enter a display name.")
            return
        }
        let cid = CustomAgent.sanitizeId(slug.isEmpty ? trimmedName : slug)
        guard CustomAgent.isValidId(cid) else {
            validationError = String(localized: "Agent ID must start with a letter or number and use only lowercase letters, numbers, '-', '_' or '.'.")
            return
        }
        let originalId = savedAgent?.id
        if cid != originalId && model.customAgents.contains(where: { $0.id == cid }) {
            validationError = String(localized: "Another custom agent already uses the ID \"\(cid)\".")
            return
        }
        var finalFilename = imageFilename
        if iconKind == .image, let pickedImageURL {
            do {
                finalFilename = try CustomAgentStore.saveIcon(from: pickedImageURL, for: cid, iconsDir: model.paths.customAgentIcons)
            } catch {
                validationError = error.localizedDescription
                return
            }
        }
        let iconVal: String? = switch iconKind {
        case .monogram: monogramText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : monogramText.trimmingCharacters(in: .whitespacesAndNewlines)
        case .symbol: symbolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "terminal.fill" : symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image: finalFilename
        }
        let trimmedResume = resumeTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = CustomAgent(
            id: cid,
            name: trimmedName,
            protocol: proto,
            supportsApproval: supportsApproval,
            resumeCommandTemplate: trimmedResume.isEmpty ? nil : trimmedResume,
            icon: CustomAgentIcon(kind: iconKind, value: iconVal, color: iconColor),
            createdAt: savedAgent?.createdAt ?? Date()
        )
        do {
            try model.saveCustomAgent(result, replacingId: originalId)
            slug = cid
            imageFilename = finalFilename
            pickedImageURL = nil
            savedAgent = result
            validationError = nil
            if advanceToConnect {
                tab = .connect
            } else {
                dismiss()
            }
        } catch {
            validationError = error.localizedDescription
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
