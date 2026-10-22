import AppKit
import Observation
import AeroTabCore

@MainActor @Observable
final class SettingsStore {
    var configuration: Configuration {
        didSet {
            if configuration.language != oldValue.language {
                L10n.language = configuration.language
                onLanguageChange?()
            }
            save()
        }
    }
    var error: String?
    let url: URL
    @ObservationIgnored private let inMemory: Bool
    @ObservationIgnored var onLanguageChange: (() -> Void)?

    init(url: URL = SettingsStore.defaultURL, inMemory: Bool = false) {
        self.url = url
        self.inMemory = inMemory
        var initial = Configuration()
        if !FileManager.default.isExecutableFile(atPath: initial.aerospacePath),
           FileManager.default.isExecutableFile(atPath: "/usr/local/bin/aerospace") {
            initial.aerospacePath = "/usr/local/bin/aerospace"
        }
        do {
            if !inMemory && FileManager.default.fileExists(atPath: url.path) {
                initial = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
            }
        } catch {
            self.error = L10n.string("Could not read settings; using defaults: \(error.localizedDescription)")
        }
        configuration = initial
        L10n.language = initial.language
    }

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AeroTab/settings.json")
    }

    func save() {
        guard !inMemory else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: url, options: .atomic)
            error = nil
        } catch { self.error = L10n.string("Could not save settings: \(error.localizedDescription)") }
    }
}
