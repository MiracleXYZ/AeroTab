import SwiftUI
import AeroTabCore

@MainActor
enum PreviewRenderer {
    /// Synthetic fixtures exercise the production view; no personal window contents are captured.
    static func render(to url: URL) throws {
        for language in ["en", "zh-Hans"] {
            try renderDocumentation(in: url.deletingLastPathComponent(), language: language)
        }
        let model = fixtureModel()
        let metrics = SwitcherMetrics(count: model.workspaces.count, availableWidth: 1400, availableHeight: 900)
        for (id, title, code) in [(1, "AeroSpace · Workspace guide", false), (2, "aerotab — swift build", true),
                                  (3, "Reading notes", false), (4, "Design references", false), (5, "Project discussion", false)] {
            let layout = model.previews.layouts.values.first { $0.placements.contains { $0.id == id } }!
            let rect = layout.placements.first { $0.id == id }!.rect
            let ratio = rect.width * layout.aspectRatio / rect.height
            let renderer = ImageRenderer(content: FixtureWindow(title: title, code: code)
                .frame(width: 620 * min(1, ratio), height: 620 / max(1, ratio)))
            model.previews.images[id] = renderer.cgImage
        }
        try write(SwitcherView(model: model, monitorID: nil, metrics: metrics, useSolidBackground: true),
                  size: CGSize(width: metrics.width, height: metrics.height), to: url, dark: true)
        let originalLayouts = model.previews.layouts
        let originalWindows = model.snapshot.windows
        // Fully stacked windows must still expose both apps in the preview's shared icon overlay.
        model.previews.layouts["2"] = WorkspaceGeometry(placements: [
            WindowPlacement(id: 3, rect: CGRect(x: 0, y: 0, width: 1, height: 1)),
            WindowPlacement(id: 4, rect: CGRect(x: 0, y: 0, width: 1, height: 1), zOrder: 1)
        ])
        // More apps than fit on one row must wrap, including apps without captured images.
        let additionalApps = [("Safari", "com.apple.Safari"), ("Notes", "com.apple.Notes"),
                              ("Terminal", "com.apple.Terminal"), ("Finder", "com.apple.finder"),
                              ("Mail", "com.apple.mail"), ("Calendar", "com.apple.iCal"),
                              ("Reminders", "com.apple.reminders"), ("TextEdit", "com.apple.TextEdit"),
                              ("Preview", "com.apple.Preview"), ("Settings", "com.apple.systempreferences"),
                              ("Music", "com.apple.Music"), ("Photos", "com.apple.Photos")]
        for (index, app) in additionalApps.enumerated() {
            model.snapshot.windows.append(WorkspaceWindow(id: index + 6, appName: app.0, bundleID: app.1, workspace: "A"))
        }
        model.previews.layouts["A"] = WorkspaceGeometry(placements: model.snapshot.windows.filter { $0.workspace == "A" }.enumerated().map {
            WindowPlacement(id: $0.element.id, rect: CGRect(x: 0, y: 0, width: 1, height: 1), zOrder: $0.offset)
        })
        try write(SwitcherView(model: model, monitorID: nil, metrics: metrics, useSolidBackground: true),
                  size: CGSize(width: metrics.width, height: metrics.height),
                  to: url.deletingPathExtension().appendingPathExtension("overlap.png"), dark: true)
        model.previews.layouts = originalLayouts
        model.snapshot.windows = originalWindows
        // Requested layout: Notes above Terminal in the left column, Safari on the right.
        model.snapshot.windows.append(WorkspaceWindow(id: 6, appName: "Notes", bundleID: "com.apple.Notes", workspace: "1", title: "A · Upper left"))
        model.previews.images[6] = model.previews.images[3]
        model.previews.layouts["1"] = WorkspaceGeometry(placements: [
            WindowPlacement(id: 6, rect: CGRect(x: 0, y: 0, width: 0.48, height: 0.48)),
            WindowPlacement(id: 2, rect: CGRect(x: 0, y: 0.52, width: 0.48, height: 0.48)),
            WindowPlacement(id: 1, rect: CGRect(x: 0.52, y: 0, width: 0.48, height: 1))
        ])
        model.previews.layouts["2"] = WorkspaceGeometry(placements: [
            WindowPlacement(id: 3, rect: CGRect(x: 0, y: 0, width: 1, height: 1)),
            WindowPlacement(id: 4, rect: CGRect(x: 0, y: 0, width: 1, height: 1), zOrder: 1)
        ])
        for dark in [true, false] {
            try write(SwitcherView(model: model, monitorID: nil, metrics: metrics, useSolidBackground: true),
                      size: CGSize(width: metrics.width, height: metrics.height),
                      to: url.deletingPathExtension().appendingPathExtension("vertical-\(dark ? "dark" : "light").png"), dark: dark)
        }
        // ABCD: Notes/Terminal share a vertical line; floating Messages stays last with a dot.
        model.snapshot.windows.append(WorkspaceWindow(id: 7, appName: "Messages", bundleID: "com.apple.MobileSMS", workspace: "1",
                                                       title: "D · Floating", layoutKind: "floating"))
        model.previews.images[7] = model.previews.images[5]
        model.previews.layouts["1"]?.placements.append(WindowPlacement(id: 7, rect: CGRect(x: 0, y: 0.28, width: 0.58, height: 0.42), zOrder: 10))
        // Aligned floating windows must both get dots, never a shared vertical line.
        for index in model.snapshot.windows.indices where model.snapshot.windows[index].workspace == "2" || model.snapshot.windows[index].workspace == "A" {
            model.snapshot.windows[index].layoutKind = "floating"
        }
        model.previews.layouts["2"] = WorkspaceGeometry(placements: [
            WindowPlacement(id: 3, rect: CGRect(x: 0, y: 0, width: 1, height: 0.48)),
            WindowPlacement(id: 4, rect: CGRect(x: 0, y: 0.52, width: 1, height: 0.48))
        ])
        model.previews.layouts["A"] = WorkspaceGeometry(placements: [], unplacedWindowIDs: [5])
        for dark in [true, false] {
            try write(SwitcherView(model: model, monitorID: nil, metrics: metrics, useSolidBackground: true),
                      size: CGSize(width: metrics.width, height: metrics.height),
                      to: url.deletingPathExtension().appendingPathExtension("floating-\(dark ? "dark" : "light").png"), dark: dark)
        }
        model.previews.images.removeValue(forKey: 7)
        model.previews.images.removeValue(forKey: 6)
        model.previews.layouts = originalLayouts
        model.snapshot.windows = originalWindows
        model.settings.configuration.appShortcuts = AppShortcut.bottomRow
        try renderRepeatedWindows(to: url)
        model.snapshot.workspaces.append(Workspace(name: "B", monitorID: 1))
        try write(SwitcherView(model: model, monitorID: nil, metrics: metrics, useSolidBackground: true),
                  size: CGSize(width: metrics.width, height: metrics.height),
                  to: url.deletingPathExtension().appendingPathExtension("custom-keys.png"), dark: true)
        for dark in [true, false] {
            try write(AppShortcutSettings(model: model, store: model.settings), size: CGSize(width: 570, height: 560),
                      to: url.deletingPathExtension().appendingPathExtension("keys-\(dark ? "dark" : "light").png"), dark: dark)
        }
        model.settings.configuration.appShortcuts = AppShortcut.functionKeys
        model.snapshot.workspaces.removeAll { $0.name == "B" }
        model.previews.layouts["2"] = WorkspaceGeometry(placements: [], unplacedWindowIDs: [3, 4])
        model.snapshot.windows += [
            WorkspaceWindow(id: 6, appName: "Terminal", bundleID: "com.apple.Terminal", workspace: "A"),
            WorkspaceWindow(id: 7, appName: "Notes", bundleID: "com.apple.Notes", workspace: "A"),
            WorkspaceWindow(id: 8, appName: "Safari", bundleID: "com.apple.Safari", workspace: "A"),
            WorkspaceWindow(id: 9, appName: "Finder", bundleID: "com.apple.finder", workspace: "A")
        ]
        model.previews.layouts["A"] = WorkspaceGeometry(placements: [], unplacedWindowIDs: [5, 6, 7, 8, 9])
        try write(SwitcherView(model: model, monitorID: nil, metrics: metrics, useSolidBackground: true),
                  size: CGSize(width: metrics.width, height: metrics.height),
                  to: url.deletingPathExtension().appendingPathExtension("unknown.png"), dark: true)
        model.previews.layouts = originalLayouts
        model.snapshot.windows = originalWindows
        model.settings.configuration.styles["1"] = WorkspaceStyle(tint: .coral, customColorHex: "#E6C7FF")
        model.settings.configuration.styles["2"] = WorkspaceStyle(tint: .violet, customColorHex: "#A78BFA")
        try write(SwitcherView(model: model, monitorID: nil, metrics: metrics, useSolidBackground: true),
                  size: CGSize(width: metrics.width, height: metrics.height),
                  to: url.deletingPathExtension().appendingPathExtension("custom-color.png"), dark: true)
        try write(SettingsView(model: model, enableKeyboard: {}, store: model.settings),
                  size: CGSize(width: 650, height: 570),
                  to: url.deletingPathExtension().appendingPathExtension("settings.png"), dark: false)
        model.settings.configuration.workspaceOrderSource = .custom
        model.settings.configuration.customWorkspaceOrder = ["A", "1", "2", "3"]
        try write(SettingsView(model: model, enableKeyboard: {}, store: model.settings, selectedTab: 1),
                  size: CGSize(width: 650, height: 570),
                  to: url.deletingPathExtension().appendingPathExtension("order.png"), dark: false)
        for (tab, name) in [(0, "settings"), (1, "order"), (2, "help")] {
            try write(SettingsView(model: model, enableKeyboard: {}, store: model.settings, selectedTab: tab),
                      size: CGSize(width: 650, height: 570),
                      to: url.deletingPathExtension().appendingPathExtension("\(name)-dark.png"), dark: true)
        }
        model.settings.configuration.workspaceOrderSource = .aerospace
        model.screenCaptureGranted = false
        model.previews.images.removeAll()
        let layoutMetrics = SwitcherMetrics(count: model.workspaces.count, availableWidth: 1400, availableHeight: 900, extraHeight: 24)
        try write(SwitcherView(model: model, monitorID: nil, metrics: layoutMetrics, useSolidBackground: true),
                  size: CGSize(width: layoutMetrics.width, height: layoutMetrics.height),
                  to: url.deletingPathExtension().appendingPathExtension("layout.png"), dark: true)
        model.keyboardReady = false
        model.accessibilityGranted = false
        model.keyboardIssue = "请先允许辅助功能，⌥Tab 才能切换工作区。"
        try write(SetupView(model: model, requestAccessibility: {}, requestScreenCapture: {}, recheck: {}, finish: {}, later: {}),
                  size: CGSize(width: 570, height: 610),
                  to: url.deletingPathExtension().appendingPathExtension("setup.png"), dark: false)
    }

