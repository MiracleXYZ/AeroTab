import Foundation
import Testing
@testable import AeroTabCore

@Suite("Configurable app shortcuts")
struct AppShortcutTests {
    @Test("Old settings retain all twelve function-key defaults")
    func compatibleDefaults() throws {
        let settings = try JSONDecoder().decode(Configuration.self, from: Data("{}".utf8))
        #expect(settings.appShortcuts == AppShortcut.functionKeys)
        var router = KeyboardRouter()
        for (index, code) in [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111].enumerated() {
            #expect(router.keyDown(Int64(code), isActive: true, appShortcuts: settings.appShortcutBindings(for: [])).action == .app(index))
        }
    }

    @Test("Custom keys persist without changing defaults or unrelated preferences")
    func persistence() throws {
        var settings = Configuration()
        settings.appShortcuts = ["Z", "x", "", ",", "F8"]
        settings.customWorkspaceOrder = ["A", "2"]
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(Configuration().appShortcuts == AppShortcut.functionKeys)
        #expect(decoded.appShortcutBindings(for: []) == ["z": 0, "x": 1, ",": 3, "f8": 4])
    }

    @Test("Only valid plain keys normalize; navigation and modifier shortcuts remain reserved")
    func normalization() {
        for (raw, expected) in [(" Z ", "z"), ("f12", "f12"), ("F1", "f1"), (",", ","), ("/", "/"), ("\\", "\\")] {
            #expect(AppShortcut.normalize(raw) == expected)
        }
        for raw in ["", " ", "Tab", "Esc", "Enter", "Space", "F13", "F01", "ZX", "⌘Z", "中", "🙂"] {
            #expect(AppShortcut.normalize(raw) == nil)
        }
    }

    @Test("ZXCV and punctuation select stable app slots only while the switcher is active")
    func bottomRow() {
        var settings = Configuration(); settings.appShortcuts = AppShortcut.bottomRow
        let bindings = settings.appShortcutBindings(for: [])
        var router = KeyboardRouter()
        for (index, key) in AppShortcut.bottomRow.prefix(10).enumerated() {
            let decision = router.keyDown(6, characters: key.uppercased(), isActive: true, appShortcuts: bindings)
            #expect(decision == KeyDecision(consume: true, action: .app(index)))
            let released = router.keyUp(6)
            #expect(released)
        }
        #expect(router.keyDown(6, characters: "z", isActive: false, appShortcuts: bindings).consume == false)
    }

    @Test("Unbound F1 and F2 pass down and up to screenshot tools without dismissing the overlay")
    func screenshotKeys() {
        var settings = Configuration(); settings.appShortcuts = AppShortcut.bottomRow
        var router = KeyboardRouter()
        for code: Int64 in [122, 120] {
            #expect(router.keyDown(code, isActive: true, appShortcuts: settings.appShortcutBindings(for: [])) == KeyDecision(consume: false, action: .none))
            let released = router.keyUp(code)
            #expect(!released)
        }
        settings.appShortcuts = ["f2"]
        #expect(router.keyDown(120, isActive: true, appShortcuts: settings.appShortcutBindings(for: [])).action == .app(0))
        let released = router.keyUp(120)
        #expect(released)
    }

    @Test("Workspace keys keep precedence, including empty workspaces and custom workspace keys")
    func workspaceConflict() {
        var settings = Configuration(); settings.appShortcuts = AppShortcut.bottomRow
        settings.styles["1"] = WorkspaceStyle(shortcut: "z")
        let workspaces = [Workspace(name: "B", monitorID: 1), Workspace(name: "1", monitorID: 1)]
        let bindings = settings.appShortcutBindings(for: workspaces)
        #expect(bindings["b"] == nil)
        #expect(bindings["z"] == nil)
        #expect(bindings["n"] == 5)
        var router = KeyboardRouter()
        #expect(router.keyDown(11, characters: "b", isActive: true, appShortcuts: bindings).action == .workspace("b"))
        #expect(router.keyDown(6, characters: "z", isActive: true, appShortcuts: bindings).action == .workspace("z"))
    }

    @Test("Duplicates, invalid entries and disabled slots do not renumber subsequent apps")
    func invalidAndBlankKeys() {
        var settings = Configuration(); settings.appShortcuts = ["z", "Z", "Tab", "", "x"]
        #expect(settings.appShortcutBindings(for: []) == ["x": 4])
        settings.appShortcuts = Array(repeating: "", count: 12) + ["x"]
        #expect(settings.appShortcutBindings(for: []).isEmpty)
    }

    @Test("Custom app selection consumes key release and repeats after switching; system combinations keep working")
    func releaseAndModifiers() {
        let bindings = ["z": 0, ",": 1]
        var router = KeyboardRouter()
        #expect(router.keyDown(6, characters: "z", modifiers: .option, isActive: true, appShortcuts: bindings).action == .app(0))
        #expect(router.keyDown(6, characters: "z", isRepeat: true, isActive: false, appShortcuts: bindings) == KeyDecision(consume: true, action: .none))
        let released = router.keyUp(6)
        #expect(released)
        #expect(router.keyDown(6, characters: "z", modifiers: .command, isActive: true, appShortcuts: bindings) == KeyDecision(consume: false, action: .dismiss))
        #expect(router.keyDown(43, characters: ",", modifiers: .command, isActive: true, appShortcuts: bindings).action == .settings)
        #expect(router.keyDown(48, isActive: true, appShortcuts: bindings).action == .cycle(1))
    }
}
