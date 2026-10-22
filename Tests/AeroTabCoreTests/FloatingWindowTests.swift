import Foundation
import Testing
@testable import AeroTabCore

@Suite("Floating window presentation")
struct FloatingWindowTests {
    private func snapshot(_ names: [String], floating: Set<Int>) -> Snapshot {
        Snapshot(monitors: [], workspaces: [.init(name: "1", monitorID: 1)], windows: names.enumerated().map {
            WorkspaceWindow(id: $0.offset + 1, appName: $0.element, bundleID: $0.element, workspace: "1",
                            layoutKind: floating.contains($0.offset + 1) ? "floating" : "h_tiles")
        })
    }
    private func place(_ id: Int, _ x: Double, _ y: Double = 0, _ w: Double = 0.4, _ h: Double = 0.5) -> WindowPlacement {
        WindowPlacement(id: id, rect: CGRect(x: x, y: y, width: w, height: h))
    }

    @Test("The actual CLI floating value survives decoding and round-trip; old or unknown layouts do not invent it")
    func layoutDecoding() throws {
        for kind: String? in ["floating", "h_tiles", "v_tiles", "h_accordion", "v_accordion", "future_layout", nil] {
            var payload: [String: Any] = ["window-id": 42, "app-name": "App", "app-bundle-id": "app", "app-pid": 1,
                                          "workspace": "1", "window-title": "Example"]
            if let kind { payload["window-layout"] = kind }
            let window = try JSONDecoder().decode(WorkspaceWindow.self, from: JSONSerialization.data(withJSONObject: payload))
            #expect(window.layoutKind == kind)
            #expect(window.isFloating == (kind == "floating"))
            #expect(try JSONDecoder().decode(WorkspaceWindow.self, from: JSONEncoder().encode(window)) == window)
        }
    }

    @Test("Requested ABCD layout keeps the line over AB, with floating D last even when its screen position is leftmost")
    func requestedLayout() {
        let data = snapshot(["D", "C", "B", "A"], floating: [1])
        let layout = WorkspaceGeometry(placements: [place(1, 0), place(2, 0.6, 0, 0.4, 1),
                                                     place(3, 0.1, 0.5), place(4, 0.1)])
        let groups = data.windowIconGroups(in: "1", layout: layout)
        #expect(groups.map { $0.windows.map(\.appName) } == [["A", "B"], ["C"], ["D"]])
        #expect(groups.map(\.isSubgroup) == [true, false, false])
        #expect(groups.flatMap(\.windows).map(\.isFloating) == [false, false, false, true])
        #expect(groups.flatMap(\.windows) == data.orderedWindows(in: "1", layout: layout))
        #expect(data.orderedWindows(in: "1", layout: layout).map(\.id) == [4, 3, 2, 1])
    }

    @Test("Floating windows never join vertical groups, including floating windows with perfectly aligned bounds")
    func floatingDoesNotJoinColumns() {
        let layout = WorkspaceGeometry(placements: [place(1, 0), place(2, 0, 0.5)])
        for floating: Set<Int> in [[2], [1, 2]] {
            let groups = snapshot(["A", "B"], floating: floating).windowIconGroups(in: "1", layout: layout)
            #expect(groups.count == 2)
            #expect(groups.allSatisfy { !$0.isSubgroup })
        }
    }

    @Test("Floating status and tiled-first order work before positions are recorded, even with partial geometry")
    func unknownGeometry() {
        let data = snapshot(["A Float", "Z Tiled", "B Float"], floating: [1, 3])
        for layout: WorkspaceGeometry? in [nil, WorkspaceGeometry(placements: [place(1, 0)], unplacedWindowIDs: [2, 3])] {
            let apps = data.apps(in: "1", layout: layout)
            #expect(apps.map(\.name) == ["Z Tiled", "A Float", "B Float"])
            #expect(apps.map(\.hasFloatingWindows) == [false, true, true])
            #expect(data.windowIconGroups(in: "1", layout: layout).allSatisfy { !$0.isSubgroup })
        }
    }

    @Test("Multiple floating apps retain spatial order within the final section")
    func floatingOrder() {
        let data = snapshot(["Right", "Tiled", "Lower", "Upper"], floating: [1, 3, 4])
        let layout = WorkspaceGeometry(placements: [place(1, 0.6), place(2, 0.9), place(3, 0, 0.5), place(4, 0)])
        #expect(data.apps(in: "1", layout: layout).map(\.name) == ["Tiled", "Upper", "Lower", "Right"])
    }

    @Test("Mixed apps keep grouped shortcuts while preview icons mark only the individual floating windows")
    func mixedApp() {
        let data = snapshot(["Mixed", "Tiled", "Mixed", "Float"], floating: [3, 4])
        let layout = WorkspaceGeometry(placements: [place(1, 0), place(2, 0.8), place(3, 0.6), place(4, 0.1)])
        let apps = data.apps(in: "1", layout: layout)
        #expect(apps.map(\.name) == ["Tiled", "Float", "Mixed"])
        #expect(apps.map(\.hasFloatingWindows) == [false, true, true])
        #expect(apps.last?.windows.map(\.id) == [1, 3])
        #expect(apps.last?.floatingWindowCount == 1)
        #expect(apps.last?.iconWindow?.id == 3)
        let icons = data.windowIconGroups(in: "1", layout: layout).flatMap(\.windows)
        #expect(icons.map(\.appName) == ["Mixed", "Tiled", "Float", "Mixed"])
        #expect(icons.map(\.id) == [1, 2, 4, 3])
        #expect(icons.map(\.isFloating) == [false, false, true, true])
    }

    @Test("Changing floating mode updates sorting and markers without requiring different geometry")
    func modeChange() {
        var data = snapshot(["A", "B"], floating: [1])
        let layout = WorkspaceGeometry(placements: [place(1, 0), place(2, 0, 0.5)])
        #expect(data.apps(in: "1", layout: layout).map(\.name) == ["B", "A"])
        data.windows[0].layoutKind = "v_tiles"
        let groups = data.windowIconGroups(in: "1", layout: layout)
        #expect(groups.map { $0.windows.map(\.appName) } == [["A"], ["B"]])
        #expect(groups.allSatisfy { !$0.isSubgroup })
        #expect(data.windowIconLayout(in: "1", layout: layout).rootAxis == .vertical)
        #expect(groups.flatMap(\.windows).allSatisfy { !$0.isFloating })
    }
}
