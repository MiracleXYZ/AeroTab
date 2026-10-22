import SwiftUI
import AeroTabCore

struct SetupView: View {
    let model: AppModel
    var requestAccessibility: () -> Void
    var requestScreenCapture: () -> Void
    var recheck: () -> Void
    var finish: () -> Void
    var later: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up AeroTab").font(.system(size: 25, weight: .semibold))
                Text("Grant access, then use ⌥Tab to view and switch workspaces.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            permissionCard(number: "1", title: "Accessibility", detail: "Required · Keyboard control", granted: model.keyboardReady) {
                Text("Allow AeroTab to receive ⌥Tab and workspace selection keys. Keyboard control needs this permission.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(model.accessibilityGranted ? LocalizedStringKey("Open permission settings") : LocalizedStringKey("Open Accessibility settings…"), action: requestAccessibility)
                        .buttonStyle(.borderedProminent)
                    Button("Recheck", action: recheck)
                }
                if let issue = model.keyboardIssue { Text(issue).foregroundStyle(.orange) }
                else if model.shortcutTestSucceeded {
                    Label("⌥Tab received — shortcut is working", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else if model.keyboardReady {
                    Text("Keyboard listener connected. Press ⌥Tab here to test it.")
                }
                Text("Enable AeroTab in System Settings. If it is missing, click ＋ to add the app.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            permissionCard(number: "2", title: "Screen Recording", detail: "Window-content previews", granted: model.screenCaptureGranted) {
                Text("Show window-content thumbnails. Without permission, you can still switch using app icons and known window positions.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(model.screenCaptureGranted ? LocalizedStringKey("View Screen Recording permission") : LocalizedStringKey("Enable window previews…"), action: requestScreenCapture)
                    if !model.screenCaptureGranted { Text("Optional").foregroundStyle(.secondary) }
                }
                Text("Previews stay in local memory and clear on close. Quit and reopen AeroTab if macOS asks you to.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Reveal app in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                    .buttonStyle(.link)
                Spacer()
                Button("Later", action: later)
                Button("Get started", action: finish).buttonStyle(.borderedProminent).disabled(!model.keyboardReady)
            }
        }.padding(26).frame(width: 570)
            .environment(\.locale, model.settings.configuration.language.locale)
    }

    private func permissionCard<Content: View>(number: String, title: String, detail: String, granted: Bool,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Text(number).font(.system(size: 11, weight: .bold)).frame(width: 22, height: 22)
                    .background(.primary.opacity(0.07), in: Circle())
                Text(LocalizedStringKey(title)).font(.system(size: 14, weight: .semibold))
                Text(LocalizedStringKey(detail)).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Label(granted ? LocalizedStringKey("Ready") : LocalizedStringKey("Not enabled"), systemImage: granted ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 11)).foregroundStyle(granted ? Color.green : .secondary)
            }
            content().font(.system(size: 12))
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
    }
}
