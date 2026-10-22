import Foundation
import Testing
@testable import AeroTabCore

@Suite("Language preferences")
struct LanguageTests {
    @Test("Existing settings gain system language without losing custom keys")
    func migrate() throws {
        let data = Data(#"{"schemaVersion":3,"appShortcuts":["z","x"],"showEmptyWorkspaces":true}"#.utf8)
        let config = try JSONDecoder().decode(Configuration.self, from: data)
        #expect(config.language == .system)
        #expect(config.appShortcuts == ["z", "x"])
        #expect(config.showEmptyWorkspaces)
    }

    @Test("Explicit languages survive saving and resolve independently of system language")
    func roundTrip() throws {
        for language in [AppLanguage.english, .simplifiedChinese] {
            var config = Configuration()
            config.language = language
            config.styles["A"] = WorkspaceStyle(label: "Project")
            let saved = try JSONEncoder().encode(config)
            let restored = try JSONDecoder().decode(Configuration.self, from: saved)
            #expect(restored == config)
            #expect(restored.language.locale.identifier == language.rawValue)
        }
    }
}
