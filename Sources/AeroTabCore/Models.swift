import Foundation

public struct Monitor: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var name: String
    /// AeroSpace exposes a ONE-based index into NSScreen.screens, not a display ID.
    public var screenIndex: Int

    public init(id: Int, name: String, screenIndex: Int) {
        self.id = id; self.name = name; self.screenIndex = screenIndex
    }

    enum CodingKeys: String, CodingKey {
        case id = "monitor-id", name = "monitor-name"
        case screenIndex = "monitor-appkit-nsscreen-screens-id"
    }
}

public struct Workspace: Codable, Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var monitorID: Int
    public var isVisible: Bool
    public var isFocused: Bool
    public var rootLayoutKind: String?
    public var rootAxis: LayoutAxis? { LayoutAxis(layoutKind: rootLayoutKind) }

    public init(name: String, monitorID: Int, isVisible: Bool = false, isFocused: Bool = false, rootLayoutKind: String? = nil) {
        self.name = name; self.monitorID = monitorID
        self.isVisible = isVisible; self.isFocused = isFocused
        self.rootLayoutKind = rootLayoutKind
    }

    enum CodingKeys: String, CodingKey {
        case name = "workspace", monitorID = "monitor-id"
        case isVisible = "workspace-is-visible", isFocused = "workspace-is-focused"
        case rootLayoutKind = "workspace-root-container-layout"
    }
}

public struct WorkspaceWindow: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var appName: String
    public var bundleID: String
    public var pid: Int32
    public var workspace: String
    public var title: String
    /// AeroSpace reports floating or the parent tiling layout. Nil supports older snapshots.
    public var layoutKind: String?
    public var isFloating: Bool { layoutKind == "floating" }

    public init(id: Int, appName: String, bundleID: String, pid: Int32 = 0, workspace: String, title: String = "", layoutKind: String? = nil) {
        self.id = id; self.appName = appName; self.bundleID = bundleID
        self.pid = pid; self.workspace = workspace; self.title = title
        self.layoutKind = layoutKind
    }

    enum CodingKeys: String, CodingKey {
        case id = "window-id", appName = "app-name", bundleID = "app-bundle-id"
        case pid = "app-pid", workspace, title = "window-title"
        case layoutKind = "window-layout"
    }
}

public struct WorkspaceApp: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var bundleID: String
    public var pid: Int32
    public var windows: [WorkspaceWindow]
    public var hasFloatingWindows: Bool { windows.contains(where: \.isFloating) }
    public var floatingWindowCount: Int { windows.filter(\.isFloating).count }
    /// Application shortcuts remain grouped; preview icons are separately generated per window.
    public var iconWindow: WorkspaceWindow? { windows.first(where: \.isFloating) ?? windows.first }
    public init(id: String, name: String, bundleID: String, pid: Int32, windows: [WorkspaceWindow]) {
        self.id = id; self.name = name; self.bundleID = bundleID; self.pid = pid; self.windows = windows
    }
}

public struct Snapshot: Equatable, Sendable {
    public var monitors: [Monitor]
    public var workspaces: [Workspace]
    public var windows: [WorkspaceWindow]

    public init(monitors: [Monitor], workspaces: [Workspace], windows: [WorkspaceWindow]) {
        self.monitors = monitors; self.workspaces = workspaces; self.windows = windows
    }

    public static let empty = Snapshot(monitors: [], workspaces: [], windows: [])
    public var focusedWorkspace: Workspace? { workspaces.first { $0.isFocused } }

    /// Tiled windows first, floating windows last; tiled regions read column-first, splitting
    /// into rows around spanning windows. Floating windows read left to right, then top to bottom.
    /// Z-order breaks identical-position ties only; it must not move a right-hand
    /// window's icon ahead of a left-hand window. Unknown positions follow known ones.
    public func orderedWindows(in workspace: String, layout: WorkspaceGeometry? = nil) -> [WorkspaceWindow] {
        let placements = Dictionary((layout?.placements ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = windows.filter { $0.workspace == workspace }.sorted { left, right in
            if left.isFloating != right.isFloating { return !left.isFloating }
            switch (placements[left.id], placements[right.id]) {
            case let (a?, b?):
                if a.rect.minX != b.rect.minX { return a.rect.minX < b.rect.minX }
                if a.rect.minY != b.rect.minY { return a.rect.minY < b.rect.minY }
                if a.zOrder != b.zOrder { return a.zOrder > b.zOrder }
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): break
            }
            let comparison = left.appName.localizedStandardCompare(right.appName)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return left.id < right.id
        }
        let tiled = ordered.filter { !$0.isFloating && placements[$0.id] != nil }
        let unplaced = ordered.filter { !$0.isFloating && placements[$0.id] == nil }
        let rootAxis = workspaces.first { $0.name == workspace }?.rootAxis
        return SpatialWindowOrder.tiled(tiled, placements: placements, preferredAxis: rootAxis) + unplaced + ordered.filter(\.isFloating)
    }

    public func apps(in workspace: String, layout: WorkspaceGeometry? = nil) -> [WorkspaceApp] {
        var result: [WorkspaceApp] = [], indices: [String: Int] = [:]
        let ordered = orderedWindows(in: workspace, layout: layout)
        for window in ordered {
            let key = window.bundleID.isEmpty ? "pid:\(window.pid):\(window.appName)" : window.bundleID
            if let index = indices[key] { result[index].windows.append(window) }
            else {
                indices[key] = result.count
                result.append(WorkspaceApp(id: key, name: window.appName, bundleID: window.bundleID,
                                           pid: window.pid, windows: [window]))
            }
        }
        let ranks = Dictionary(ordered.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return result.sorted {
            let left = $0.iconWindow.flatMap { ranks[$0.id] } ?? Int.max
            let right = $1.iconWindow.flatMap { ranks[$0.id] } ?? Int.max
            return left < right
        }
    }

    public func orderedWorkspaces(showEmpty: Bool, preferredOrder: [String] = []) -> [Workspace] {
        let occupied = Set(windows.map(\.workspace))
        var ranks: [String: Int] = [:]
        for name in preferredOrder where ranks[name] == nil { ranks[name] = ranks.count }
        return workspaces.filter { showEmpty || occupied.contains($0.name) }
            .sorted {
                let left = ranks[$0.name] ?? Int.max, right = ranks[$1.name] ?? Int.max
                if left != right { return left < right }
                let comparison = $0.name.localizedStandardCompare($1.name)
                return comparison == .orderedSame ? $0.name < $1.name : comparison == .orderedAscending
            }
    }
}
