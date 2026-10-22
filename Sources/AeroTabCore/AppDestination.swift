import Foundation

public enum AppDestination: Equatable, Sendable {
    case switcher, settings

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "aerotab", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return nil }
        switch url.host?.lowercased() {
        case "show": self = .switcher
        case "settings": self = .settings
        default: return nil
        }
    }
}
