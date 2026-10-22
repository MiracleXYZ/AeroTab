import Foundation
import Testing
@testable import AeroTabCore

@Suite("Stable workspace order")
struct WorkspaceOrderTests {
    private let snapshot = Snapshot(monitors: [], workspaces: [
        Workspace(name: "10", monitorID: 1), Workspace(name: "B", monitorID: 1),
        Workspace(name: "A", monitorID: 3), Workspace(name: "2", monitorID: 2),
        Workspace(name: "1", monitorID: 3), Workspace(name: "Empty", monitorID: 1, isVisible: true)
    ], windows: [WorkspaceWindow(id: 1, appName: "Notes", bundleID: "notes", workspace: "A"),
                 WorkspaceWindow(id: 2, appName: "Notes", bundleID: "notes", workspace: "2")])

    @Test("Explicit order ignores monitor IDs, tolerates duplicate/stale names, and appends new names naturally")
    func ordering() {
        let order = ["gone", "B", "1", "B", "A"]
        #expect(snapshot.orderedWorkspaces(showEmpty: true, preferredOrder: order).map(\.name) == ["B", "1", "A", "2", "10", "Empty"])
        #expect(snapshot.orderedWorkspaces(showEmpty: false, preferredOrder: order).map(\.name) == ["A", "2"])
        var moved = snapshot
        moved.workspaces[1].monitorID = 99
        #expect(moved.orderedWorkspaces(showEmpty: true, preferredOrder: order).map(\.name)
                == snapshot.orderedWorkspaces(showEmpty: true, preferredOrder: order).map(\.name))
    }

    @Test("Tab follows the card order including wraparound, independent of recent focus")
    func tabOrder() {
        let ordered = snapshot.orderedWorkspaces(showEmpty: true, preferredOrder: ["B", "A", "1"])
        var selection = Selection()
        selection.recordFocus("10"); selection.recordFocus("2")
        selection.begin(workspaces: ordered, focused: "A", order: Configuration().cycleOrder, advance: 0)
        selection.cycle(1)
        #expect(selection.selected == "1")
        selection.cycle(-2)
        #expect(selection.selected == "B")
        selection.cycle(-1)
        #expect(selection.selected == "Empty")
    }

    @Test("Upgrade adopts fixed order and light background once; new explicit preferences roundtrip")
    func migration() throws {
        let upgraded = try JSONDecoder().decode(Configuration.self, from: Data(#"{"schemaVersion":2,"cycleOrder":"recent","capturePreviews":true}"#.utf8))
        #expect(upgraded.cycleOrder == .workspace)
        #expect(!upgraded.glassBackground)
        #expect(upgraded.capturePreviews)
        var custom = upgraded
        custom.workspaceOrderSource = .custom
        custom.customWorkspaceOrder = ["B", "A", "1"]
        custom.cycleOrder = .recent
        custom.glassBackground = true
        #expect(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(custom)) == custom)
    }

    @Test("Root TOML array supports multiline values, comments, literal strings and escapes")
    func readArray() throws {
        let source = #"""
        config-version = 2
        'persistent-workspaces' = [
          "1", # ] a closing bracket in a comment
          'Research #1', 'O"Brien', "\u5de5\u4f5c", "A\\B", "E\"R",
        ]
        [mode.main.binding]
        persistent-workspaces = ['wrong table']
        """#
        #expect(try PersistentWorkspaceReader.read(source) == ["1", "Research #1", "O\"Brien", "工作", "A\\B", "E\"R"])
    }

    @Test("Comments, other arrays, multiline scripts and nested tables cannot impersonate a root option")
    func skipOtherValues() throws {
        let source = #"""
        # persistent-workspaces = ['comment']
        after-startup-command = [
          '''exec-and-forget
        persistent-workspaces = ['script']
        ''',
          "ordinary string",
        ]
        persistent-workspaces = ['real', 'order']
        """#
        #expect(try PersistentWorkspaceReader.read(source) == ["real", "order"])
        #expect(try PersistentWorkspaceReader.read("[mode.main]\npersistent-workspaces=['nested']") == [])
        #expect(try PersistentWorkspaceReader.read("# no explicit option\nconfig-version=2") == [])
        #expect(try PersistentWorkspaceReader.read("persistent-workspaces=[]") == [])
        #expect(try PersistentWorkspaceReader.read("persistent-workspaces = [\r\n 'B',\r\n 'A',\r\n]\r\n") == ["B", "A"])
    }

    @Test("Malformed workspace arrays fail without returning partial order")
    func rejectInvalidArray() {
        for source in ["persistent-workspaces=['A' 'B']", "persistent-workspaces=[1]",
                       "persistent-workspaces=['A'", "persistent-workspaces='A'", "persistent-workspaces=[,'A']"] {
            #expect(throws: (any Error).self) { try PersistentWorkspaceReader.read(source) }
        }
    }

    @Test("CLI discovers the active custom config path; read errors degrade without breaking switching")
    func activeConfig() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("aerotab-order-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: file) }
        try "persistent-workspaces=['T','W','R','E']".write(to: file, atomically: true, encoding: .utf8)
        let client = AeroSpaceClient(executable: "/fixture", runner: ConfigPathRunner(path: file.path))
        let result = await client.workspaceOrder()
        #expect(result.names == ["T", "W", "R", "E"])
        #expect(result.issue == nil)
        try FileManager.default.removeItem(at: file)
        let unavailable = await client.workspaceOrder()
        #expect(unavailable.names.isEmpty)
        #expect(unavailable.issue != nil)
    }
}

private struct ConfigPathRunner: CommandRunning {
    let path: String
    func run(executable: String, arguments: [String]) throws -> Data {
        #expect(arguments == ["config", "--config-path"])
        return Data((path + "\n").utf8)
    }
}
