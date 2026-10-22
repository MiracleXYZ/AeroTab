import AppKit
import SwiftUI
import AeroTabCore

private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
    private var panels: [NSPanel] = []
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private let model: AppModel

    init(model: AppModel) { self.model = model }

    func present() {
        dismiss()
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        if model.settings.configuration.displayMode == .perMonitor && model.lastError == nil {
            for monitor in model.snapshot.monitors {
                guard model.workspaces.contains(where: { $0.monitorID == monitor.id }) else { continue }
                let index = monitor.screenIndex - 1
                guard screens.indices.contains(index) else { continue }
                addPanel(screen: screens[index], monitorID: monitor.id)
            }
        }
        if panels.isEmpty {
            let focusedID = model.snapshot.focusedWorkspace?.monitorID
            let index = model.snapshot.monitors.first { $0.id == focusedID }.map { $0.screenIndex - 1 } ?? 0
            addPanel(screen: screens[screens.indices.contains(index) ? index : 0], monitorID: nil)
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.model.dismiss() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if !self.panels.contains(where: { $0 == event.window }) { self.model.dismiss() }
            return event
        }
    }

    private func addPanel(screen: NSScreen, monitorID: Int?) {
        let visible = screen.visibleFrame
        let workspaces = model.workspaces.filter { monitorID == nil || $0.monitorID == monitorID }
        let extra = !model.screenCaptureGranted && model.settings.configuration.capturePreviews ? 24.0 : 0
        let metrics = SwitcherMetrics(count: workspaces.count, availableWidth: visible.width, availableHeight: visible.height, extraHeight: extra)
        let width = metrics.width, height = metrics.height
        let frame = NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
        let panel = SwitcherPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "AeroTab Switcher"
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.contentView = NSHostingView(rootView: SwitcherView(model: model, monitorID: monitorID, metrics: metrics))
        panel.setFrame(frame, display: false)
        panels.append(panel)
        // Non-activating and never key: the current application keeps its focus until commit.
        panel.orderFrontRegardless()
    }

    func dismiss() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        clickMonitor = nil; localClickMonitor = nil
        for panel in panels { panel.orderOut(nil); panel.close() }
        panels.removeAll()
    }
}
