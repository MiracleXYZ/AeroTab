import SwiftUI
import AeroTabCore

struct AppShortcutSettings: View {
    let model: AppModel
    @Bindable var store: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("App shortcuts").font(.title2.bold())
            Text("Keys follow the app row at the bottom of the switcher. Active only while it is open. Changes save automatically.")
                .font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 14) {
                ForEach(0..<12) { index in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("App \(index + 1)").font(.caption).foregroundStyle(.secondary)
                        TextField("None", text: binding(at: index))
                            .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                            .multilineTextAlignment(.center).accessibilityLabel("App \(index + 1) shortcut")
                        Text(issue(at: index) ?? " ").font(.system(size: 10)).foregroundStyle(.orange)
                            .lineLimit(2).frame(height: 28, alignment: .topLeading)
                    }
                }
            }.padding(14).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text("Enter F1–F12, a letter, digit, or punctuation. Leave blank to disable that app’s shortcut.")
                Text("Duplicate or invalid keys are disabled. Workspace keys take priority; choose another app key if needed.")
            }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 570)
            .environment(\.locale, store.configuration.language.locale)
    }

    private func value(at index: Int) -> String {
        store.configuration.appShortcuts.indices.contains(index) ? store.configuration.appShortcuts[index] : ""
    }

    private func binding(at index: Int) -> Binding<String> {
        Binding(get: { value(at: index).uppercased() }, set: { value in
            var keys = Array(store.configuration.appShortcuts.prefix(12))
            while keys.count < 12 { keys.append("") }
            keys[index] = value
            store.configuration.appShortcuts = keys
        })
    }

    private func issue(at index: Int) -> String? {
        let value = value(at: index).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard let key = AppShortcut.normalize(value) else { return L10n.string("Invalid key") }
        let workspaces = model.snapshot.workspaces.filter { store.configuration.shortcut(for: $0.name) == key }
        if !workspaces.isEmpty { return L10n.string("Workspace key conflict: \(workspaces.map(\.name).joined(separator: "/"))") }
        if store.configuration.appShortcuts.prefix(12).filter({ AppShortcut.normalize($0) == key }).count > 1 { return L10n.string("Duplicate key") }
        return nil
    }
}
