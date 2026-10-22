import AppKit
import ApplicationServices
import AeroTabCore
import Carbon

@MainActor
final class KeyboardController {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var router = KeyboardRouter()
    private var fallbackHotKey: EventHotKeyRef?
    private var fallbackHandler: EventHandlerRef?
    private let model: AppModel

    init(model: AppModel) { self.model = model }

    @discardableResult
    func start() -> Bool {
        stop()
        guard AXIsProcessTrusted() else {
            model.keyboardReady = false
            model.keyboardIssue = L10n.string("Enable Accessibility to switch workspaces with ⌥Tab.")
            installPermissionShortcut()
            return false
        }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                         callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let swallow = MainActor.assumeIsolated {
                let controller = Unmanaged<KeyboardController>.fromOpaque(info).takeUnretainedValue()
                return controller.handle(type: type, event: event)
            }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            model.keyboardReady = false
            model.keyboardIssue = L10n.string("Accessibility is allowed, but the keyboard listener is not connected. Recheck, or restart AeroTab.")
            installPermissionShortcut()
            return false
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        model.keyboardReady = true
        model.keyboardIssue = nil
        return true
    }

    func stop() {
        if let fallbackHotKey { UnregisterEventHotKey(fallbackHotKey) }
        if let fallbackHandler { RemoveEventHandler(fallbackHandler) }
        fallbackHotKey = nil; fallbackHandler = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; router.reset()
        model.keyboardReady = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            model.dismiss()
            router.reset()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp { return router.keyUp(code) }
        if type == .flagsChanged {
            if model.invocation.isActive && !event.flags.contains(.maskAlternate) { model.optionReleased() }
            return false
        }
        guard type == .keyDown else { return false }
        var modifiers: KeyModifiers = []
        if event.flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if event.flags.contains(.maskShift) { modifiers.insert(.shift) }
        if event.flags.contains(.maskCommand) { modifiers.insert(.command) }
        if event.flags.contains(.maskControl) { modifiers.insert(.control) }
        let decision = router.keyDown(code, characters: Self.shortcutCharacter(event), modifiers: modifiers,
                                      isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                                      isActive: model.invocation.isActive,
                                      captureOptionTab: model.settings.configuration.captureOptionTab,
                                      holdMode: model.settings.configuration.releaseToCommit,
                                      appShortcuts: model.appShortcutBindings)
        switch decision.action {
        case .none: break
        case .show(let advance):
            model.shortcutTestSucceeded = true
            if !model.isShowingSetup { model.show(advance: advance, followsOptionRelease: true) }
        case .cycle(let delta): model.cycle(delta)
        case .confirm: model.commit()
        case .dismiss: model.dismiss()
        case .settings:
            // Constructing and activating a settings window must not block the event tap callback.
            Task { @MainActor [weak self] in self?.model.openSettings() }
        case .workspace(let key): model.chooseShortcut(key)
        case .app(let index): model.chooseApp(at: index)
        }
        return decision.consume
    }

    private static func shortcutCharacter(_ event: CGEvent) -> String? {
        // Strip Option so ⌥A maps to A, not å; leave keyboard layout translation to AppKit.
        return NSEvent(cgEvent: event)?.characters(byApplyingModifiers: [])?.lowercased()
    }

    /// Carbon can receive a single registered hotkey without Accessibility. It only
    /// opens the setup guide; actual input interception still requires the event tap.
    private func installPermissionShortcut() {
        guard model.settings.configuration.captureOptionTab else { return }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let controller = Unmanaged<KeyboardController>.fromOpaque(context).takeUnretainedValue()
                controller.model.onSetup?()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &fallbackHandler)
        guard handlerStatus == noErr else { return }
        let status = RegisterEventHotKey(UInt32(kVK_Tab), UInt32(optionKey), EventHotKeyID(signature: 0x41544250, id: 1),
                                         GetApplicationEventTarget(), 0, &fallbackHotKey)
        if status != noErr { model.keyboardIssue = L10n.string("⌥Tab could not be registered. Another app may be using it. Free the shortcut and recheck.") }
    }
}
