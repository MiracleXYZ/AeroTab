import Foundation
import Testing
@testable import AeroTabCore

@Suite("Keyboard interaction")
struct KeyboardTests {
    @Test("Option-Tab opens on current workspace; unmodified letters select directly")
    func stickySequence() {
        var router = KeyboardRouter()
        let open = router.keyDown(48, modifiers: .option, isActive: false)
        #expect(open == KeyDecision(consume: true, action: .show(advance: 0)))
        let up = router.keyUp(48)
        #expect(up)
        let letter = router.keyDown(0, characters: "A", isActive: true)
        #expect(letter == KeyDecision(consume: true, action: .workspace("a")))
    }

    @Test("Tab and Shift-Tab navigate, space and return commit")
    func navigation() {
        var router = KeyboardRouter()
        let next = router.keyDown(48, isActive: true)
        let previous = router.keyDown(48, modifiers: .shift, isActive: true)
        let space = router.keyDown(49, isActive: true)
        let enter = router.keyDown(36, isActive: true)
        #expect(next.action == .cycle(1))
        #expect(previous.action == .cycle(-1))
        #expect(space.action == .confirm)
        #expect(enter.action == .confirm)
    }

    @Test("A held shortcut never types repeated letters into the newly focused app")
    func noKeyLeakAfterCommit() {
        var router = KeyboardRouter()
        _ = router.keyDown(0, characters: "a", isActive: true)
        let repeatAfterClose = router.keyDown(0, characters: "a", isRepeat: true, isActive: false)
        #expect(repeatAfterClose == KeyDecision(consume: true, action: .none))
        let up = router.keyUp(0)
        #expect(up)
        let laterTyping = router.keyDown(0, characters: "a", isActive: false)
        #expect(!laterTyping.consume)
    }

    @Test("Escape is consumed, while unrelated system shortcuts cancel and pass through")
    func escapeAndSystemShortcuts() {
        var router = KeyboardRouter()
        let escape = router.keyDown(53, isActive: true)
        let commandTab = router.keyDown(48, modifiers: .command, isActive: true)
        #expect(escape == KeyDecision(consume: true, action: .dismiss))
        #expect(commandTab == KeyDecision(consume: false, action: .dismiss))
        let idleTab = router.keyDown(48, isActive: false)
        #expect(!idleTab.consume)
    }

    @Test("Disabling the hotkey preserves normal Option-Tab, and hold mode is explicit")
    func optionalModes() {
        var router = KeyboardRouter()
        let disabled = router.keyDown(48, modifiers: .option, isActive: false, captureOptionTab: false)
        #expect(!disabled.consume)
        let hold = router.keyDown(48, modifiers: .option, isActive: false, holdMode: true)
        #expect(hold.action == .show(advance: 1))
    }

    @Test("Command-comma opens settings only inside the switcher and never leaks into the previous app")
    func settingsShortcut() {
        var router = KeyboardRouter()
        let idle = router.keyDown(43, characters: ",", modifiers: .command, isActive: false)
        #expect(!idle.consume)
        let active = router.keyDown(43, characters: ",", modifiers: .command, isActive: true)
        #expect(active == KeyDecision(consume: true, action: .settings))
        let repeating = router.keyDown(43, characters: ",", modifiers: .command, isRepeat: true, isActive: false)
        #expect(repeating == KeyDecision(consume: true, action: .none))
        let up = router.keyUp(43)
        #expect(up)
    }

    @Test("Settings uses the keyboard layout's comma and does not consume other Command shortcuts")
    func settingsLayout() {
        var router = KeyboardRouter()
        let alternateLayout = router.keyDown(99, characters: ",", modifiers: .command, isActive: true)
        #expect(alternateLayout.action == .settings)
        let differentCharacter = router.keyDown(43, characters: "w", modifiers: .command, isActive: true)
        #expect(differentCharacter == KeyDecision(consume: false, action: .dismiss))
        let extraModifier = router.keyDown(43, characters: ",", modifiers: [.command, .option], isActive: true)
        #expect(extraModifier == KeyDecision(consume: false, action: .dismiss))
    }
}

@Suite("Application entry points")
struct AppDestinationTests {
    @Test("Settings has a separate deep link that works without the menu bar")
    func settingsLink() throws {
        #expect(AppDestination(url: try #require(URL(string: "aerotab://settings"))) == .settings)
        #expect(AppDestination(url: try #require(URL(string: "aerotab://show"))) == .switcher)
        #expect(AppDestination(url: try #require(URL(string: "AEROTAB://SETTINGS/"))) == .settings)
    }

    @Test("External URLs cannot supply commands, workspace arguments, or unrelated actions")
    func restrictedRoutes() throws {
        for address in ["https://settings", "aerotab://quit", "aerotab://settings/extra",
                        "aerotab://show?workspace=A", "aerotab://settings#extra",
                        "aerotab://user@settings", "aerotab://settings:42"] {
            #expect(AppDestination(url: try #require(URL(string: address))) == nil)
        }
    }
}

