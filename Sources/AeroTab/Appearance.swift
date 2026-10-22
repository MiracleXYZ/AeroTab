import SwiftUI
import AeroTabCore

extension WorkspaceWindow {
    var appIdentity: WorkspaceApp {
        WorkspaceApp(id: bundleID.isEmpty ? "pid:\(pid):\(appName)" : bundleID,
                     name: appName, bundleID: bundleID, pid: pid, windows: [self])
    }
}

extension WorkspaceTint {
    var color: Color {
        switch self {
        case .coral: Color(red: 1, green: 0.39, blue: 0.38)
        case .violet: Color(red: 0.66, green: 0.48, blue: 1)
        case .blue: Color(red: 0.30, green: 0.61, blue: 1)
        case .mint: Color(red: 0.27, green: 0.79, blue: 0.62)
        case .amber: Color(red: 1, green: 0.72, blue: 0.28)
        case .pink: Color(red: 0.96, green: 0.44, blue: 0.73)
        case .cyan: Color(red: 0.22, green: 0.77, blue: 0.86)
        case .graphite: Color(red: 0.62, green: 0.67, blue: 0.75)
        }
    }
    var title: String {
        switch self {
        case .coral: L10n.string("Coral")
        case .violet: L10n.string("Violet")
        case .blue: L10n.string("Blue")
        case .mint: L10n.string("Mint")
        case .amber: L10n.string("Amber")
        case .pink: L10n.string("Pink")
        case .cyan: L10n.string("Cyan")
        case .graphite: L10n.string("Graphite")
        }
    }
}

extension WorkspaceStyle {
    var color: Color {
        if let customColor { return Color(.sRGB, red: customColor.red, green: customColor.green, blue: customColor.blue) }
        return tint.color
    }
    var selectedForeground: Color {
        customColor?.prefersDarkForeground == true ? .black : .white
    }
}

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private var icons: [String: NSImage] = [:]
    func icon(for app: WorkspaceApp) -> NSImage {
        if let cached = icons[app.id] { return cached }
        let icon: NSImage
        if let running = NSRunningApplication(processIdentifier: app.pid), let image = running.icon {
            icon = image
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: app.name)!
        }
        icons[app.id] = icon
        return icon
    }
}

struct Keycap: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.primary.opacity(0.09), lineWidth: 0.5))
    }
}
