import Foundation
import Testing
@testable import AeroTabCore

@Suite("Custom workspace colors")
struct HexColorTests {
    @Test("HEX accepts three or six ASCII digits with optional hash and normalizes to RGB")
    func parse() throws {
        #expect(HexColor(" #a7f\n")?.hex == "#AA77FF")
        let color = try #require(HexColor("12abEF"))
        #expect(color.hex == "#12ABEF")
        #expect(color.red == 18.0 / 255)
        #expect(color.green == 171.0 / 255)
        #expect(color.blue == 239.0 / 255)
        for value in ["", "#", "12", "1234", "12345", "#12345678", "#GG0000", "##123456", "12 3456", "ＦＦＦ", "0x123456"] {
            #expect(HexColor(value) == nil)
        }
    }

    @Test("Selected workspace labels remain readable on light and dark custom colors")
    func foreground() {
        #expect(HexColor("#FFFFFF")?.prefersDarkForeground == true)
        #expect(HexColor("#FFFF00")?.prefersDarkForeground == true)
        #expect(HexColor("#000000")?.prefersDarkForeground == false)
        #expect(HexColor("#000080")?.prefersDarkForeground == false)
    }

    @Test("Existing per-workspace styles decode without a custom color and retain all settings")
    func migration() throws {
        let data = Data(#"{"label":"阅读","symbol":"book","tint":"mint","shortcut":"r"}"#.utf8)
        let style = try JSONDecoder().decode(WorkspaceStyle.self, from: data)
        #expect(style.label == "阅读" && style.shortcut == "r" && style.tint == .mint)
        #expect(style.customColorHex == nil)
    }

    @Test("Custom color survives saving and malformed overrides fall back without losing the style")
    func persistence() throws {
        var configuration = Configuration()
        configuration.styles["R"] = WorkspaceStyle(label: "阅读", tint: .mint, shortcut: "r", customColorHex: "#a7f")
        let roundtrip = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(configuration))
        #expect(roundtrip == configuration)
        #expect(roundtrip.style(for: "R").customColor?.hex == "#AA77FF")
        let invalid = Data(#"{"label":"阅读","symbol":"book","tint":"mint","shortcut":"r","customColorHex":"broken"}"#.utf8)
        let style = try JSONDecoder().decode(WorkspaceStyle.self, from: invalid)
        #expect(style.customColor == nil)
        #expect(style.tint == .mint && style.label == "阅读" && style.shortcut == "r")
    }
}
