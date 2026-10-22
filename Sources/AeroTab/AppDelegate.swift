import AppKit
import SwiftUI
import ApplicationServices
import AeroTabCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let model: AppModel
    private var keyboard: KeyboardController!
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var statusMenuItem: NSMenuItem!
    private var observers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?
    private var launched = false
    private var pendingDestination: AppDestination?

    init(settingsURL: URL?) {
        model = AppModel(settings: SettingsStore(url: settingsURL ?? SettingsStore.defaultURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        keyboard = KeyboardController(model: model)
        overlay = OverlayController(model: model)
        model.onPresent = { [weak self] in self?.overlay.present() }
        model.onDismiss = { [weak self] in self?.overlay.dismiss() }
        model.onStatusChange = { [weak self] in self?.updateStatus() }
        model.onSetup = { [weak self] in self?.showSetup() }
        model.onSettings = { [weak self] in self?.showSettings() }
        model.settings.onLanguageChange = { [weak self] in
            guard let self else { return }
            self.localizeMenu()
            self.settingsWindow?.title = L10n.string("AeroTab Settings")
            self.setupWindow?.title = L10n.string("Welcome to AeroTab")
            self.keyboard.start()
            self.model.refresh()
            self.updateStatus()
        }
        createStatusItem()
        keyboard.start()
        refreshPermissions()
        model.start()
        updateStatus()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshPermissions()
                self.model.observeDesktop()
            }
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model.dismiss(); self?.model.refresh(); self?.restoreStatusItemIfNeeded()
            }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.model.dismiss() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.restoreStatusItemIfNeeded() }
            })
        }
        launched = true
        if let destination = pendingDestination {
            pendingDestination = nil
            navigate(to: destination)
        } else if KeyboardReadiness(accessibility: model.accessibilityGranted, listener: model.keyboardReady)
            .needsSetup(completed: model.settings.configuration.onboardingCompleted) { showSetup() }
    }

    private func createStatusItem() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        let newItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = newItem
        newItem.autosaveName = "AeroTab.MainStatusItem"
        newItem.behavior = []
        newItem.isVisible = true
        configureStatusButton()
        let menu = NSMenu()
        menu.delegate = self
        statusMenuItem = menu.addItem(withTitle: "AeroTab", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        item("Show workspaces", action: #selector(showSwitcher), in: menu)
        item("Settings…", action: #selector(showSettings), key: ",", in: menu)
        item("Permissions & Setup…", action: #selector(showSetup), in: menu)
        menu.addItem(.separator())
        item("Quit AeroTab", action: #selector(quit), key: "q", in: menu)
        newItem.menu = menu
    }

    private func configureStatusButton() {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "AeroTab")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        image?.isTemplate = true
        button.image = image
        // Keep a usable menu target even if the system symbol cannot be loaded.
        button.title = image == nil ? "AT" : ""
        button.font = .systemFont(ofSize: 10, weight: .semibold)
        button.appearsDisabled = false
        button.setAccessibilityLabel("AeroTab")
    }

    private func restoreStatusItemIfNeeded() {
        guard let statusItem, let button = statusItem.button else {
            createStatusItem(); updateStatus(); return
        }
        if !statusItem.isVisible { statusItem.isVisible = true }
        if button.image == nil && button.title.isEmpty { configureStatusButton() }
        updateStatus()
        // isVisible remains true when macOS obscures an item for lack of space.
        // Settings therefore also has entry points independent of the status item.
    }

    private func item(_ title: String, action: Selector, key: String = "", in menu: NSMenu) {
        let item = menu.addItem(withTitle: L10n.key(title), action: action, keyEquivalent: key)
        item.representedObject = title
        item.target = self
    }

    private func localizeMenu() {
        for item in statusItem?.menu?.items ?? [] {
            if let key = item.representedObject as? String { item.title = L10n.key(key) }
        }
    }

    func menuWillOpen(_ menu: NSMenu) { updateStatus() }

    private func updateStatus() {
        let title: String
        if model.lastError != nil { title = L10n.string("AeroSpace connection issue · Open settings") }
        else if !model.settings.configuration.captureOptionTab { title = L10n.string("⌥Tab is disabled in settings") }
        else if !model.keyboardReady { title = L10n.string("⌥Tab unavailable · Complete setup") }
        else { title = L10n.string("AeroTab · ⌥Tab ready") }
        if statusMenuItem?.title != title { statusMenuItem?.title = title }
        if statusItem?.button?.toolTip != title { statusItem?.button?.toolTip = title }
    }

    @objc private func showSwitcher() {
        if !model.keyboardReady { showSetup() } else { model.show() }
    }

    @objc private func showSettings() {
        model.dismiss()
        setupWindow?.close()
        model.isShowingSetup = false
        if settingsWindow == nil {
            let view = SettingsView(model: model, enableKeyboard: { [weak self] in self?.showSetup() }, store: model.settings)
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = L10n.string("AeroTab Settings")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.deminiaturize(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        model.refresh()
    }

    @objc private func enableKeyboard() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrusted() { _ = AXIsProcessTrustedWithOptions(options) }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func refreshPermissions() {
        let accessibility = AXIsProcessTrusted()
        if model.accessibilityGranted != accessibility { model.accessibilityGranted = accessibility }
        let previousScreenAccess = model.screenCaptureGranted
        let screenAccess = CGPreflightScreenCaptureAccess()
        if previousScreenAccess != screenAccess { model.screenCaptureGranted = screenAccess }
        if !model.keyboardReady && model.accessibilityGranted { keyboard.start() }
        if model.keyboardReady && !model.accessibilityGranted { keyboard.start(); model.dismiss() }
        if previousScreenAccess && !model.screenCaptureGranted { model.previews.cancelCapture(clearImages: true) }
        updateStatus()
    }

    @objc private func showSetup() {
        model.dismiss()
        model.isShowingSetup = true
        if setupWindow == nil {
            let view = SetupView(model: model, requestAccessibility: { [weak self] in self?.enableKeyboard() },
                                 requestScreenCapture: { [weak self] in self?.enablePreviews() },
                                 recheck: { [weak self] in self?.keyboard.start(); self?.refreshPermissions() },
                                 finish: { [weak self] in self?.finishSetup() },
                                 later: { [weak self] in self?.setupWindow?.close() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = L10n.string("Welcome to AeroTab")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            setupWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        setupWindow?.makeKeyAndOrderFront(nil)
    }

    private func enablePreviews() {
        model.settings.configuration.capturePreviews = true
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    private func finishSetup() {
        guard model.keyboardReady else { return }
        model.settings.configuration.onboardingCompleted = true
        setupWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === setupWindow { model.isShowingSetup = false }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let destination = urls.compactMap({ AppDestination(url: $0) }).first else { return }
        if launched { navigate(to: destination) }
        else { pendingDestination = destination }
    }

    private func navigate(to destination: AppDestination) {
        switch destination {
        case .switcher: showSwitcher()
        case .settings: showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if launched { showSettings() }
        else { pendingDestination = .settings }
        return false
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        keyboard.stop(); model.stop()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        settingsWindow?.close()
        setupWindow?.close()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}
