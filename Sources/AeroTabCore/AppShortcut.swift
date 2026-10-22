import Foundation

/// Plain keys used only while the switcher is open. Navigation and modified system keys are reserved.
public enum AppShortcut {
    public static let functionKeys = (1...12).map { "f\($0)" }
    public static let bottomRow = ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "", ""]
    public static let defaultBindings = Dictionary(uniqueKeysWithValues: functionKeys.enumerated().map { ($0.element, $0.offset) })
    private static let functionKeyCodes: [Int64: String] = [122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
                                                          98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12"]

    public static func normalize(_ value: String) -> String? {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if functionKeys.contains(key) { return key }
        guard key.count == 1, "abcdefghijklmnopqrstuvwxyz0123456789,./;'[]\\-=`".contains(key) else { return nil }
        return key
    }

    public static func key(code: Int64, characters: String?) -> String? {
        functionKeyCodes[code] ?? characters.flatMap(normalize)
    }

    public static func isFunctionKey(_ code: Int64) -> Bool { functionKeyCodes[code] != nil }
}
