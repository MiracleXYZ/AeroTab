import Testing
@testable import AeroTabCore

@Suite("Desktop icon preference compatibility")
struct CodexIconPreferenceTests {
    @Test("Read the selected icon from desktop settings, including quoted and dotted keys")
    func selectedIcon() {
        for source in [
            "[desktop]\ndock-icon-preference = \"codex-system\" # selected in the app\n",
            "['desktop']\n'dock-icon-preference' = 'codex-system'\n[other]\nvalue = 1",
            "desktop.dock-icon-preference = 'codex-system'\n",
            "[desktop]\n\"dock-icon-preference\" = 'codex-system'\r\n"
        ] {
            #expect(CodexIconPreference.read(source) == .codexSystem)
        }
    }

    @Test("Comments, multiline strings, arrays and other tables cannot impersonate the desktop icon setting")
    func ignoreUnrelatedSettings() {
        let source = #"""
        # desktop.dock-icon-preference = 'space-system'
        note = '''
        [desktop]
        dock-icon-preference = 'space-system'
        '''
        commands = [
          "[desktop]", "dock-icon-preference = 'space-system'",
        ]
        [desktop]
        dock-icon-preference = 'codex-system'
        [desktop.other]
        dock-icon-preference = 'space-system'
        [[profiles]]
        desktop.dock-icon-preference = 'space-system'
        """#
        #expect(CodexIconPreference.read(source) == .codexSystem)
        #expect(CodexIconPreference.read("[other]\ndock-icon-preference = 'codex-system'") == nil)
        #expect(CodexIconPreference.read("dock-icon-preference = 'codex-system'") == nil)
    }

    @Test("Missing, malformed or unknown preferences safely fall back; default never forces a replacement")
    func fallback() {
        for source in ["", "[desktop]\ndock-icon-preference = false", "[desktop]\ndock-icon-preference = '../icon.png'",
                       "[desktop]\ndock-icon-preference = 'future-choice'", "[desktop]\ndock-icon-preference = 'codex-system",
                       "[desktop\ndock-icon-preference = 'codex-system'"] {
            #expect(CodexIconPreference.read(source) == nil)
        }
        let value = CodexIconPreference.read("[desktop]\ndock-icon-preference = 'app-default'")
        #expect(value == .appDefault)
        #expect(value?.resourceName(dark: false) == nil)
        #expect(value?.resourceName(dark: true) == nil)
    }

    @Test("Light and dark appearance select the installed app's corresponding icon resource")
    func appearance() {
        #expect(CodexIconPreference.codexSystem.resourceName(dark: false) == "icon-codex-light.png")
        #expect(CodexIconPreference.codexSystem.resourceName(dark: true) == "icon-codex-dark-color.png")
        #expect(CodexIconPreference.spaceSystem.resourceName(dark: false) == "icon-space-light.png")
        #expect(CodexIconPreference.spaceSystem.resourceName(dark: true) == "icon-space-dark.png")
    }
}
