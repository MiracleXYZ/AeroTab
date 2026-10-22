import AppKit
import Observation
import AeroTabCore

@MainActor @Observable
final class AppModel {
    let settings: SettingsStore
    var snapshot: Snapshot = .empty
    var selection = Selection()
    var invocation = Invocation()
    var lastError: String?
    var keyboardReady = false
    var accessibilityGranted = false
    var screenCaptureGranted = false
    var keyboardIssue: String?
    var isShowingSetup = false
    var shortcutTestSucceeded = false
    let previews = WindowPreviewStore()
    var isSwitching = false
    var isRefreshing = false
    var aerospaceWorkspaceOrder: [String] = []
    var workspaceOrderIssue: String?
    @ObservationIgnored var onPresent: (() -> Void)?
    @ObservationIgnored var onDismiss: (() -> Void)?
    @ObservationIgnored var onStatusChange: (() -> Void)?
    @ObservationIgnored var onSetup: (() -> Void)?
    @ObservationIgnored var onSettings: (() -> Void)?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var preferredWindowIDs: [String: Int] = [:]
    @ObservationIgnored let subscription = FocusSubscription()
    @ObservationIgnored private var refreshDebounce: Task<Void, Never>?

    init(settings: SettingsStore) { self.settings = settings }

    var client: AeroSpaceClient { AeroSpaceClient(executable: settings.configuration.aerospacePath) }
    var preferredWorkspaceOrder: [String] {
        settings.configuration.workspaceOrderSource == .custom
            ? settings.configuration.customWorkspaceOrder : aerospaceWorkspaceOrder
    }
    var workspaces: [Workspace] { snapshot.orderedWorkspaces(showEmpty: settings.configuration.showEmptyWorkspaces, preferredOrder: preferredWorkspaceOrder) }
    var allWorkspaces: [Workspace] { snapshot.orderedWorkspaces(showEmpty: true, preferredOrder: preferredWorkspaceOrder) }
    var selectedWorkspace: Workspace? { snapshot.workspaces.first { $0.name == selection.selected } }
    var selectedApps: [WorkspaceApp] { selection.selected.map { snapshot.apps(in: $0, layout: previews.layouts[$0]) } ?? [] }
    var appShortcutBindings: [String: Int] { settings.configuration.appShortcutBindings(for: snapshot.workspaces) }
    func appShortcutLabel(at index: Int) -> String? { appShortcutBindings.first { $0.value == index }?.key.uppercased() }
    var shortcuts: [String: String] { settings.configuration.shortcuts(for: workspaces) }

    func start() {
        subscription.onFocus = { [weak self] name, windowID in
            guard let self else { return }
            self.selection.recordFocus(name)
            if let windowID { self.preferredWindowIDs[name] = windowID }
            self.refreshDebounce?.cancel()
            self.refreshDebounce = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
        subscription.start(path: settings.configuration.aerospacePath)
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            do {
                async let order = client.workspaceOrder()
                let fresh = try await client.snapshot()
                let workspaceOrder = await order
                guard !invocation.isActive else { return }
                applyWorkspaceOrder(workspaceOrder)
                snapshot = filtered(fresh); lastError = nil
                previews.updateGeometry(snapshot)
                if let focused = fresh.focusedWorkspace { selection.recordFocus(focused.name) }
            } catch { lastError = error.localizedDescription }
            onStatusChange?()
        }
    }

