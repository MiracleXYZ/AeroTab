import Foundation

/// One immediate child of the outer layout; a line marks a multi-window subgroup.
public struct WindowIconGroup: Equatable, Sendable {
    public var windows: [WorkspaceWindow]
    public var subgroupAxis: LayoutAxis?
    public var isSubgroup: Bool { subgroupAxis != nil && windows.count > 1 }
    public init(windows: [WorkspaceWindow], subgroupAxis: LayoutAxis? = nil) {
        self.windows = windows; self.subgroupAxis = subgroupAxis
    }
}

public struct WorkspaceIconLayout: Equatable, Sendable {
    public var rootAxis: LayoutAxis?
    public var groups: [WindowIconGroup]
}

extension Snapshot {
    public func windowIconLayout(in workspace: String, layout: WorkspaceGeometry? = nil) -> WorkspaceIconLayout {
        let ordered = orderedWindows(in: workspace, layout: layout)
        let singles = ordered.map { WindowIconGroup(windows: [$0]) }
        let tiled = ordered.filter { !$0.isFloating }
        guard !tiled.isEmpty else { return WorkspaceIconLayout(rootAxis: nil, groups: singles) }
        let placements = Dictionary((layout?.placements ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = tiled.filter { placements[$0.id] != nil }
        let workspaceInfo = workspaces.first { $0.name == workspace }
        var axis = workspaceInfo?.rootAxis
        // Legacy/synthetic snapshots may lack the CLI field. Never override a reported root.
        if workspaceInfo?.rootLayoutKind == nil, known.count == tiled.count, known.count > 1 {
            axis = [LayoutAxis.horizontal, .vertical].first {
                SpatialWindowOrder.partitions(known, placements: placements, axis: $0).count > 1
            }
        }
        // Unknown positions cannot establish subgroup membership. The CLI arrow remains valid.
        guard let axis, known.count == tiled.count, known.count > 1 else {
            return WorkspaceIconLayout(rootAxis: axis, groups: singles)
        }
        let children = SpatialWindowOrder.partitions(tiled, placements: placements, axis: axis)
        guard children.count > 1 else { return WorkspaceIconLayout(rootAxis: axis, groups: singles) }
        let groups = children.flatMap { child -> [WindowIconGroup] in
            // A line denotes a child group, not a direction. Its first internal split is
            // perpendicular to the outer split; overlapping/accordion windows stay ungrouped.
            let internalGroups = SpatialWindowOrder.partitions(child, placements: placements, axis: axis.opposite)
            if child.count > 1 && internalGroups.count > 1 {
                return [WindowIconGroup(windows: child, subgroupAxis: axis.opposite)]
            }
            return child.map { WindowIconGroup(windows: [$0]) }
        } + ordered.filter(\.isFloating).map { WindowIconGroup(windows: [$0]) }
        return WorkspaceIconLayout(rootAxis: axis, groups: groups)
    }

    public func windowIconGroups(in workspace: String, layout: WorkspaceGeometry? = nil) -> [WindowIconGroup] {
        windowIconLayout(in: workspace, layout: layout).groups
    }
}
