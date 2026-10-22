import Foundation

/// Read separate columns left to right, and rows top to bottom within each column.
/// If a window spans the entire width, split into rows first so it cannot interrupt
/// two side-by-side windows. Overlapping windows retain the stable fallback order.
enum SpatialWindowOrder {
    static func tiled(_ windows: [WorkspaceWindow], placements: [Int: WindowPlacement], preferredAxis: LayoutAxis? = nil) -> [WorkspaceWindow] {
        guard windows.count > 1 else { return windows }
        for axis in [preferredAxis ?? .horizontal, preferredAxis?.opposite ?? .vertical] {
            let groups = partitions(windows, placements: placements, axis: axis)
            if groups.count > 1 {
                return groups.flatMap { tiled($0, placements: placements, preferredAxis: axis.opposite) }
            }
        }
        return windows
    }

    static func partitions(_ windows: [WorkspaceWindow], placements: [Int: WindowPlacement],
                           axis: LayoutAxis) -> [[WorkspaceWindow]] {
        func bounds(_ window: WorkspaceWindow) -> (start: CGFloat, end: CGFloat) {
            let rect = placements[window.id]!.rect // Caller passes only windows with known placements.
            return axis == .horizontal ? (rect.minX, rect.maxX) : (rect.minY, rect.maxY)
        }
        // Preserve fallback order inside a partition, including overlapping foreground windows.
        let sorted = windows.enumerated().sorted {
            let left = bounds($0.element).start, right = bounds($1.element).start
            return left == right ? $0.offset < $1.offset : left < right
        }
        var groups: [[Int]] = []
        var end = -CGFloat.infinity
        for item in sorted {
            let interval = bounds(item.element)
            if groups.isEmpty || interval.start >= end {
                groups.append([item.offset])
                end = interval.end
            } else {
                groups[groups.count - 1].append(item.offset)
                end = max(end, interval.end)
            }
        }
        return groups.map { $0.sorted().map { windows[$0] } }
    }
}
