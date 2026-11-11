import AppKit
import AeroTabCore

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private struct Key: Hashable {
        var appID: String
        var pid: Int32
        var dark: Bool
    }
    private var icons: [Key: NSImage] = [:]
    private let load: @MainActor (WorkspaceApp, Bool) -> NSImage?
    private let isDark: @MainActor () -> Bool

    init(load: @escaping @MainActor (WorkspaceApp, Bool) -> NSImage? = AppIconCache.systemIcon,
         isDark: @escaping @MainActor () -> Bool = {
             NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
         }) {
        self.load = load; self.isDark = isDark
    }

    /// Cache within one presentation only, so changes made while the switcher is
    /// closed are reflected on the next invocation without polling or GPU work.
    func beginPresentation() { icons.removeAll(keepingCapacity: true) }

    func icon(for app: WorkspaceApp) -> NSImage {
        let key = Key(appID: app.id, pid: app.pid, dark: isDark())
        if let cached = icons[key] { return cached }
        let image = load(app, key.dark) ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: app.name)!
        icons[key] = image
        return image
    }

    private static func systemIcon(for app: WorkspaceApp, dark: Bool) -> NSImage? {
        let candidate = app.pid > 0 ? NSRunningApplication(processIdentifier: app.pid) : nil
        let running = candidate.flatMap { app.bundleID.isEmpty || $0.bundleIdentifier == app.bundleID ? $0 : nil }
        let url = running?.bundleURL ?? (app.bundleID.isEmpty ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID))
        if let url, app.bundleID == "com.openai.codex",
           let custom = codexIcon(in: url, dark: dark) { return custom }
        if let image = running?.icon { return image }
        return url.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    private static func codexIcon(in bundleURL: URL, dark: Bool) -> NSImage? {
        let override = ProcessInfo.processInfo.environment["CODEX_HOME"]
        let directory = override.flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        let config = directory.appendingPathComponent("config.toml")
        // Read only the icon preference; never log or persist another app's settings.
        guard let size = try? config.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576,
              let source = try? String(contentsOf: config, encoding: .utf8),
              let name = CodexIconPreference.read(source)?.resourceName(dark: dark) else { return nil }
        return NSImage(contentsOf: bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true).appendingPathComponent(name))
    }
}
