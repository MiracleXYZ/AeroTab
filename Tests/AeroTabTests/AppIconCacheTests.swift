import AppKit
import Testing
import AeroTabCore
@testable import AeroTab

@Suite("App icon refresh") @MainActor
struct AppIconCacheTests {
    @MainActor private final class State {
        var selected = NSImage(size: NSSize(width: 20, height: 20))
        var reads = 0
        var dark = false
        var requests: [String] = []
    }
    private func app(pid: Int32 = 42) -> WorkspaceApp {
        .init(id: "example", name: "Example", bundleID: "example", pid: pid, windows: [])
    }

    @Test("The icon updates on reopening the switcher while repeated windows share one load per presentation")
    func refreshOnOpen() {
        let original = NSImage(size: NSSize(width: 20, height: 20))
        let replacement = NSImage(size: NSSize(width: 20, height: 20))
        let state = State()
        state.selected = original
        let cache = AppIconCache(load: { _, _ in state.reads += 1; return state.selected }, isDark: { false })
        #expect(cache.icon(for: app()) === original)
        state.selected = replacement
        #expect(cache.icon(for: app()) === original)
        #expect(state.reads == 1)
        cache.beginPresentation()
        #expect(cache.icon(for: app()) === replacement)
        #expect(cache.icon(for: app()) === replacement)
        #expect(state.reads == 2)
    }

    @Test("A restarted process or changed appearance cannot inherit another cached icon")
    func processAndAppearance() {
        let state = State()
        let cache = AppIconCache(load: { app, isDark in
            state.requests.append("\(app.pid):\(isDark)")
            return NSImage(size: NSSize(width: 20, height: 20))
        }, isDark: { state.dark })
        _ = cache.icon(for: app())
        _ = cache.icon(for: app(pid: 43))
        state.dark = true
        _ = cache.icon(for: app(pid: 43))
        _ = cache.icon(for: app(pid: 43))
        #expect(state.requests == ["42:false", "43:false", "43:true"])
    }
}
