import Foundation
import Testing
@testable import AeroTabCore

@Suite("Workspace layout direction and subgroups")
struct WorkspaceIconLayoutTests {
    private func data(_ root: String, count: Int = 4) -> Snapshot {
        Snapshot(monitors: [], workspaces: [.init(name: "T", monitorID: 1, rootLayoutKind: root)],
                 windows: (1...count).map { .init(id: $0, appName: "Finder", bundleID: "com.apple.finder", workspace: "T") })
    }
    private func place(_ id: Int, _ x: Double, _ y: Double, _ width: Double = 0.5, _ height: Double = 0.5) -> WindowPlacement {
        .init(id: id, rect: CGRect(x: x, y: y, width: width, height: height))
    }
    private var grid: WorkspaceGeometry {
        .init(placements: [place(1, 0, 0), place(2, 0.5, 0), place(3, 0, 0.5), place(4, 0.5, 0.5)])
    }

    @Test("Root layout round-trips all actual CLI values and accepts legacy or future data")
    func decodeRoot() throws {
        for kind: String? in ["h_tiles", "v_tiles", "h_accordion", "v_accordion", "future_layout", nil] {
            var payload: [String: Any] = ["workspace": "T", "monitor-id": 1, "workspace-is-visible": true, "workspace-is-focused": true]
            if let kind { payload["workspace-root-container-layout"] = kind }
            let workspace = try JSONDecoder().decode(Workspace.self, from: JSONSerialization.data(withJSONObject: payload))
            #expect(workspace.rootLayoutKind == kind)
            #expect(workspace.rootAxis == LayoutAxis(layoutKind: kind))
            #expect(try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace)) == workspace)
        }
    }

    @Test("Identical grid geometry follows the reported root: columns for horizontal, rows for vertical")
    func rootResolvesGrid() {
        for root in ["h_tiles", "v_tiles", "h_accordion", "v_accordion"] {
            let snapshot = data(root)
            let result = snapshot.windowIconLayout(in: "T", layout: grid)
            let horizontal = root.hasPrefix("h_")
            #expect(result.rootAxis == (horizontal ? .horizontal : .vertical))
            #expect(result.groups.map { $0.windows.map(\.id) } == (horizontal ? [[1, 3], [2, 4]] : [[1, 2], [3, 4]]))
            #expect(result.groups.map(\.subgroupAxis) == (horizontal ? [.vertical, .vertical] : [.horizontal, .horizontal]))
            #expect(result.groups.flatMap(\.windows) == snapshot.orderedWindows(in: "T", layout: grid))
            var remembered = grid
            remembered.isRemembered = true
            #expect(snapshot.windowIconLayout(in: "T", layout: remembered) == result)
        }
    }

    @Test("Unknown or partial geometry preserves the real root arrow and every icon without inventing groups")
    func unknownGeometry() {
        let snapshot = data("v_tiles")
        for layout: WorkspaceGeometry? in [nil, .init(placements: [place(1, 0, 0), place(2, 0.5, 0)], unplacedWindowIDs: [3, 4])] {
            let result = snapshot.windowIconLayout(in: "T", layout: layout)
            #expect(result.rootAxis == .vertical)
            #expect(result.groups.allSatisfy { !$0.isSubgroup })
            #expect(result.groups.flatMap(\.windows).count == 4)
        }
        #expect(data("future_layout").windowIconLayout(in: "T", layout: grid).rootAxis == nil)
        #expect(data("future_layout").windowIconLayout(in: "T", layout: grid).groups.allSatisfy { !$0.isSubgroup })
    }

    @Test("Floating windows cannot determine the root or join a subgroup, even when they cover the tiled area")
    func floatingAndEmpty() {
        var snapshot = data("v_tiles")
        snapshot.windows.append(.init(id: 5, appName: "Finder", bundleID: "com.apple.finder", workspace: "T", layoutKind: "floating"))
        var layout = grid
        layout.placements.append(place(5, 0, 0, 1, 1))
        let result = snapshot.windowIconLayout(in: "T", layout: layout)
        #expect(result.rootAxis == .vertical)
        #expect(result.groups.map { $0.windows.map(\.id) } == [[1, 2], [3, 4], [5]])
        #expect(result.groups.map(\.isSubgroup) == [true, true, false])
        for index in snapshot.windows.indices { snapshot.windows[index].layoutKind = "floating" }
        #expect(snapshot.windowIconLayout(in: "T", layout: layout).rootAxis == nil)
        #expect(snapshot.windowIconGroups(in: "T", layout: layout).allSatisfy { !$0.isSubgroup })
        snapshot.windows.removeAll()
        #expect(snapshot.windowIconLayout(in: "T", layout: layout).rootAxis == nil)
        #expect(snapshot.windowIconGroups(in: "T", layout: layout).isEmpty)
    }

    @Test("A plain vertical layout needs only its root arrow; overlapping accordion windows never invent a subgroup")
    func directChildrenAndOverlap() {
        let snapshot = data("v_tiles", count: 3)
        let rows = WorkspaceGeometry(placements: [place(1, 0, 0, 1, 0.3), place(2, 0, 0.35, 1, 0.3), place(3, 0, 0.7, 1, 0.3)])
        let result = snapshot.windowIconLayout(in: "T", layout: rows)
        #expect(result.rootAxis == .vertical)
        #expect(result.groups.allSatisfy { !$0.isSubgroup })
        let overlap = WorkspaceGeometry(placements: [place(1, 0, 0, 1, 1), place(2, 0, 0.01, 1, 0.98), place(3, 0, 0.02, 1, 0.98)])
        let accordion = data("h_accordion", count: 3).windowIconLayout(in: "T", layout: overlap)
        #expect(accordion.rootAxis == .horizontal)
        #expect(accordion.groups.allSatisfy { !$0.isSubgroup })
    }

    @Test("Deeper nesting marks the outer child group once and keeps its full internal reading order")
    func nestedGroup() {
        let snapshot = data("h_tiles")
        // Left child: A over B/C; right child: D occupies the full height.
        let layout = WorkspaceGeometry(placements: [place(1, 0, 0, 0.6, 0.5), place(2, 0, 0.5, 0.3, 0.5),
                                                     place(3, 0.3, 0.5, 0.3, 0.5), place(4, 0.6, 0, 0.4, 1)])
        let result = snapshot.windowIconLayout(in: "T", layout: layout)
        #expect(result.rootAxis == .horizontal)
        #expect(result.groups.map { $0.windows.map(\.id) } == [[1, 2, 3], [4]])
        #expect(result.groups.map(\.isSubgroup) == [true, false])
    }
}