    func show(advance: Int = 0, followsOptionRelease: Bool = false) {
        guard !isSwitching else { return }
        if invocation.isActive { cycle(advance == 0 ? 1 : advance); return }
        lastError = nil
        let generation = invocation.begin(advance: advance, followsOptionRelease: followsOptionRelease)
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let order = client.workspaceOrder()
                let fresh = try await client.snapshot()
                let workspaceOrder = await order
                guard !Task.isCancelled, invocation.markReady(generation: generation) else { return }
                applyWorkspaceOrder(workspaceOrder)
                snapshot = filtered(fresh)
                previews.updateGeometry(snapshot)
                selection.begin(workspaces: workspaces, focused: fresh.focusedWorkspace?.name,
                                order: settings.configuration.cycleOrder, advance: invocation.advance)
                if let key = invocation.pendingShortcut, let name = shortcuts[key] {
                    selection.select(name)
                    if !settings.configuration.releaseToCommit { commit(); return }
                }
                if invocation.commitWhenReady { commit(); return }
                onPresent?()
                previews.capture(snapshot, enabled: settings.configuration.capturePreviews,
                                 workspaceOrder: workspaces.map(\.name), selectedWorkspace: selection.selected)
            } catch {
                guard !Task.isCancelled, invocation.generation == generation else { return }
                // Fail visibly only after the user requested the switcher. No startup alert.
                _ = invocation.markReady(generation: generation)
                lastError = error.localizedDescription
                selection.end()
                onPresent?(); onStatusChange?()
            }
        }
    }

    func cycle(_ delta: Int) {
        if invocation.phase == .loading { invocation.enqueueCycle(delta) }
        else { selection.cycle(delta) }
    }

    func chooseShortcut(_ key: String) {
        if invocation.phase == .loading { invocation.enqueueShortcut(key); return }
        if let name = shortcuts[key] {
            selection.select(name)
            if !settings.configuration.releaseToCommit { commit() }
        }
    }

    func optionReleased() {
        guard invocation.followsOptionRelease, settings.configuration.releaseToCommit else { return }
        if invocation.phase == .loading { invocation.requestCommit() }
        else if lastError == nil { commit() }
    }

    func commit() {
        if invocation.phase == .loading { invocation.requestCommit(); return }
        guard let name = selection.selected else { return }
        perform(.workspace(name))
    }

    func chooseWorkspace(_ name: String) {
        selection.select(name)
        commit()
    }

    func chooseApp(at index: Int) {
        guard selectedApps.indices.contains(index) else { return }
        let app = selectedApps[index]
        let preferred = selection.selected.flatMap { preferredWindowIDs[$0] }
        let window = app.windows.first { $0.id == preferred } ?? app.windows.first
        if let window { perform(.window(window.id)) }
    }

    func chooseWindow(_ id: Int) { perform(.window(id)) }

    private func perform(_ target: SwitchTarget) {
        guard !isSwitching else { return }
        dismiss()
        isSwitching = true
        Task {
            defer { isSwitching = false; onStatusChange?() }
            do { try await client.focus(target); lastError = nil }
            catch {
                lastError = error.localizedDescription
                let generation = invocation.begin(advance: 0, followsOptionRelease: false)
                _ = invocation.markReady(generation: generation)
                onPresent?()
            }
        }
    }

    func dismiss() {
        loadTask?.cancel(); loadTask = nil
        invocation.cancel(); selection.end()
        previews.cancelCapture(clearImages: true)
        onDismiss?()
    }

    func openSettings() {
        dismiss()
        onSettings?()
    }

    private func filtered(_ snapshot: Snapshot) -> Snapshot {
        var result = snapshot
        result.windows.removeAll { $0.bundleID == Bundle.main.bundleIdentifier || $0.pid == ProcessInfo.processInfo.processIdentifier }
        return result
    }

    func observeDesktop() {
        // A visible switcher is a snapshot, not a live video wall. Keep its layout and
        // pixels stable until dismissal; only record hidden-overlay desktop geometry.
        guard !invocation.isActive else { return }
        previews.updateGeometry(snapshot)
    }

    private func applyWorkspaceOrder(_ value: AeroSpaceWorkspaceOrder) {
        if aerospaceWorkspaceOrder != value.names { aerospaceWorkspaceOrder = value.names }
        if workspaceOrderIssue != value.issue { workspaceOrderIssue = value.issue }
    }

    func stop() { refreshDebounce?.cancel(); dismiss(); subscription.stop() }
}
