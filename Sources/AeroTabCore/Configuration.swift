import Foundation

public enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case perMonitor, allOnActiveMonitor
}

public enum CycleOrder: String, Codable, CaseIterable, Sendable {
    case recent, workspace
}

public enum WorkspaceOrderSource: String, Codable, CaseIterable, Sendable {
    case aerospace, custom
}

public enum WorkspaceTint: String, Codable, CaseIterable, Sendable {
    case coral, violet, blue, mint, amber, pink, cyan, graphite
}

public struct WorkspaceStyle: Codable, Equatable, Sendable {
    public var label: String
    public var symbol: String
    public var tint: WorkspaceTint
    /// Optional override; older settings without this key keep their preset color.
    public var customColorHex: String?
    /// Empty means use a one-character workspace name as the shortcut.
    public var shortcut: String

    public init(label: String = "", symbol: String = "square.stack.3d.up", tint: WorkspaceTint = .blue, shortcut: String = "", customColorHex: String? = nil) {
        self.label = label; self.symbol = symbol; self.tint = tint; self.shortcut = shortcut
        self.customColorHex = customColorHex.flatMap { HexColor($0)?.hex }
    }

    public var customColor: HexColor? { customColorHex.flatMap(HexColor.init) }
}

public struct Configuration: Codable, Equatable, Sendable {
    public var language: AppLanguage = .system
    public var displayMode: DisplayMode = .allOnActiveMonitor
    public var cycleOrder: CycleOrder = .workspace
    public var workspaceOrderSource: WorkspaceOrderSource = .aerospace
    public var customWorkspaceOrder: [String] = []
    public var glassBackground = false
    public var showEmptyWorkspaces = false
    public var capturePreviews = true
    public var onboardingCompleted = false
    public var schemaVersion = 3
    public var releaseToCommit = false
    public var captureOptionTab = true
    public var appShortcuts: [String] = AppShortcut.functionKeys
    public var aerospacePath = "/opt/homebrew/bin/aerospace"
    public var styles: [String: WorkspaceStyle] = [:]

    public init() {}

    // Allow older configuration files to gain new options without being discarded.
    enum CodingKeys: String, CodingKey {
        case language
        case displayMode, cycleOrder, showEmptyWorkspaces, releaseToCommit, captureOptionTab, aerospacePath, styles
        case capturePreviews, onboardingCompleted, schemaVersion
        case workspaceOrderSource, customWorkspaceOrder, glassBackground, appShortcuts
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        displayMode = try c.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? displayMode
        let oldSchema = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        // Earlier versions defaulted to MRU. Adopt the new fixed order once on upgrade.
        cycleOrder = oldSchema < 3 ? .workspace : (try c.decodeIfPresent(CycleOrder.self, forKey: .cycleOrder) ?? cycleOrder)
        workspaceOrderSource = try c.decodeIfPresent(WorkspaceOrderSource.self, forKey: .workspaceOrderSource) ?? workspaceOrderSource
        customWorkspaceOrder = try c.decodeIfPresent([String].self, forKey: .customWorkspaceOrder) ?? []
        glassBackground = try c.decodeIfPresent(Bool.self, forKey: .glassBackground) ?? false
        // Version 1 shipped with empty workspaces enabled. Adopt the corrected default on upgrade.
        showEmptyWorkspaces = oldSchema < 2 ? false : (try c.decodeIfPresent(Bool.self, forKey: .showEmptyWorkspaces) ?? false)
        capturePreviews = try c.decodeIfPresent(Bool.self, forKey: .capturePreviews) ?? capturePreviews
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        releaseToCommit = try c.decodeIfPresent(Bool.self, forKey: .releaseToCommit) ?? releaseToCommit
        captureOptionTab = try c.decodeIfPresent(Bool.self, forKey: .captureOptionTab) ?? captureOptionTab
        appShortcuts = try c.decodeIfPresent([String].self, forKey: .appShortcuts) ?? appShortcuts
        aerospacePath = try c.decodeIfPresent(String.self, forKey: .aerospacePath) ?? aerospacePath
        styles = try c.decodeIfPresent([String: WorkspaceStyle].self, forKey: .styles) ?? styles
    }

    public func style(for workspace: String) -> WorkspaceStyle {
        if let custom = styles[workspace] { return custom }
        let palette = WorkspaceTint.allCases
        // Stable across launches; Swift's Hasher is intentionally randomized.
        let seed = workspace.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0x7fffffff }
        let index = Int(workspace).map { max(0, $0 - 1) % palette.count } ?? seed % palette.count
        return WorkspaceStyle(tint: palette[index])
    }

    public func shortcut(for workspace: String) -> String? {
        let custom = style(for: workspace).shortcut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = custom.isEmpty ? workspace.lowercased() : custom
        guard value.count == 1, value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else { return nil }
        return value
    }

    /// Ambiguous shortcuts are disabled instead of choosing an arbitrary workspace.
    public func shortcuts(for workspaces: [Workspace]) -> [String: String] {
        let pairs = workspaces.compactMap { w in shortcut(for: w.name).map { ($0, w.name) } }
        return Dictionary(grouping: pairs, by: { $0.0 }).compactMapValues { $0.count == 1 ? $0[0].1 : nil }
    }

    /// Keep slot numbers stable. Invalid, duplicate and workspace-reserved keys have no app binding.
    public func appShortcutBindings(for workspaces: [Workspace]) -> [String: Int] {
        let reserved = Set(workspaces.compactMap { shortcut(for: $0.name) })
        let pairs = appShortcuts.prefix(12).enumerated().compactMap { index, value in
            AppShortcut.normalize(value).map { ($0, index) }
        }
        return Dictionary(grouping: pairs, by: { $0.0 }).compactMapValues { values in
            values.count == 1 && !reserved.contains(values[0].0) ? values[0].1 : nil
        }
    }
}
