import Foundation
import Testing
@testable import AeroTabCore

@Suite("Bounded preview capture")
struct PreviewCapturePlanTests {
    @Test("Retina thumbnails fit their display bounds and keep tall and wide source ratios")
    func resolution() {
        let request = PreviewCaptureRequest(window: .init(id: 1, appName: "App", bundleID: "app", workspace: "1"),
                                            bounds: CGSize(width: 276, height: 156))
        for size in [CGSize(width: 3840, height: 2160), CGSize(width: 1200, height: 2400),
                     CGSize(width: 8000, height: 500), CGSize(width: 100, height: 100)] {
            let pixels = request.pixelSize(for: size)
            #expect(pixels.width <= 512 && pixels.height <= 312)
            #expect(pixels.width >= 1 && pixels.height >= 1)
            #expect(abs(pixels.width / pixels.height - size.width / size.height) <= 0.04)
            #expect(pixels.width * pixels.height < 720 * 720)
        }
        #expect(request.pixelSize(for: .zero) == CGSize(width: 256, height: 160))
    }

    @Test("Capture selected workspace first, skip unseen unknown-layout overflow and size tiled windows individually")
    func plan() {
        let windows = (1...8).map { WorkspaceWindow(id: $0, appName: "App", bundleID: "app", pid: 42,
                                                   workspace: $0 <= 6 ? "A" : "B") }
        let snapshot = Snapshot(monitors: [], workspaces: [.init(name: "A", monitorID: 1), .init(name: "B", monitorID: 2)], windows: windows)
        let layouts = [
            "A": WorkspaceGeometry(placements: [], unplacedWindowIDs: Array(1...6)),
            "B": WorkspaceGeometry(placements: [.init(id: 7, rect: CGRect(x: 0, y: 0, width: 0.5, height: 1)),
                                                 .init(id: 8, rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))])
        ]
        let plan = PreviewCapturePlan.requests(snapshot: snapshot, layouts: layouts, workspaceOrder: ["A", "B"], selectedWorkspace: "B")
        #expect(plan.map(\.window.id) == [7, 8, 1, 2, 3, 4])
        #expect(plan.first?.window.pid == 42)
        #expect(plan.first!.bounds.width <= 138)
        #expect(plan.first!.pixelSize(for: CGSize(width: 1200, height: 1600)).width <= 276)
    }

    @Test("Partial-layout count badges do not cause captures for windows with no visible surface")
    func partialLayout() {
        let snapshot = Snapshot(monitors: [], workspaces: [.init(name: "A", monitorID: 1)], windows: [
            .init(id: 1, appName: "Notes", bundleID: "notes", workspace: "A"),
            .init(id: 2, appName: "Notes", bundleID: "notes", workspace: "A")
        ])
        let layouts = ["A": WorkspaceGeometry(placements: [.init(id: 1, rect: CGRect(x: 0, y: 0, width: 1, height: 1))], unplacedWindowIDs: [2])]
        let plan = PreviewCapturePlan.requests(snapshot: snapshot, layouts: layouts, workspaceOrder: [], selectedWorkspace: "A")
        #expect(plan.map(\.window.id) == [1])
    }
}
