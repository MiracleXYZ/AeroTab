import Foundation

public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let option = Self(rawValue: 1)
    public static let shift = Self(rawValue: 2)
    public static let command = Self(rawValue: 4)
    public static let control = Self(rawValue: 8)
}

public enum KeyAction: Equatable, Sendable {
    case none, show(advance: Int), cycle(Int), confirm, dismiss, settings, workspace(String), app(Int)
}

public struct KeyDecision: Equatable, Sendable {
    public var consume: Bool
    public var action: KeyAction
}

public struct KeyboardRouter: Sendable {
    private var consumedKeys: Set<Int64> = []
    public init() {}
    public mutating func reset() { consumedKeys.removeAll() }
    public mutating func keyUp(_ code: Int64) -> Bool { consumedKeys.remove(code) != nil }

    public mutating func keyDown(_ code: Int64, characters: String? = nil, modifiers: KeyModifiers = [],
                                 isRepeat: Bool = false, isActive: Bool, captureOptionTab: Bool = true,
                                 holdMode: Bool = false, appShortcuts: [String: Int] = AppShortcut.defaultBindings) -> KeyDecision {
        if isRepeat && consumedKeys.contains(code) && !isActive {
            return KeyDecision(consume: true, action: .none)
        }
        let action: KeyAction
        let hasOtherModifiers = !modifiers.intersection([.command, .control]).isEmpty
        if code == 48, modifiers.contains(.option), !hasOtherModifiers, captureOptionTab {
            let delta = modifiers.contains(.shift) ? -1 : 1
            action = .show(advance: isActive || holdMode ? delta : 0)
        } else if !isActive {
            return KeyDecision(consume: false, action: .none)
        } else if modifiers == .command && (characters == "," || (characters == nil && code == 43)) {
            action = .settings
        } else if hasOtherModifiers {
            return KeyDecision(consume: false, action: .dismiss)
        } else {
            switch code {
            case 53: action = .dismiss
            case 36, 49, 76: action = .confirm
            case 48: action = .cycle(modifiers.contains(.shift) ? -1 : 1)
            case 123, 126: action = .cycle(-1)
            case 124, 125: action = .cycle(1)
            default:
                if let key = AppShortcut.key(code: code, characters: characters), let index = appShortcuts[key] { action = .app(index) }
                else if AppShortcut.isFunctionKey(code) {
                    // Let screenshot utilities receive unbound function keys without closing the overlay.
                    return KeyDecision(consume: false, action: .none)
                }
                else if let characters { action = .workspace(characters.lowercased()) }
                else { action = .none }
            }
        }
        consumedKeys.insert(code)
        return KeyDecision(consume: true, action: action)
    }
}
