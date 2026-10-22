import AppKit
import Observation
@preconcurrency import ScreenCaptureKit
import AeroTabCore

@MainActor @Observable
final class WindowPreviewStore {
    var layouts: [String: WorkspaceGeometry] = [:]
    var images: [Int: CGImage] = [:]
    var captureIssue: String?
    var isCapturing = false
    @ObservationIgnored private(set) var capturedPixelCount = 0
    @ObservationIgnored private(set) var captureDuration: TimeInterval = 0
    @ObservationIgnored private var memory = LayoutMemory()
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    func updateGeometry(_ snapshot: Snapshot) {
        let screens = NSScreen.screens
        let originY = screens.first?.frame.maxY ?? 0
        var monitors: [Int: CGRect] = [:]
        for monitor in snapshot.monitors {
            guard screens.indices.contains(monitor.screenIndex - 1) else { continue }
            let frame = screens[monitor.screenIndex - 1].frame
            monitors[monitor.id] = CGRect(x: frame.minX, y: originY - frame.maxY, width: frame.width, height: frame.height)
        }
        let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let targets = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.id, $0.pid) })
        var frames: [Int: WindowGeometry] = [:]
        for (index, info) in raw.enumerated() {
            guard let id = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, targets[id] == pid,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { continue }
            frames[id] = WindowGeometry(frame: frame, zOrder: raw.count - index)
        }
        let updated = memory.update(snapshot: snapshot, frames: frames, monitors: monitors)
        if layouts != updated { layouts = updated }
        let ids = Set(snapshot.windows.map(\.id))
        if images.keys.contains(where: { !ids.contains($0) }) {
            images = images.filter { ids.contains($0.key) }
        }
    }

    func capture(_ snapshot: Snapshot, enabled: Bool, workspaceOrder: [String] = [], selectedWorkspace: String? = nil) {
        guard enabled, CGPreflightScreenCaptureAccess() else {
            cancelCapture(clearImages: true)
            return
        }
        guard !isCapturing else { return }
        let plan = PreviewCapturePlan.requests(snapshot: snapshot, layouts: layouts,
                                               workspaceOrder: workspaceOrder, selectedWorkspace: selectedWorkspace)
        guard !plan.isEmpty else { return }
        isCapturing = true
        capturedPixelCount = 0; captureDuration = 0
        let request = generation
        let start = Date()
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == request { isCapturing = false; captureDuration = Date().timeIntervalSince(start) }
            }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                guard !Task.isCancelled, request == generation else { return }
                let available = Dictionary(uniqueKeysWithValues: content.windows.map { (Int($0.windowID), $0) })
                // A window filter captures its own surface even when another window occludes it.
                var batch: [Int: CGImage] = [:]
                if captureIssue != nil { captureIssue = nil }
                for (index, item) in plan.enumerated() {
                    guard !Task.isCancelled, request == generation else { return }
                    guard let window = available[item.window.id], window.owningApplication?.processID == item.window.pid else { continue }
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    let config = SCStreamConfiguration()
                    let size = item.pixelSize(for: window.frame.size)
                    config.width = Int(size.width)
                    config.height = Int(size.height)
                    config.showsCursor = false
                    config.ignoreShadowsSingleWindow = true
                    config.captureResolution = .nominal
                    config.includeChildWindows = false
                    do {
                        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                        guard !Task.isCancelled, request == generation else { return }
                        batch[Int(window.windowID)] = image
                        capturedPixelCount += image.width * image.height
                    } catch {
                        // One closed/protected window must not prevent the other previews.
                        guard !Task.isCancelled, request == generation else { return }
                    }
                    // Publish at workspace boundaries, instead of invalidating the entire
                    // grid for each image. Pace the one-shot capture to avoid a tight burst.
                    if index == plan.count - 1 || plan[index + 1].window.workspace != item.window.workspace {
                        if !batch.isEmpty { images.merge(batch) { _, new in new }; batch.removeAll(keepingCapacity: true) }
                    }
                    try await Task.sleep(for: .milliseconds(40))
                }
                if !batch.isEmpty { images.merge(batch) { _, new in new } }
                if !snapshot.windows.isEmpty && images.isEmpty {
                    captureIssue = L10n.string("Window contents are unavailable; showing layouts instead.")
                }
            } catch {
                guard request == generation, !Task.isCancelled else { return }
                captureIssue = L10n.string("Could not capture previews. Check Screen Recording permission.")
            }
        }
    }

    func cancelCapture(clearImages: Bool = false) {
        generation += 1
        captureTask?.cancel(); captureTask = nil; isCapturing = false
        if clearImages {
            if !images.isEmpty { images.removeAll() }
            if captureIssue != nil { captureIssue = nil }
        }
    }

    func waitForCapture() async { await captureTask?.value }
}
