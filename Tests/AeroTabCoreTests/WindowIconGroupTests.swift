import Foundation
import Testing
@testable import AeroTabCore

@Suite("Workspace preview icon groups")
struct WindowIconGroupTests {
    private func data(_ names: [String]) -> Snapshot {
        Snapshot(monitors: [], workspaces: [.init(name: "1", monitorID: 1)], windows: names.enumerated().map {
            WorkspaceWindow(id: $0.offset + 1, appName: $0.element, bundleID: $0.element, workspace: "1")
        })
    }
    private func place(_ id: Int, _ x: Double, _ y: Double, _ w: Double, _ h: Double, z: Int = 0) -> WindowPlacement {
        WindowPlacement(id: id, rect: CGRect(x: x, y: y, width: w, height: h), zOrder: z)
    }
    private func names(_ groups: [WindowIconGroup]) -> [[String]] { groups.map { $0.windows.map(\.appName) } }

    @Test("A over B on the left and C on the right produces ABC with a line over AB only")
    func requestedLayout() {
        let snapshot = data(["C", "B", "A"])
        let layout = WorkspaceGeometry(placements: [place(1, 0.5, 0, 0.5, 1), place(2, 0, 0.5, 0.5, 0.5), place(3, 0, 0, 0.5, 0.5)])
        let groups = snapshot.windowIconGroups(in: "1", layout: layout)
        #expect(names(groups) == [["A", "B"], ["C"]])
        #expect(groups.map(\.isSubgroup) == [true, false])
        #expect(groups.flatMap(\.windows) == snapshot.orderedWindows(in: "1", layout: layout))
    }

    @Test("Side-by-side, fully overlapping and accordion windows never receive a vertical marker")
    func horizontalAndOccluded() {
        let snapshot = data(["A", "B", "C"])
        for placements in [
            [place(1, 0, 0, 0.3, 1), place(2, 0.35, 0, 0.3, 1), place(3, 0.7, 0, 0.3, 1)],
            [place(1, 0, 0, 1, 1), place(2, 0, 0, 1, 1, z: 1), place(3, 0, 0, 1, 1, z: 2)],
            [place(1, 0, 0, 1, 0.98), place(2, 0, 0.01, 1, 0.98), place(3, 0, 0.02, 1, 0.98)]
        ] {
            let groups = snapshot.windowIconGroups(in: "1", layout: WorkspaceGeometry(placements: placements))
            #expect(groups.count == 3)
            #expect(groups.allSatisfy { !$0.isSubgroup })
            #expect(Set(groups.flatMap(\.windows).map(\.appName)) == ["A", "B", "C"])
        }
    }

    @Test("Separate vertical columns receive separate markers, including small gaps and border insets")
    func multipleColumns() {
        let snapshot = data(["D", "C", "B", "A"])
        let layout = WorkspaceGeometry(placements: [
            place(4, 0, 0, 0.48, 0.48), place(3, 0.003, 0.51, 0.475, 0.49),
            place(2, 0.52, 0, 0.48, 0.48), place(1, 0.52, 0.52, 0.48, 0.48)
        ])
        #expect(names(snapshot.windowIconGroups(in: "1", layout: layout)) == [["A", "B"], ["C", "D"]])
    }

    @Test("A full-width window over two side-by-side windows is not mislabeled as one vertical column")
    func spanningWindow() {
        let snapshot = data(["A", "B", "C"])
        let layout = WorkspaceGeometry(placements: [place(1, 0, 0, 1, 0.5), place(2, 0, 0.5, 0.5, 0.5), place(3, 0.5, 0.5, 0.5, 0.5)])
        #expect(names(snapshot.windowIconGroups(in: "1", layout: layout)) == [["A"], ["B", "C"]])
        #expect(snapshot.windowIconLayout(in: "1", layout: layout).rootAxis == .vertical)
    }

    @Test("Unknown geometry keeps the complete inventory and never invents a vertical group")
    func unknownGeometry() {
        let snapshot = data(["C", "B", "A"])
        #expect(names(snapshot.windowIconGroups(in: "1")) == [["A"], ["B"], ["C"]])
        let partial = WorkspaceGeometry(placements: [place(1, 0, 0, 0.5, 0.5)], unplacedWindowIDs: [2, 3])
        #expect(names(snapshot.windowIconGroups(in: "1", layout: partial)) == [["C"], ["A"], ["B"]])
    }