    /// Reproducible README screenshots. Both window metadata and contents are fictional.
    private static func renderDocumentation(in directory: URL, language: String) throws {
        let model = fixtureModel()
        let chinese = language == "zh-Hans"
        let suffix = chinese ? "zh" : "en"
        model.settings.configuration.language = chinese ? .simplifiedChinese : .english
        if chinese {
            model.snapshot.monitors[0].name = "内建显示器"
            model.snapshot.monitors[1].name = "外接显示器"
        }
        model.snapshot.workspaces = [
            Workspace(name: "1", monitorID: 1, isVisible: true, isFocused: true, rootLayoutKind: "v_tiles"),
            Workspace(name: "2", monitorID: 1, rootLayoutKind: "h_tiles"),
            Workspace(name: "A", monitorID: 2, isVisible: true, rootLayoutKind: "h_tiles")
        ]
        model.snapshot.windows = [
            WorkspaceWindow(id: 1, appName: "Finder", bundleID: "com.apple.finder", workspace: "1", title: "Projects"),
            WorkspaceWindow(id: 2, appName: "Finder", bundleID: "com.apple.finder", workspace: "1", title: "Resources"),
            WorkspaceWindow(id: 3, appName: "Terminal", bundleID: "com.apple.Terminal", workspace: "1", title: "Build output"),
            WorkspaceWindow(id: 4, appName: "Safari", bundleID: "com.apple.Safari", workspace: "2", title: "Workspace guide"),
            WorkspaceWindow(id: 5, appName: "Notes", bundleID: "com.apple.Notes", workspace: "2", title: "Ideas", layoutKind: "floating"),
            WorkspaceWindow(id: 6, appName: "Notes", bundleID: "com.apple.Notes", workspace: "A", title: "Reading list")
        ]
        model.previews.layouts = [
            "1": WorkspaceGeometry(placements: [
                WindowPlacement(id: 1, rect: CGRect(x: 0, y: 0, width: 0.495, height: 0.59)),
                WindowPlacement(id: 2, rect: CGRect(x: 0.505, y: 0, width: 0.495, height: 0.59)),
                WindowPlacement(id: 3, rect: CGRect(x: 0, y: 0.61, width: 1, height: 0.39))
            ]),
            "2": WorkspaceGeometry(placements: [
                WindowPlacement(id: 4, rect: CGRect(x: 0, y: 0, width: 1, height: 1)),
                WindowPlacement(id: 5, rect: CGRect(x: 0.4, y: 0.3, width: 0.59, height: 0.65), zOrder: 1)
            ], isRemembered: true),
            "A": WorkspaceGeometry(placements: [WindowPlacement(id: 6, rect: CGRect(x: 0, y: 0, width: 1, height: 1))])
        ]
        if chinese {
            let titles = ["项目", "资源", "构建输出", "工作区指南", "灵感", "阅读清单"]
            for index in model.snapshot.windows.indices {
                model.snapshot.windows[index].title = titles[index]
                if model.snapshot.windows[index].appName == "Terminal" { model.snapshot.windows[index].appName = "终端" }
                if model.snapshot.windows[index].appName == "Notes" { model.snapshot.windows[index].appName = "备忘录" }
            }
        }
        for window in model.snapshot.windows {
            let layout = model.previews.layouts[window.workspace]!
            let rect = layout.placements.first { $0.id == window.id }!.rect
            let ratio = rect.width * layout.aspectRatio / rect.height
            let renderer = ImageRenderer(content: FixtureWindow(title: window.title, code: window.bundleID == "com.apple.Terminal", chinese: chinese)
                .frame(width: 620 * min(1, ratio), height: 620 / max(1, ratio)))
            model.previews.images[window.id] = renderer.cgImage
        }
        let metrics = SwitcherMetrics(count: model.workspaces.count, availableWidth: 1400, availableHeight: 900)
        for dark in [true, false] {
            try write(SwitcherView(model: model, monitorID: nil, metrics: metrics, useSolidBackground: true),
                      size: CGSize(width: metrics.width, height: metrics.height),
                      to: directory.appendingPathComponent("demo-\(suffix)-\(dark ? "dark" : "light").png"), dark: dark, language: language)
        }
        model.settings.configuration.styles["1"] = WorkspaceStyle(label: chinese ? "开发" : "Build", tint: .coral)
        model.settings.configuration.styles["2"] = WorkspaceStyle(label: chinese ? "探索" : "Explore", tint: .violet, customColorHex: "#A78BFA")
        model.settings.configuration.styles["A"] = WorkspaceStyle(label: chinese ? "阅读" : "Read", tint: .mint)
        try write(SettingsView(model: model, enableKeyboard: {}, store: model.settings, selectedTab: 1),
                  size: CGSize(width: 650, height: 570),
                  to: directory.appendingPathComponent("demo-settings-\(suffix).png"), dark: true, language: language)
        // Inspect all translated surfaces during QA; only curated demo files become README assets.
        for tab in [0, 2] {
            try write(SettingsView(model: model, enableKeyboard: {}, store: model.settings, selectedTab: tab),
                      size: CGSize(width: 650, height: 570),
                      to: directory.appendingPathComponent("i18n-settings-\(tab)-\(suffix).png"), dark: true, language: language)
        }
        try write(AppShortcutSettings(model: model, store: model.settings), size: CGSize(width: 570, height: 450),
                  to: directory.appendingPathComponent("i18n-keys-\(suffix).png"), dark: true, language: language)
        try write(SetupView(model: model, requestAccessibility: {}, requestScreenCapture: {}, recheck: {}, finish: {}, later: {}),
                  size: CGSize(width: 570, height: 610),
                  to: directory.appendingPathComponent("i18n-setup-\(suffix).png"), dark: true, language: language)
    }

