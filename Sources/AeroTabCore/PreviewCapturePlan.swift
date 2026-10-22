import Foundation
import CoreGraphics

public struct PreviewCaptureRequest: Equatable, Sendable {
    public var window: WorkspaceWindow
    public var bounds: CGSize

    /// Match the miniature's actual display footprint at 2x, capped at 512 px.
    /// Capture pixels preserve the source aspect ratio even for portrait windows.
    public func pixelSize(for source: CGSize) -> CGSize {
        guard source.width.isFinite, source.height.isFinite, source.width > 0, source.height > 0 else {
            return CGSize(width: 256, height: 160)
        }
        let scale = min(bounds.width * 2 / source.width, bounds.height * 2 / source.height,
                        512 / max(source.width, source.height))
        return CGSize(width: min(512, max(1, ceil(source.width * scale))), height: min(512, max(1, ceil(source.height * scale))))
    }
}

public enum PreviewCapturePlan {
    public static func requests(snapshot: Snapshot, layouts: [String: WorkspaceGeometry],
                                workspaceOrder: [String], selectedWorkspace: String?) -> [PreviewCaptureRequest] {
        let ordered = snapshot.orderedWorkspaces(showEmpty: false, preferredOrder: workspaceOrder)
        let names = ordered.map(\.name)
        let prioritized = names.filter { $0 == selectedWorkspace } + names.filter { $0 != selectedWorkspace }
        return prioritized.flatMap { name -> [PreviewCaptureRequest] in
            let windows = snapshot.orderedWindows(in: name, layout: layouts[name])
            let stripCount = Double(max(1, min(4, windows.count)))
            let stripBounds = CGSize(width: (266 - (stripCount - 1) * 4) / stripCount, height: 140)
            guard let layout = layouts[name] else {
                return windows.prefix(4).map { PreviewCaptureRequest(window: $0, bounds: stripBounds) }
            }
            let canvas = CGSize(width: min(276, 156 * layout.aspectRatio), height: min(156, 276 / layout.aspectRatio))
            return windows.compactMap { window in
                if let placement = layout.placements.first(where: { $0.id == window.id }) {
                    return PreviewCaptureRequest(window: window, bounds: CGSize(width: max(1, canvas.width * placement.rect.width),
                                                                              height: max(1, canvas.height * placement.rect.height)))
                }
                // With a partial layout, the UI shows a count rather than extra surfaces.
                // A wholly unknown layout displays at most four window previews.
                guard layout.placements.isEmpty, windows.prefix(4).contains(where: { $0.id == window.id }) else { return nil }
                return PreviewCaptureRequest(window: window, bounds: stripBounds)
            }
        }
    }
}
