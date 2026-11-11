import Foundation

/// Reads only the root string-array option. Other TOML values are skipped lexically,
/// including comments and multiline strings; they are never evaluated as commands.
public enum PersistentWorkspaceReader {
    public static func read(_ source: String) throws -> [String] {
        do { return try readArray(source) }
        catch { throw InvalidArray() }
    }

    private static func readArray(_ source: String) throws -> [String] {
        var lexer = TOMLLexer(source)
        var lineStart = true, depth = 0
        while let token = try lexer.next() {
            if token == .newline { lineStart = depth == 0; continue }
            if lineStart && depth == 0 {
                if token == .mark("[") { return [] } // All root keys precede table declarations.
                if token == .word("persistent-workspaces") || token == .string("persistent-workspaces") {
                    guard try lexer.next() == .mark("="), try lexer.next() == .mark("[") else { throw InvalidArray() }
                    var names: [String] = [], expectsValue = true
                    while let item = try lexer.next() {
                        switch item {
                        case .newline: continue
                        case .mark("]"): return names
                        case .string(let name) where expectsValue:
                            names.append(name); expectsValue = false
                        case .mark(",") where !expectsValue: expectsValue = true
                        default: throw InvalidArray()
                        }
                    }
                    throw InvalidArray()
                }
            }
            if token == .mark("[") || token == .mark("{") { depth += 1 }
            if token == .mark("]") || token == .mark("}") { depth -= 1 }
            lineStart = false
        }
        return []
    }

    private struct InvalidArray: LocalizedError {
        var errorDescription: String? { L10n.string("persistent-workspaces must be a TOML array of strings.") }
    }
}