    private static func renderRepeatedWindows(to url: URL) throws {
        let model = fixtureModel()
        for index in model.snapshot.workspaces.indices {
            model.snapshot.workspaces[index].rootLayoutKind = model.snapshot.workspaces[index].name == "A" ? "h_accordion" : "v_tiles"
        }
        model.snapshot.windows = [
            WorkspaceWindow(id: 1, appName: "Finder", bundleID: "com.apple.finder", workspace: "1", title: "Downloads"),
            WorkspaceWindow(id: 2, appName: "Finder", bundleID: "com.apple.finder", workspace: "1", title: "Projects"),
            WorkspaceWindow(id: 3, appName: "Terminal", bundleID: "com.apple.Terminal", workspace: "1", title: "Build output"),
            WorkspaceWindow(id: 4, appName: "Finder", bundleID: "com.apple.finder", workspace: "2", title: "Upper folder"),
            WorkspaceWindow(id: 5, appName: "Finder", bundleID: "com.apple.finder", workspace: "2", title: "Lower folder"),
            WorkspaceWindow(id: 6, appName: "Finder", bundleID: "com.apple.finder", workspace: "2", title: "Floating folder", layoutKind: "floating")
        ]
        model.snapshot.windows += (7...19).map {
            WorkspaceWindow(id: $0, appName: "Finder", bundleID: "com.apple.finder", workspace: "A", title: "Folder \($0 - 6)")
        }
        model.previews.layouts = [
            "1": WorkspaceGeometry(placements: [
                WindowPlacement(id: 1, rect: CGRect(x: 0, y: 0, width: 0.495, height: 0.62)),
                WindowPlacement(id: 2, rect: CGRect(x: 0.505, y: 0, width: 0.495, height: 0.62)),
                WindowPlacement(id: 3, rect: CGRect(x: 0, y: 0.63, width: 1, height: 0.37))
            ]),
            "2": WorkspaceGeometry(placements: [
                WindowPlacement(id: 4, rect: CGRect(x: 0, y: 0, width: 1, height: 0.495)),
                WindowPlacement(id: 5, rect: CGRect(x: 0, y: 0.505, width: 1, height: 0.495)),
                WindowPlacement(id: 6, rect: CGRect(x: 0.35, y: 0.3, width: 0.6, height: 0.5), zOrder: 10)
            ]),
            "A": WorkspaceGeometry(placements: [], unplacedWindowIDs: Array(7...19))
        ]
        for window in model.snapshot.windows where window.id <= 6 {
            let renderer = ImageRenderer(content: FixtureWindow(title: window.title, code: window.appName == "Terminal")
                .frame(width: 620, height: window.id == 3 ? 200 : 400))
            model.previews.images[window.id] = renderer.cgImage
        }
        let metrics = SwitcherMetrics(count: model.workspaces.count, availableWidth: 1400, availableHeight: 900)
        for dark in [true, false] {
            try write(SwitcherView(model: model, monitorID: nil, metrics: metrics, useSolidBackground: true),
                      size: CGSize(width: metrics.width, height: metrics.height),
                      to: url.deletingPathExtension().appendingPathExtension("repeated-windows-\(dark ? "dark" : "light").png"), dark: dark)
        }
    }