@Suite("Workspace switching")
struct SelectionTests {
    let workspaces = [Workspace(name: "1", monitorID: 3, isVisible: true, isFocused: true),
                      Workspace(name: "2", monitorID: 3), Workspace(name: "A", monitorID: 2, isVisible: true)]

    @Test("Sticky invocation starts on the current workspace")
    func startsOnCurrent() {
        var selection = Selection()
        selection.begin(workspaces: workspaces, focused: "1", order: .recent, advance: 0)
        #expect(selection.selected == "1")
        selection.cycle(1)
        #expect(selection.selected == "2")
        selection.cycle(-2)
        #expect(selection.selected == "A")
    }

    @Test("MRU follows external focus, and cycling order is frozen until dismissal")
    func recentOrder() {
        var selection = Selection()
        selection.recordFocus("A"); selection.recordFocus("2")
        selection.begin(workspaces: workspaces, focused: "1", order: .recent, advance: 1)
        #expect(selection.selected == "2")
        selection.recordFocus("A")
        selection.cycle(1)
        #expect(selection.selected == "A")
        selection.end()
        selection.begin(workspaces: workspaces, focused: "2", order: .recent, advance: 1)
        #expect(selection.selected == "A")
    }

    @Test("Deleted workspaces are pruned, empty lists and large reverse steps are safe")
    func pruning() {
        var selection = Selection()
        selection.recordFocus("deleted")
        selection.begin(workspaces: workspaces, focused: nil, order: .recent, advance: -7)
        #expect(!selection.names.contains("deleted"))
        #expect(selection.selected == "A")
        selection.begin(workspaces: [], focused: "missing", order: .recent, advance: -1)
        #expect(selection.selected == nil)
    }

    @Test("All empty workspaces are hidden, including visible and focused ones")
    func visibleWorkspaces() {
        let snapshot = Snapshot(monitors: [], workspaces: workspaces + [Workspace(name: "B", monitorID: 1, isVisible: true)], windows: [
            WorkspaceWindow(id: 42, appName: "Notes", bundleID: "com.apple.Notes", workspace: "2")
        ])
        #expect(snapshot.orderedWorkspaces(showEmpty: false).map(\.name) == ["2"])
        #expect(snapshot.orderedWorkspaces(showEmpty: true).count == 4)
    }

    @Test("Apps are grouped per workspace, with all of their window targets retained")
    func appGrouping() {
        let snapshot = Snapshot(monitors: [], workspaces: workspaces, windows: [
            WorkspaceWindow(id: 30, appName: "Safari", bundleID: "com.apple.Safari", workspace: "1"),
            WorkspaceWindow(id: 10, appName: "Safari", bundleID: "com.apple.Safari", workspace: "1"),
            WorkspaceWindow(id: 20, appName: "Safari", bundleID: "com.apple.Safari", workspace: "A")
        ])
        #expect(snapshot.apps(in: "1").count == 1)
        #expect(snapshot.apps(in: "1").first?.windows.map(\.id) == [10, 30])
        #expect(snapshot.apps(in: "A").first?.windows.map(\.id) == [20])
    }
}

@Suite("Asynchronous input")
struct InvocationTests {
    @Test("Escape prevents a slow query from reopening the switcher")
    func cancelledResponse() {
        var state = Invocation()
        let old = state.begin(advance: 0, followsOptionRelease: false)
        state.enqueueCycle(2)
        state.cancel()
        let staleAfterCancel = state.markReady(generation: old)
        #expect(!staleAfterCancel)
        let current = state.begin(advance: 0, followsOptionRelease: false)
        let staleAfterReopen = state.markReady(generation: old)
        #expect(!staleAfterReopen)
        let ready = state.markReady(generation: current)
        #expect(ready)
        #expect(state.advance == 0)
    }

    @Test("Tab, letter, and confirmation can arrive before the CLI response")
    func earlyInput() {
        var state = Invocation()
        let generation = state.begin(advance: 0, followsOptionRelease: false)
        state.enqueueCycle(1); state.enqueueCycle(1); state.enqueueCycle(-1)
        state.enqueueShortcut("a"); state.requestCommit()
        let ready = state.markReady(generation: generation)
        #expect(ready)
        #expect(state.advance == 1)
        #expect(state.pendingShortcut == "a")
        #expect(state.commitWhenReady)
    }

    @Test("Release-to-commit is opt-in")
    func stickyDefault() throws {
        #expect(Configuration().releaseToCommit == false)
        let config = try JSONDecoder().decode(Configuration.self, from: Data("{}".utf8))
        #expect(!config.releaseToCommit)
    }
}

