import Foundation
import CoreGraphics
import Testing
@testable import AeroTabCore

@Suite("Window layout")
struct WorkspaceGeometryTests {
    let monitor = CGRect(x: -1000, y: 200, width: 1000, height: 800)
    func snapshot(visible: Bool, pid: Int32 = 40, workspace: String = "A") -> Snapshot {
        Snapshot(monitors: [], workspaces: [Workspace(name: workspace, monitorID: 2, isVisible: visible)], windows: [
            WorkspaceWindow(id: 12, appName: "Editor", bundleID: "test.editor", pid: pid, workspace: workspace)
        ])
    }

    @Test("Window positions normalize against their own monitor, including negative coordinates")
    func normalize() {
        let rect = LayoutMemory.normalizedVisibleFrame(CGRect(x: -900, y: 280, width: 500, height: 400), in: monitor)
        #expect(rect == CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
        let clipped = LayoutMemory.normalizedVisibleFrame(CGRect(x: -1100, y: 200, width: 500, height: 800), in: monitor)
        #expect(clipped == CGRect(x: 0, y: 0, width: 0.4, height: 1))
    }

    @Test("AeroSpace hideout slivers and invalid bounds are not mistaken for a desktop layout")
    func rejectHidden() {
        #expect(LayoutMemory.normalizedVisibleFrame(CGRect(x: -5, y: 200, width: 700, height: 700), in: monitor) == nil)
        #expect(LayoutMemory.normalizedVisibleFrame(.zero, in: monitor) == nil)
        #expect(LayoutMemory.normalizedVisibleFrame(CGRect(x: Double.nan, y: 0, width: 100, height: 100), in: monitor) == nil)
    }

    @Test("A hidden workspace retains its last visible layout instead of offscreen bounds")
    func remember() throws {
        var memory = LayoutMemory()
        let first = memory.update(snapshot: snapshot(visible: true), frames: [12: WindowGeometry(frame: monitor, zOrder: 3)], monitors: [2: monitor])
        let next = memory.update(snapshot: snapshot(visible: false), frames: [12: WindowGeometry(frame: CGRect(x: 9999, y: 9999, width: 400, height: 400))], monitors: [2: monitor])
        #expect(first["A"]?.placements == next["A"]?.placements)
        #expect(next["A"]?.isRemembered == true)
        #expect(next["A"]?.placements.first?.zOrder == 3)
        #expect(next["A"]?.aspectRatio == 1.25)
    }

    @Test("Unseen workspaces stay explicitly unknown; reused IDs and moved windows cannot inherit stale geometry")
    func identity() {
        var memory = LayoutMemory()
        let unseen = memory.update(snapshot: snapshot(visible: false), frames: [12: WindowGeometry(frame: monitor)], monitors: [2: monitor])
        #expect(unseen["A"]?.placements.isEmpty == true)
        #expect(unseen["A"]?.unplacedWindowIDs == [12])
        _ = memory.update(snapshot: snapshot(visible: true), frames: [12: WindowGeometry(frame: monitor)], monitors: [2: monitor])
        let moved = memory.update(snapshot: snapshot(visible: false, workspace: "B"), frames: [:], monitors: [2: monitor])
        #expect(moved["B"]?.unplacedWindowIDs == [12])
        _ = memory.update(snapshot: snapshot(visible: true), frames: [12: WindowGeometry(frame: monitor)], monitors: [2: monitor])
        let reused = memory.update(snapshot: snapshot(visible: false, pid: 99), frames: [:], monitors: [2: monitor])
        #expect(reused["A"]?.unplacedWindowIDs == [12])
    }

    @Test("Closing and reopening a window removes its cached layout")
    func prune() {
        var memory = LayoutMemory()
        _ = memory.update(snapshot: snapshot(visible: true), frames: [12: WindowGeometry(frame: monitor)], monitors: [2: monitor])
        _ = memory.update(snapshot: .empty, frames: [:], monitors: [2: monitor])
        let reopened = memory.update(snapshot: snapshot(visible: false), frames: [:], monitors: [2: monitor])
        #expect(reopened["A"]?.unplacedWindowIDs == [12])
    }

    @Test("Panel size follows occupied workspace count and remains within a small screen")
    func metrics() {
        let one = SwitcherMetrics(count: 1, availableWidth: 1920, availableHeight: 1080)
        let two = SwitcherMetrics(count: 2, availableWidth: 1920, availableHeight: 1080)
        #expect(one.width == 324)
        #expect(one.height == two.height)
        #expect(two.width < 800)
        let many = SwitcherMetrics(count: 30, availableWidth: 800, availableHeight: 600)
        #expect(many.columns == 2)
        #expect(many.width <= 736)
        #expect(many.height <= 528)
    }
}

@Suite("First launch and upgrades")
struct SetupTests {
    @Test("New installs and v1 configurations hide empty workspaces and require onboarding")
    func migration() throws {
        #expect(!Configuration().showEmptyWorkspaces)
        let old = try JSONDecoder().decode(Configuration.self, from: Data(#"{"showEmptyWorkspaces":true}"#.utf8))
        #expect(!old.showEmptyWorkspaces)
        #expect(!old.onboardingCompleted)
        #expect(old.capturePreviews)
        let current = try JSONDecoder().decode(Configuration.self, from: Data(#"{"schemaVersion":2,"showEmptyWorkspaces":true,"onboardingCompleted":true}"#.utf8))
        #expect(current.showEmptyWorkspaces)
        #expect(current.onboardingCompleted)
    }

    @Test("Permission is not enough: a connected listener is required to mark the shortcut ready")
    func readiness() {
        let missing = KeyboardReadiness(accessibility: false, listener: false)
        #expect(missing == .needsAccessibility)
        #expect(missing.needsSetup(completed: true))
        let failed = KeyboardReadiness(accessibility: true, listener: false)
        #expect(failed == .listenerFailed)
        #expect(failed.needsSetup(completed: true))
        let ready = KeyboardReadiness(accessibility: true, listener: true)
        #expect(ready.needsSetup(completed: false))
        #expect(!ready.needsSetup(completed: true))
    }
}
