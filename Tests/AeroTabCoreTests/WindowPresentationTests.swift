import Foundation
import Testing
@testable import AeroTabCore

@Suite("Window and app presentation")
struct WindowPresentationTests {
    private func snapshot(_ windows: [WorkspaceWindow]) -> Snapshot {
        Snapshot(monitors: [], workspaces: [.init(name: "A", monitorID: 1)], windows: windows)
    }
    private func window(_ id: Int, _ name: String, bundle: String? = nil) -> WorkspaceWindow {
        .init(id: id, appName: name, bundleID: bundle ?? name, pid: Int32(id), workspace: "A")
    }

    @Test("Right-hand app names and CLI order cannot override left-to-right positions")
    func spatialOrder() {
        let data = snapshot([window(1, "A Right"), window(20, "Z Left"), window(3, "M Middle")])
        let layout = WorkspaceGeometry(placements: [
            .init(id: 1, rect: CGRect(x: 0.7, y: 0, width: 0.3, height: 1), zOrder: 99),
            .init(id: 3, rect: CGRect(x: 0.35, y: 0, width: 0.3, height: 1)),
            .init(id: 20, rect: CGRect(x: 0, y: 0, width: 0.3, height: 1))
        ])
        #expect(data.orderedWindows(in: "A", layout: layout).map(\.id) == [20, 3, 1])
        #expect(data.apps(in: "A", layout: layout).map(\.name) == ["Z Left", "M Middle", "A Right"])
        var reordered = data
        reordered.windows.reverse()
        #expect(reordered.apps(in: "A", layout: layout) == data.apps(in: "A", layout: layout))
        var remembered = layout
        remembered.isRemembered = true
        #expect(data.apps(in: "A", layout: remembered) == data.apps(in: "A", layout: layout))
    }

    @Test("Same-column windows run top to bottom, identical positions use foreground order, unknown positions come last")
    func verticalAndUnknown() {
        let data = snapshot([window(1, "Unknown"), window(2, "Lower"), window(3, "Back"), window(4, "Front")])
        let layout = WorkspaceGeometry(placements: [
            .init(id: 2, rect: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)),
            .init(id: 3, rect: CGRect(x: 0, y: 0, width: 1, height: 0.5), zOrder: 1),
            .init(id: 4, rect: CGRect(x: 0, y: 0, width: 1, height: 0.5), zOrder: 2)
        ], unplacedWindowIDs: [1])
        #expect(data.orderedWindows(in: "A", layout: layout).map(\.id) == [4, 3, 2, 1])
    }

    @Test("Apps keep all windows, ordered spatially, and occupy the position of their first window")
    func groupedAppWindows() {
        let data = snapshot([window(1, "Browser", bundle: "browser"), window(2, "Editor"), window(30, "Browser", bundle: "browser")])
        let layout = WorkspaceGeometry(placements: [
            .init(id: 1, rect: CGRect(x: 0.7, y: 0, width: 0.3, height: 1)),
            .init(id: 2, rect: CGRect(x: 0.35, y: 0, width: 0.3, height: 1)),
            .init(id: 30, rect: CGRect(x: 0, y: 0, width: 0.3, height: 1))
        ])
        let apps = data.apps(in: "A", layout: layout)
        #expect(apps.map(\.name) == ["Browser", "Editor"])
        #expect(apps.first?.windows.map(\.id) == [30, 1])
    }

    @Test("Unknown-layout previews and capture planning use the same four windows while all app identities remain available")
    func unknownCaptureSubset() {
        let data = snapshot([window(1, "Z"), window(2, "Y"), window(3, "X"), window(4, "W"), window(5, "V"), window(6, "U")])
        let layout = WorkspaceGeometry(placements: [], unplacedWindowIDs: [1, 2, 3, 4, 5, 6])
        let presented = data.orderedWindows(in: "A", layout: layout)
        #expect(presented.map(\.id) == [6, 5, 4, 3, 2, 1])
        let plan = PreviewCapturePlan.requests(snapshot: data, layouts: ["A": layout], workspaceOrder: [], selectedWorkspace: "A")
        #expect(plan.map(\.window.id) == Array(presented.prefix(4)).map(\.id))
        #expect(data.apps(in: "A", layout: layout).count == 6)
    }

    @Test("The workspace inventory retains fully covered, tiny and unplaced windows, grouping only by app identity")
    func completeInventory() {
        let data = snapshot([window(1, "Back"), window(2, "Front"), window(3, "Tiny"), window(4, "Unplaced"), window(5, "Back")])
        let layout = WorkspaceGeometry(placements: [
            .init(id: 1, rect: CGRect(x: 0, y: 0, width: 1, height: 1)),
            .init(id: 2, rect: CGRect(x: 0, y: 0, width: 1, height: 1), zOrder: 1),
            .init(id: 3, rect: CGRect(x: 0.9, y: 0, width: 0.01, height: 0.01))
        ], unplacedWindowIDs: [4, 5])
        let apps = data.apps(in: "A", layout: layout)
        #expect(apps.map(\.name) == ["Front", "Back", "Tiny", "Unplaced"])
        #expect(apps.flatMap(\.windows).map(\.id).sorted() == [1, 2, 3, 4, 5])
        #expect(data.apps(in: "A").count == 4)
    }
}
