import Foundation

public struct HexColor: Equatable, Sendable {
    public let rgb: UInt32

    public init?(_ text: String) {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 3 || value.count == 6,
              value.unicodeScalars.allSatisfy({ "0123456789abcdefABCDEF".unicodeScalars.contains($0) }) else { return nil }
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        guard let rgb = UInt32(value, radix: 16) else { return nil }
        self.rgb = rgb
    }

    public var hex: String { String(format: "#%06X", rgb) }
    public var red: Double { Double((rgb >> 16) & 255) / 255 }
    public var green: Double { Double((rgb >> 8) & 255) / 255 }
    public var blue: Double { Double(rgb & 255) / 255 }

    public var prefersDarkForeground: Bool {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue) > 0.179
    }
}