@Suite("Configuration and safe commands")
struct ConfigurationTests {
    @Test("Workspace names stay literal command arguments, even with shell syntax")
    func literalNames() {
        #expect(SwitchTarget.workspace("--next; $(touch /tmp/nope)").arguments == ["workspace", "--", "--next; $(touch /tmp/nope)"])
        #expect(SwitchTarget.window(42).arguments == ["focus", "--window-id", "42"])
    }

    @Test("Custom shortcuts handle long workspace names and reject ambiguity")
    func shortcuts() {
        var config = Configuration()
        config.styles["Research"] = WorkspaceStyle(shortcut: "r")
        let workspaces = [Workspace(name: "Research", monitorID: 1), Workspace(name: "A", monitorID: 2)]
        #expect(config.shortcuts(for: workspaces) == ["r": "Research", "a": "A"])
        config.styles["A"] = WorkspaceStyle(shortcut: "R")
        #expect(config.shortcuts(for: workspaces).isEmpty)
        #expect(config.shortcut(for: "Long name") == nil)
    }

    @Test("Styles survive roundtrip and default 1/2 colors match the note")
    func configRoundtrip() throws {
        var config = Configuration()
        config.displayMode = .perMonitor
        config.styles["A"] = WorkspaceStyle(label: "阅读", symbol: "book.closed", tint: .mint, shortcut: "a")
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
        #expect(decoded.style(for: "1").tint == .coral)
        #expect(decoded.style(for: "2").tint == .violet)
    }
}

private struct FixtureRunner: CommandRunning {
    func run(executable: String, arguments: [String]) throws -> Data {
        let json: String
        switch arguments.first {
        case "list-monitors": json = """
        [{"monitor-id":1,"monitor-name":"External Display","monitor-appkit-nsscreen-screens-id":2},
         {"monitor-id":3,"monitor-name":"Built-in Display","monitor-appkit-nsscreen-screens-id":1}]
        """
        case "list-workspaces":
            guard arguments.contains(where: { $0.contains("%{workspace-root-container-layout}") }) else {
                throw AeroSpaceError.commandFailed("Root layout must be requested in the production query")
            }
            json = """
        [{"workspace":"1","monitor-id":3,"workspace-is-visible":true,"workspace-is-focused":true,"workspace-root-container-layout":"v_tiles"},
         {"workspace":"B","monitor-id":1,"workspace-is-visible":true,"workspace-is-focused":false,"workspace-root-container-layout":"h_accordion"}]
        """
        case "list-windows":
            guard arguments.contains(where: { $0.contains("%{window-layout}") }) else {
                throw AeroSpaceError.commandFailed("Window layout must be requested in the production query")
            }
            json = #"""
        [{"window-id":42,"app-name":"Notes","app-bundle-id":"com.apple.Notes","app-pid":123,"workspace":"B","window-title":"标题 \"引号\"\n笔记","window-layout":"floating"},
         {"window-id":43,"app-name":"Finder","app-bundle-id":"com.apple.finder","app-pid":456,"workspace":"1","window-title":"Files","window-layout":"h_tiles"}]
        """#
        default: throw AeroSpaceError.commandFailed("Unexpected test command")
        }
        return Data(json.utf8)
    }
}

@Suite("AeroSpace integration")
struct ClientTests {
    @Test("Real CLI schema uses boolean flags and one-based NSScreen indices")
    func decodeSnapshot() async throws {
        let snapshot = try await AeroSpaceClient(executable: "/fixture", runner: FixtureRunner()).snapshot()
        #expect(snapshot.monitors[0].screenIndex == 2)
        #expect(snapshot.focusedWorkspace?.monitorID == 3)
        #expect(snapshot.focusedWorkspace?.rootAxis == .vertical)
        #expect(snapshot.workspaces[1].rootAxis == .horizontal)
        #expect(snapshot.workspaces.filter(\.isVisible).count == 2)
        #expect(snapshot.windows[0].workspace == "B")
        #expect(snapshot.windows[0].isFloating)
        #expect(!snapshot.windows[1].isFloating)
    }

    @Test("Missing executable returns an actionable error")
    func missingCLI() throws {
        #expect(throws: AeroSpaceError.self) { try ProcessRunner().run(executable: "/no-such-aerospace", arguments: []) }
    }

    @Test("Both output pipes drain even when they exceed pipe capacity")
    func largeOutput() throws {
        let data = try ProcessRunner().run(executable: "/usr/bin/perl", arguments: ["-e", "print STDOUT 'x' x 200000; print STDERR 'e' x 200000;"])
        #expect(data.count == 200_000)
    }

    @Test("Hung CLI is terminated with a bounded timeout")
    func timeout() throws {
        let start = Date()
        #expect(throws: AeroSpaceError.self) {
            try ProcessRunner(timeout: 0.1).run(executable: "/usr/bin/perl", arguments: ["-e", "sleep 10"])
        }
        #expect(Date().timeIntervalSince(start) < 2)
    }
}
