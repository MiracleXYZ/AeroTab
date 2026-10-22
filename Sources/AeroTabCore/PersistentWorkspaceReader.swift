import Foundation

/// Reads only the root string-array option. Other TOML values are skipped lexically,
/// including comments and multiline strings; they are never evaluated as commands.
public enum PersistentWorkspaceReader {
    public static func read(_ source: String) throws -> [String] {
        var lexer = Lexer(source)
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

    private enum Token: Equatable {
        case word(String), string(String), mark(Character), newline
    }

    private struct Lexer {
        let chars: [Character]
        var index = 0
        init(_ source: String) { chars = Array(source) }
        var current: Character? { index < chars.count ? chars[index] : nil }

        mutating func next() throws -> Token? {
            while let c = current {
                if c == " " || c == "\t" || c == "\r" || c == "\u{FEFF}" { index += 1; continue }
                if c == "#" {
                    while let c = current, c != "\n", c != "\r\n" { index += 1 }
                    continue
                }
                if c == "\n" || c == "\r\n" { index += 1; return .newline }
                if c == "\"" || c == "'" { return .string(try string()) }
                if "[]=,{}.".contains(c) { index += 1; return .mark(c) }
                let start = index
                while let c = current, !c.isWhitespace, !"#[]=,{}.\"'".contains(c) { index += 1 }
                guard index > start else { throw InvalidArray() }
                return .word(String(chars[start..<index]))
            }
            return nil
        }

        mutating func string() throws -> String {
            let quote = chars[index]
            let triple = index + 2 < chars.count && chars[index + 1] == quote && chars[index + 2] == quote
            index += triple ? 3 : 1
            if triple, current == "\n" || current == "\r\n" { index += 1 }
            var result = ""
            while let c = current {
                if c == quote {
                    if !triple { index += 1; return result }
                    var count = 0
                    while current == quote { count += 1; index += 1 }
                    if count >= 3 {
                        guard count <= 5 else { throw InvalidArray() }
                        result += String(repeating: String(quote), count: count - 3)
                        return result
                    }
                    result += String(repeating: String(quote), count: count)
                    continue
                }
                index += 1
                if c == "\\", quote == "\"" {
                    guard let escaped = current else { throw InvalidArray() }
                    if triple, escaped.isWhitespace {
                        while let whitespace = current, whitespace.isWhitespace { index += 1 }
                        continue
                    }
                    index += 1
                    switch escaped {
                    case "b": result += "\u{08}"
                    case "t": result += "\t"
                    case "n": result += "\n"
                    case "f": result += "\u{0C}"
                    case "r": result += "\r"
                    case "\"": result += "\""
                    case "\\": result += "\\"
                    case "u", "U":
                        let count = escaped == "u" ? 4 : 8
                        guard index + count <= chars.count,
                              let code = UInt32(String(chars[index..<index + count]), radix: 16),
                              let scalar = UnicodeScalar(code) else { throw InvalidArray() }
                        index += count; result.unicodeScalars.append(scalar)
                    default: throw InvalidArray()
                    }
                } else {
                    if !triple && c.isNewline { throw InvalidArray() }
                    result.append(c)
                }
            }
            throw InvalidArray()
        }
    }
}