    static func renderLiveLayout(snapshot: Snapshot, to url: URL) throws {
        let model = AppModel(settings: SettingsStore(inMemory: true))
        model.snapshot = snapshot
        model.previews.updateGeometry(snapshot)
        model.selection.begin(workspaces: model.workspaces, focused: snapshot.focusedWorkspace?.name, order: .workspace, advance: 0)
        let metrics = SwitcherMetrics(count: model.workspaces.count, availableWidth: 1400, availableHeight: 900, extraHeight: 24)
        try write(SwitcherView(model: model, monitorID: nil, metrics: metrics, useSolidBackground: true),
                  size: CGSize(width: metrics.width, height: metrics.height), to: url, dark: true)
    }

    private static func fixtureModel() -> AppModel {
        let model = AppModel(settings: SettingsStore(inMemory: true))
        model.settings.configuration.language = .simplifiedChinese
        model.snapshot = Snapshot(monitors: [Monitor(id: 1, name: "Built-in Display", screenIndex: 1),
                                             Monitor(id: 2, name: "External Display", screenIndex: 2)], workspaces: [
            Workspace(name: "1", monitorID: 1, isVisible: true, isFocused: true, rootLayoutKind: "h_tiles"),
            Workspace(name: "2", monitorID: 1, rootLayoutKind: "h_accordion"), Workspace(name: "3", monitorID: 1),
            Workspace(name: "A", monitorID: 2, isVisible: true, rootLayoutKind: "h_tiles")
        ], windows: [
            WorkspaceWindow(id: 1, appName: "Safari", bundleID: "com.apple.Safari", workspace: "1", title: "AeroSpace · Workspace guide"),
            WorkspaceWindow(id: 2, appName: "Terminal", bundleID: "com.apple.Terminal", workspace: "1", title: "swift build"),
            WorkspaceWindow(id: 3, appName: "Notes", bundleID: "com.apple.Notes", workspace: "2", title: "Reading notes"),
            WorkspaceWindow(id: 4, appName: "Safari", bundleID: "com.apple.Safari", workspace: "2", title: "Design references"),
            WorkspaceWindow(id: 5, appName: "Messages", bundleID: "com.apple.MobileSMS", workspace: "A", title: "Project discussion")
        ])
        model.previews.layouts = [
            "1": WorkspaceGeometry(placements: [WindowPlacement(id: 1, rect: CGRect(x: 0.36, y: 0.03, width: 0.64, height: 0.94)),
                                                 WindowPlacement(id: 2, rect: CGRect(x: 0, y: 0.03, width: 0.35, height: 0.94))]),
            "2": WorkspaceGeometry(placements: [WindowPlacement(id: 3, rect: CGRect(x: 0, y: 0.04, width: 0.58, height: 0.92)),
                                                 WindowPlacement(id: 4, rect: CGRect(x: 0.36, y: 0.15, width: 0.64, height: 0.8), zOrder: 1)], isRemembered: true),
            "A": WorkspaceGeometry(placements: [WindowPlacement(id: 5, rect: CGRect(x: 0.03, y: 0.02, width: 0.94, height: 0.96))])
        ]
        model.keyboardReady = true; model.accessibilityGranted = true; model.screenCaptureGranted = true
        let generation = model.invocation.begin(advance: 0, followsOptionRelease: false)
        _ = model.invocation.markReady(generation: generation)
        model.selection.begin(workspaces: model.workspaces, focused: "1", order: .workspace, advance: 0)
        return model
    }

