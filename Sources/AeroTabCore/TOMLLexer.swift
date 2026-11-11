import Foundation

/// Tokenizes config values without evaluating commands or interpreting unrelated settings.
enum TOMLToken: Equatable {
    case word(String), string(String), mark(Character), newline
}

struct TOMLLexer {
    private struct InvalidString: Error {}
    let chars: [Character]
    var index = 0
    init(_ source: String) { chars = Array(source) }
    var current: Character? { index < chars.count ? chars[index] : nil }

    mutating func next() throws -> TOMLToken? {
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
            guard index > start else { throw InvalidString() }
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
                    guard count <= 5 else { throw InvalidString() }
                    result += String(repeating: String(quote), count: count - 3)
                    return result
                }
                result += String(repeating: String(quote), count: count)
                continue
            }
            index += 1
            if c == "\\", quote == "\"" {
                guard let escaped = current else { throw InvalidString() }
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
                          let scalar = UnicodeScalar(code) else { throw InvalidString() }
                    index += count; result.unicodeScalars.append(scalar)
                default: throw InvalidString()
                }
            } else {
                if !triple && c.isNewline { throw InvalidString() }
                result.append(c)
            }
        }
        throw InvalidString()
    }
}
