import Foundation
import CoreGraphics

public struct WindowGeometry: Equatable, Sendable {
    public var frame: CGRect
    /// Larger values are nearer the front.
    public var zOrder: Int
    public init(frame: CGRect, zOrder: Int = 0) { self.frame = frame; self.zOrder = zOrder }
}

public struct WindowPlacement: Identifiable, Equatable, Sendable {
    public var id: Int
    /// Top-left origin; fractions of the workspace's display bounds.
    public var rect: CGRect
    public var zOrder: Int
    public init(id: Int, rect: CGRect, zOrder: Int = 0) { self.id = id; self.rect = rect; self.zOrder = zOrder }
}

public struct WorkspaceGeometry: Equatable, Sendable {
    public var placements: [WindowPlacement]
    public var unplacedWindowIDs: [Int]
    public var isRemembered: Bool
    public var aspectRatio: Double

    public init(placements: [WindowPlacement], unplacedWindowIDs: [Int] = [], isRemembered: Bool = false, aspectRatio: Double = 16.0 / 10) {
        self.placements = placements; self.unplacedWindowIDs = unplacedWindowIDs
        self.isRemembered = isRemembered; self.aspectRatio = aspectRatio
    }
}

/// AeroSpace hides windows by moving them offscreen. Remember geometry only when
/// that workspace is visible, never treating a hideout corner as the real layout.
public struct LayoutMemory: Sendable {
    private struct Key: Hashable, Sendable { var id: Int; var pid: Int32; var workspace: String }
    private var known: [Key: WindowPlacement] = [:]
    public init() {}

    public mutating func update(snapshot: Snapshot, frames: [Int: WindowGeometry], monitors: [Int: CGRect]) -> [String: WorkspaceGeometry] {
        let liveKeys = Set(snapshot.windows.map { Key(id: $0.id, pid: $0.pid, workspace: $0.workspace) })
        known = known.filter { liveKeys.contains($0.key) }
        var result: [String: WorkspaceGeometry] = [:]
        for workspace in snapshot.workspaces {
            let windows = snapshot.windows.filter { $0.workspace == workspace.name }
            let display = monitors[workspace.monitorID]
            var placements: [WindowPlacement] = [], unknown: [Int] = []
            for window in windows {
                let key = Key(id: window.id, pid: window.pid, workspace: workspace.name)
                if workspace.isVisible, let display, let info = frames[window.id],
                   let rect = Self.normalizedVisibleFrame(info.frame, in: display) {
                    known[key] = WindowPlacement(id: window.id, rect: rect, zOrder: info.zOrder)
                }
                if let placement = known[key] { placements.append(placement) }
                else { unknown.append(window.id) }
            }
            result[workspace.name] = WorkspaceGeometry(
                placements: placements.sorted { $0.zOrder < $1.zOrder },
                unplacedWindowIDs: unknown, isRemembered: !workspace.isVisible,
                aspectRatio: display.map { max(0.3, min(4, $0.width / max(1, $0.height))) } ?? 1.6)
        }
        return result
    }

    public static func normalizedVisibleFrame(_ frame: CGRect, in display: CGRect) -> CGRect? {
        guard frame.width > 1, frame.height > 1, display.width > 1, display.height > 1,
              frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite else { return nil }
        let intersection = frame.intersection(display)
        guard !intersection.isNull, intersection.width > 4, intersection.height > 4,
              intersection.width * intersection.height / (frame.width * frame.height) > 0.08 else { return nil }
        return CGRect(x: (intersection.minX - display.minX) / display.width,
                      y: (intersection.minY - display.minY) / display.height,
                      width: intersection.width / display.width, height: intersection.height / display.height)
    }
}

/// Content-driven panel sizing, shared by the native window and screenshot renderer.
public struct SwitcherMetrics: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var columns: Int
    public var cardWidth: Double
    public static let cardHeight: Double = 196
    public static let gap: Double = 12

    public init(count: Int, availableWidth: Double, availableHeight: Double, extraHeight: Double = 0) {
        let count = max(1, count)
        let maxWidth = max(280, min(1120, availableWidth - 64))
        columns = max(1, min(count, 4, Int((maxWidth - 32 + Self.gap) / (248 + Self.gap))))
        cardWidth = min(292, (maxWidth - 32 - Double(columns - 1) * Self.gap) / Double(columns))
        width = Double(columns) * cardWidth + Double(columns - 1) * Self.gap + 32
        let rows = Int(ceil(Double(count) / Double(columns)))
        height = min(Double(rows) * Self.cardHeight + Double(rows - 1) * Self.gap + 106 + extraHeight, max(220, availableHeight - 72))
    }
}
