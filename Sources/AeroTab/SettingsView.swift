import SwiftUI
import ApplicationServices
import ServiceManagement
import AeroTabCore

struct SettingsView: View {
    let model: AppModel
    let enableKeyboard: () -> Void
    @Bindable var store: SettingsStore
    @State var selectedTab = 0
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var showingAppShortcuts = false
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedTab: Int?

    private var canvas: Color {
        colorScheme == .dark ? Color(red: 48 / 255, green: 46 / 255, blue: 49 / 255) : Color(nsColor: .windowBackgroundColor)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabs.padding(.top, 18)
            Group {
                switch selectedTab {
                case 1: workspaceStyles
                case 2: help
                default: general
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(width: 650, height: 570).background(canvas)
            .sheet(isPresented: $showingAppShortcuts) { AppShortcutSettings(model: model, store: store) }
            .environment(\.locale, store.configuration.language.locale)
            .onChange(of: store.configuration.aerospacePath) { _, _ in
                model.subscription.start(path: store.configuration.aerospacePath)
                model.refresh()
            }
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(Array(["General", "Workspaces", "Help"].enumerated()), id: \.offset) { index, title in
                Button { selectedTab = index } label: {
                    Text(LocalizedStringKey(title)).font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).frame(height: 28)
                        .foregroundStyle(selectedTab == index ? .white : .primary)
                        .background(selectedTab == index ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            if focusedTab == index {
                                RoundedRectangle(cornerRadius: 5).inset(by: 2)
                                    .stroke(selectedTab == index ? .white.opacity(0.6) : Color.accentColor, lineWidth: 1)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).focusEffectDisabled().focused($focusedTab, equals: index)
                    .accessibilityAddTraits(selectedTab == index ? [.isSelected] : [])
            }
        }.padding(3).background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            .onMoveCommand { direction in
                guard let current = focusedTab else { return }
                let next: Int
                switch direction {
                case .left: next = (current + 2) % 3
                case .right: next = (current + 1) % 3
                default: return
                }
                selectedTab = next; focusedTab = next
            }
    }

    private var general: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $store.configuration.language) {
                    Text("Follow system").tag(AppLanguage.system)
                    Text(verbatim: "English").tag(AppLanguage.english)
                    Text(verbatim: "简体中文").tag(AppLanguage.simplifiedChinese)
                }
            }
            Section("Keyboard") {
                LabeledContent("Global shortcut") { Text("⌥ Tab").font(.system(.body, design: .monospaced)) }
                Toggle("Enable ⌥Tab", isOn: $store.configuration.captureOptionTab)
                Toggle("Hold ⌥ to switch: release to confirm", isOn: $store.configuration.releaseToCommit)
                Text("By default, release ⌥ to keep the switcher open. Press a workspace key to jump, or Space / Return to confirm.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("App shortcuts") {
                    Text(store.configuration.appShortcuts == AppShortcut.functionKeys ? LocalizedStringKey("F1–F12") : LocalizedStringKey("Custom"))
                        .foregroundStyle(.secondary)
                    Button("Customize…") { showingAppShortcuts = true }
                }
                HStack {
                    Label(model.keyboardReady ? LocalizedStringKey("Keyboard control is ready") : LocalizedStringKey("Keyboard control is not ready"), systemImage: model.keyboardReady ? "checkmark.circle.fill" : "lock")
                        .foregroundStyle(model.keyboardReady ? Color.green : Color.secondary)
                    Spacer()
                    Button("Permissions & Setup…") { enableKeyboard() }
                }
            }
            Section("Workspace switcher") {
                Picker("Displays", selection: $store.configuration.displayMode) {
                    Text("All workspaces on the focused display").tag(DisplayMode.allOnActiveMonitor)
                    Text("Each display’s own workspaces").tag(DisplayMode.perMonitor)
                }
                Picker("Tab order", selection: $store.configuration.cycleOrder) {
                    Text("Most recently used").tag(CycleOrder.recent)
                    Text("Workspace order").tag(CycleOrder.workspace)
                }
                Toggle("Show empty workspaces", isOn: $store.configuration.showEmptyWorkspaces)
                Toggle("Show window previews", isOn: $store.configuration.capturePreviews)
                Toggle("Use Liquid Glass background", isOn: $store.configuration.glassBackground)
                Text("The default background is lightweight. Previews refresh on opening and stay still. Glass may use more GPU.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.configuration.capturePreviews && !model.screenCaptureGranted {
                    Text("Enable Screen Recording in Permissions & Setup for previews. Without it, known window positions are shown.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Hidden workspaces use their last recorded layout. Visit a workspace to record its positions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Connection & startup") {
                HStack {
                    TextField("AeroSpace CLI", text: $store.configuration.aerospacePath)
                    Button("Check connection") { model.refresh() }.disabled(model.isRefreshing)
                }
                if let error = model.lastError { Text(error).font(.caption).foregroundStyle(.red) }
                else { Text("Found \(model.snapshot.monitors.count) displays and \(model.snapshot.workspaces.count) workspaces")
                    .font(.caption).foregroundStyle(.secondary) }
                Toggle("Launch at login", isOn: $loginEnabled).onChange(of: loginEnabled) { _, value in
                    do {
                        if value { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch { loginError = error.localizedDescription }
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 22, for: .scrollContent)
            .contentMargins(.vertical, 0, for: .scrollContent)
    }

    private var workspaceStyles: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workspace order & appearance").font(.headline)
                    Text("Names are display labels. Empty keys use workspace names. Changes save automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh workspaces")
            }
            Picker("Order", selection: $store.configuration.workspaceOrderSource) {
                Text("Follow AeroSpace").tag(WorkspaceOrderSource.aerospace)
                Text("Custom order").tag(WorkspaceOrderSource.custom)
            }.pickerStyle(.segmented)
                .onChange(of: store.configuration.workspaceOrderSource) { _, value in
                    if value == .custom && store.configuration.customWorkspaceOrder.isEmpty {
                        store.configuration.customWorkspaceOrder = model.snapshot.orderedWorkspaces(
                            showEmpty: true, preferredOrder: model.aerospaceWorkspaceOrder).map(\.name)
                    }
                }
            if store.configuration.workspaceOrderSource == .aerospace {
                Text("Follows persistent-workspaces; other names follow. Empty workspaces are hidden by default.")
                    .font(.caption).foregroundStyle(.secondary)
                if let issue = model.workspaceOrderIssue {
                    Text(issue).font(.caption).foregroundStyle(.orange).lineLimit(3)
                }
            } else {
                Text("Use the arrows to reorder. The order is preserved when workspaces move between displays.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.snapshot.workspaces.isEmpty {
                ContentUnavailableView("No workspaces yet", systemImage: "rectangle.stack", description: Text("Start AeroSpace, then refresh."))
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.allWorkspaces) { workspace in
                            styleRow(workspace)
                        }
                    }.padding(.top, 4).padding(.bottom, 20)
                }
            }
        }.padding(.horizontal, 42).padding(.top, 20)
    }

    private func moveWorkspace(_ name: String, by delta: Int) {
        let names = model.allWorkspaces.map(\.name)
        guard let index = names.firstIndex(of: name), names.indices.contains(index + delta) else { return }
        var order = store.configuration.customWorkspaceOrder
        for value in names where !order.contains(value) { order.append(value) }
        guard let from = order.firstIndex(of: name), let to = order.firstIndex(of: names[index + delta]) else { return }
        order.swapAt(from, to)
        store.configuration.customWorkspaceOrder = order
    }

    private func styleBinding<T>(_ name: String, _ keyPath: WritableKeyPath<WorkspaceStyle, T>) -> Binding<T> {
        Binding(get: { store.configuration.style(for: name)[keyPath: keyPath] }, set: { value in
            var style = store.configuration.style(for: name)
            style[keyPath: keyPath] = value
            store.configuration.styles[name] = style
        })
    }

    private func styleRow(_ workspace: Workspace) -> some View {
        let style = store.configuration.style(for: workspace.name)
        let shortcut = store.configuration.shortcut(for: workspace.name)
        let conflict = shortcut.map { key in
            store.configuration.shortcuts(for: model.snapshot.workspaces)[key] == nil
        } ?? false
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(workspace.name).font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(style.color).frame(width: 38)
                TextField("Workspace \(workspace.name)", text: styleBinding(workspace.name, \.label))
                TextField("Key", text: styleBinding(workspace.name, \.shortcut)).frame(width: 50)
                    .help("Enter a letter or digit; leave blank to use the workspace name")
                Button { store.configuration.styles.removeValue(forKey: workspace.name) } label: {
                    Image(systemName: "arrow.counterclockwise")
                }.buttonStyle(.borderless).help("Reset appearance")
                if store.configuration.workspaceOrderSource == .custom {
                    Button { moveWorkspace(workspace.name, by: -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless).help("Move \(workspace.name) up").accessibilityLabel("Move \(workspace.name) up")
                        .disabled(model.allWorkspaces.first?.name == workspace.name)
                    Button { moveWorkspace(workspace.name, by: 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless).help("Move \(workspace.name) down").accessibilityLabel("Move \(workspace.name) down")
                        .disabled(model.allWorkspaces.last?.name == workspace.name)
                }
            }
            WorkspaceColorControls(style: styleBinding(workspace.name, \.self))
                .padding(.leading, 48)
            if conflict || shortcut == nil {
                if conflict { Text("Duplicate key; shortcut disabled").foregroundStyle(.orange).font(.caption) }
                else if shortcut == nil { Text("Use a single letter or digit").foregroundStyle(.secondary).font(.caption) }
            }
        }.padding(12).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private var help: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            Text("From windows back to work.").font(.system(size: 25, weight: .semibold, design: .rounded))
            Text("AeroTab · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 26, verticalSpacing: 14) {
                shortcutRow("⌥ Tab", "Open; release to keep it visible")
                shortcutRow("1–9 / A–Z", "Jump to a workspace (no need to hold ⌥)")
                shortcutRow("Tab / ⇧ Tab", "Select the next / previous workspace")
                shortcutRow("↑ ↓ ← →", "Move the selection")
                shortcutRow("Space / Return", "Enter the selected workspace")
                shortcutRow(store.configuration.appShortcuts == AppShortcut.functionKeys ? "F1–F12" : "Custom app keys", "Focus an app in the selected workspace")
                shortcutRow("Esc", "Cancel and keep the current focus")
                shortcutRow("⌘,", "Open settings while the switcher is visible")
            }
            Text("Customize keys in General → App shortcuts. Use fn with media keys. Click an app to focus it, or right-click to choose a window.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Unbind alt-tab and alt-shift-tab in AeroSpace and reload its configuration. AeroSpace continues to manage windows, layouts, and displays.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Link("AeroSpace", destination: URL(string: "https://github.com/nikitabobko/AeroSpace")!)
                Link("Inspired by AltTab", destination: URL(string: "https://github.com/lwouis/alt-tab-macos")!)
            }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 42).padding(.vertical, 20)
        }
    }

    private func shortcutRow(_ keys: String, _ description: String) -> some View {
        GridRow { Text(LocalizedStringKey(keys)).font(.system(.body, design: .monospaced)); Text(LocalizedStringKey(description)).foregroundStyle(.secondary) }
    }
}
