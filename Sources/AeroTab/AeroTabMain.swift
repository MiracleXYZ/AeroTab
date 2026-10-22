import AppKit
import ApplicationServices
import AeroTabCore

@main
enum AeroTabMain {
    @MainActor static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        func value(after flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        let configURL = value(after: "--config").map { URL(fileURLWithPath: $0) }
        if args.contains("--help") {
            print("""
            AeroTab — native AeroSpace workspace switcher for macOS 26+
            --config PATH          Use a separate settings file
            --diagnose             Read-only connection check; no windows or keyboard capture
            --check-previews       With --diagnose, check capture in memory if permission is already granted
            --render-preview PATH  Render demo PNG without presenting a window
            --render-live-layout PATH  Render current window geometry without capturing window contents
            --help                 Show this help
            """)
            return
        }
        if args.contains("--diagnose") {
            let store = SettingsStore(url: configURL ?? SettingsStore.defaultURL)
            Task {
                do {
                    let client = AeroSpaceClient(executable: store.configuration.aerospacePath)
                    let snapshot = try await client.snapshot()
                    let order = await client.workspaceOrder()
                    print("AeroSpace: connected")
                    print("Monitors: \(snapshot.monitors.count); workspaces: \(snapshot.workspaces.count); windows: \(snapshot.windows.count)")
                    for monitor in snapshot.monitors {
                        print("  \(monitor.name): NSScreen index \(monitor.screenIndex)")
                    }
                    print("Visible workspaces: \(snapshot.workspaces.filter(\.isVisible).map(\.name).joined(separator: ", "))")
                    print("Focused workspace: \(snapshot.focusedWorkspace?.name ?? "none")")
                    print("AeroSpace workspace order: \(order.names.joined(separator: ", "))")
                    if let issue = order.issue { print(issue) }
                    print("This process: Accessibility=\(AXIsProcessTrusted()), ScreenCapture=\(CGPreflightScreenCaptureAccess())")
                    let previews = WindowPreviewStore()
                    previews.updateGeometry(snapshot)
                    print("Window geometry: \(previews.layouts.values.reduce(0) { $0 + $1.placements.count }) placed, \(previews.layouts.values.reduce(0) { $0 + $1.unplacedWindowIDs.count }) unknown")
                    if args.contains("--check-previews") {
                        if CGPreflightScreenCaptureAccess() {
                            previews.capture(snapshot, enabled: true)
                            await previews.waitForCapture()
                            print("Captured in memory: \(previews.images.count)/\(snapshot.windows.count) windows")
                            print("One-shot capture: \(String(format: "%.3f", previews.captureDuration)) s; \(previews.capturedPixelCount) output pixels")
                            if let issue = previews.captureIssue { print(issue) }
                            previews.cancelCapture(clearImages: true)
                        } else { print("Capture skipped: grant Screen Recording to AeroTab in its setup guide.") }
                    }
                    print("No UI, event tap, configuration writes, or focus commands were used.")
                    if args.contains("--audit-wait") { try await Task.sleep(for: .seconds(4)) }
                    exit(0)
                } catch {
                    fputs("\(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
            RunLoop.main.run()
            return
        }
        if let output = value(after: "--render-live-layout") {
            NSApplication.shared.setActivationPolicy(.prohibited)
            let store = SettingsStore(url: configURL ?? SettingsStore.defaultURL)
            Task {
                do {
                    let snapshot = try await AeroSpaceClient(executable: store.configuration.aerospacePath).snapshot()
                    try PreviewRenderer.renderLiveLayout(snapshot: snapshot, to: URL(fileURLWithPath: output))
                    print("Rendered live geometry; no window contents captured: \(output)")
                    if args.contains("--audit-wait") { try await Task.sleep(for: .seconds(4)) }
                    exit(0)
                } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            }
            RunLoop.main.run()
            return
        }
        if let output = value(after: "--render-preview") {
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            do {
                try PreviewRenderer.render(to: URL(fileURLWithPath: output))
                print("Rendered \(output)")
                if args.contains("--audit-wait") { RunLoop.main.run(until: Date().addingTimeInterval(4)) }
            }
            catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate(settingsURL: configURL)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
