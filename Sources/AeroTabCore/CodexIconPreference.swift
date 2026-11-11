import Foundation

/// Compatibility with the desktop app's persisted icon selection. Unknown formats
/// fall back to the system icon; no image assets are bundled or downloaded.
public enum CodexIconPreference: String, Sendable {
    case appDefault = "app-default"
    case codexSystem = "codex-system"
    case spaceSystem = "space-system"

    public func resourceName(dark: Bool) -> String? {
        switch self {
        case .appDefault: nil
        case .codexSystem: dark ? "icon-codex-dark-color.png" : "icon-codex-light.png"
        case .spaceSystem: dark ? "icon-space-dark.png" : "icon-space-light.png"
        }
    }

    public static func read(_ source: String) -> Self? {
        try? readValue(source)
    }

    private static func readValue(_ source: String) throws -> Self? {
        var lexer = TOMLLexer(source)
        var table: [String] = [], line: [TOMLToken] = [], depth = 0
        var result: Self?
        func path(_ tokens: ArraySlice<TOMLToken>) -> [String]? {
            var components: [String] = [], expectsKey = true
            for token in tokens {
                switch token {
                case .word(let key), .string(let key):
                    guard expectsKey else { return nil }
                    components.append(key); expectsKey = false
                case .mark(".") where !expectsKey: expectsKey = true
                default: return nil
                }
            }
            return !components.isEmpty && !expectsKey ? components : nil
        }
        func consumeLine() {
            defer { line.removeAll(keepingCapacity: true) }
            guard let first = line.first else { return }
            if first == .mark("[") {
                table = line.last == .mark("]") ? path(line.dropFirst().dropLast()) ?? [""] : [""]
                return
            }
            guard let equals = line.firstIndex(of: .mark("=")),
                  let key = path(line[..<equals]),
                  table + key == ["desktop", "dock-icon-preference"],
                  line.count == equals + 2, case .string(let value) = line[equals + 1] else { return }
            result = Self(rawValue: value)
        }
        while let token = try lexer.next() {
            if token == .newline {
                if depth == 0 { consumeLine() }
                continue
            }
            line.append(token)
            if token == .mark("[") || token == .mark("{") { depth += 1 }
            if token == .mark("]") || token == .mark("}") { depth -= 1 }
            guard depth >= 0 else { return nil }
        }
        guard depth == 0 else { return nil }
        consumeLine()
        return result
    }
}