    private static func write<V: View>(_ content: V, size: CGSize, to url: URL, dark: Bool, language: String = "zh-Hans") throws {
        let view = content.environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: language)).padding(24)
            .background(Color(nsColor: dark ? NSColor(calibratedWhite: 0.08, alpha: 1) : .windowBackgroundColor))
        // Never ordered onto a screen. AppKit-backed scroll views require a real backing window.
        let frame = NSRect(origin: .zero, size: CGSize(width: size.width + 48, height: size.height + 48))
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: view)
        host.frame = frame
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url, options: .atomic)
    }
}

/// Deliberately generic sample content, used only by --render-preview.
private struct FixtureWindow: View {
    let title: String
    let code: Bool
    var chinese = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { ForEach([Color.red, .yellow, .green], id: \.self) { color in Circle().fill(color.opacity(0.8)).frame(width: 9, height: 9) }
                Spacer(); Text(title).font(.system(size: 11)); Spacer() }.padding(12).background(.gray.opacity(0.12))
            if code {
                VStack(alignment: .leading, spacing: 14) {
                    Text("~/aerospace-alt-tab").foregroundStyle(.gray)
                    Text("$ swift build").foregroundStyle(.white)
                    Text("Building for production…\nCompiling AeroTabCore\nCompiling AeroTab\nLinking AeroTab").foregroundStyle(.green)
                    Text("Build complete.").foregroundStyle(.white)
                    Spacer()
                }.font(.system(size: 15, design: .monospaced)).padding(22).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(chinese ? "资料库" : "Library").font(.headline)
                        ForEach(chinese ? ["概览", "工作区", "窗口", "快捷键"] : ["Overview", "Workspaces", "Windows", "Shortcuts"], id: \.self) { Text($0).font(.system(size: 11)) }
                        Spacer()
                    }.padding(18).frame(width: 145).background(.gray.opacity(0.05))
                    VStack(alignment: .leading, spacing: 18) {
                        Text(title).font(.system(size: 25, weight: .semibold))
                        Text(chinese ? "给每个想法，一方空间。" : "A space for every thought.").font(.system(size: 15)).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 8).fill(.blue.opacity(0.12)).frame(height: 100)
                            .overlay(Image(systemName: "macwindow.on.rectangle").font(.system(size: 40)).foregroundStyle(.blue))
                        ForEach(0..<5) { index in RoundedRectangle(cornerRadius: 2).fill(.gray.opacity(0.13)).frame(width: index == 4 ? 120 : nil, height: 6) }
                        Spacer()
                    }.padding(25).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.background(code ? Color(white: 0.07) : .white).foregroundStyle(code ? .white : .black)
    }
}