    @Test("Multiple windows of one app retain separate icons and vertical groups in both columns")
    func repeatedApplication() {
        let snapshot = data(["A", "B", "A", "C"])
        let layout = WorkspaceGeometry(placements: [
            place(1, 0, 0, 0.5, 0.5), place(2, 0, 0.5, 0.5, 0.5),
            place(3, 0.5, 0, 0.5, 0.5), place(4, 0.5, 0.5, 0.5, 0.5)
        ])
        let groups = snapshot.windowIconGroups(in: "1", layout: layout)
        #expect(names(groups) == [["A", "B"], ["A", "C"]])
        #expect(groups.map(\.isSubgroup) == [true, true])
        #expect(groups.flatMap(\.windows).map(\.id) == [1, 2, 3, 4])
    }

    @Test("Two Finder windows above a full-width terminal keep two adjacent Finder icons, regardless of CLI order")
    func finderScreenshot() {
        let original = data(["Finder", "Terminal", "Finder"])
        let layout = WorkspaceGeometry(placements: [
            place(1, 0, 0, 0.5, 0.65), place(3, 0.5, 0, 0.5, 0.65), place(2, 0, 0.65, 1, 0.35)
        ])
        for windows in [original.windows, Array(original.windows.reversed())] {
            var snapshot = original
            snapshot.windows = windows
            let groups = snapshot.windowIconGroups(in: "1", layout: layout)
            #expect(names(groups) == [["Finder", "Finder"], ["Terminal"]])
            #expect(groups.flatMap(\.windows).map(\.id) == [1, 3, 2])
            #expect(groups.map(\.isSubgroup) == [true, false])
            #expect(snapshot.windowIconLayout(in: "1", layout: layout).rootAxis == .vertical)
            // App shortcuts still represent apps, while preview icons represent windows.
            #expect(snapshot.apps(in: "1", layout: layout).map(\.name) == ["Finder", "Terminal"])
        }
    }

    @Test("A simple vertical root uses its arrow without inventing a subgroup; window titles and IDs remain distinct")
    func sameAppColumn() {
        var snapshot = data(["Finder", "Finder"])
        snapshot.windows[0].title = "Downloads"
        snapshot.windows[1].title = "Projects"
        let layout = WorkspaceGeometry(placements: [place(1, 0, 0, 1, 0.5), place(2, 0, 0.5, 1, 0.5)])
        let groups = snapshot.windowIconGroups(in: "1", layout: layout)
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { !$0.isSubgroup })
        #expect(snapshot.windowIconLayout(in: "1", layout: layout).rootAxis == .vertical)
        #expect(groups.flatMap(\.windows).map(\.id) == [1, 2])
        #expect(groups.flatMap(\.windows).map(\.title) == ["Downloads", "Projects"])
    }

    @Test("Covered, tiny, and unknown same-app windows all retain distinct icons")
    func repeatedOccludedAndUnknownWindows() {
        var snapshot = data(Array(repeating: "Finder", count: 13))
        snapshot.windows.append(.init(id: 14, appName: "Finder", bundleID: "Finder", workspace: "other"))
        let known = WorkspaceGeometry(placements: [
            place(1, 0, 0, 1, 1), place(2, 0, 0, 1, 1, z: 1), place(3, 0.9, 0, 0.01, 0.01)
        ], unplacedWindowIDs: Array(4...13))
        for layout: WorkspaceGeometry? in [nil, known] {
            let groups = snapshot.windowIconGroups(in: "1", layout: layout)
            #expect(groups.flatMap(\.windows).count == 13)
            #expect(groups.flatMap(\.windows).map(\.id).sorted() == Array(1...13))
            #expect(groups.allSatisfy { !$0.isSubgroup })
        }
    }

    @Test("Every floating window of the same app keeps its own dotted icon after the tiled window")
    func repeatedFloatingWindows() {
        var snapshot = data(["Finder", "Finder", "Finder"])
        snapshot.windows[0].layoutKind = "floating"
        snapshot.windows[2].layoutKind = "floating"
        let layout = WorkspaceGeometry(placements: [place(1, 0, 0, 0.5, 0.5), place(2, 0.5, 0, 0.5, 1),
                                                     place(3, 0, 0.5, 0.5, 0.5)])
        let groups = snapshot.windowIconGroups(in: "1", layout: layout)
        #expect(groups.flatMap(\.windows).map(\.id) == [2, 1, 3])
        #expect(groups.flatMap(\.windows).map(\.isFloating) == [false, true, true])
        #expect(groups.allSatisfy { !$0.isSubgroup })
    }
}
