import Foundation
import Synchronization

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system, english = "en", simplifiedChinese = "zh-Hans"

    public var identifier: String {
        if self != .system { return rawValue }
        return Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: Locale.preferredLanguages).first ?? "en"
    }

    public var locale: Locale { Locale(identifier: identifier) }
}

/// Shared by AppKit and background CLI errors. SwiftUI uses the same language via its locale environment.
public enum L10n {
    private static let selection = Mutex(AppLanguage.system)

    public static var language: AppLanguage {
        get { selection.withLock { $0 } }
        set { selection.withLock { $0 = newValue } }
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        guard let path = Bundle.main.path(forResource: language.identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    public static func string(_ value: String.LocalizationValue) -> String {
        let language = language
        return String(localized: value, bundle: bundle(for: language), locale: language.locale)
    }

    public static func key(_ key: String) -> String {
        bundle(for: language).localizedString(forKey: key, value: key, table: nil)
    }
}
