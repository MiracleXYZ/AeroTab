import SwiftUI
import AeroTabCore

struct WorkspaceColorControls: View {
    @Binding var style: WorkspaceStyle
    @State private var hexDraft = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                ForEach(WorkspaceTint.allCases, id: \.self) { tint in
                    Button {
                        hexDraft = ""; error = nil
                        var updated = style
                        updated.tint = tint; updated.customColorHex = nil
                        style = updated
                    } label: {
                        Circle().fill(tint.color).frame(width: 20, height: 20)
                            .overlay {
                                if style.customColor == nil && style.tint == tint {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                }
                            }
                    }.buttonStyle(.plain).help(tint.title).accessibilityLabel(tint.title)
                }
                Spacer(minLength: 6)
                ColorPicker("Custom color", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden().help("Choose a custom color").fixedSize()
                TextField("#RRGGBB", text: $hexDraft)
                    .font(.system(size: 11, design: .monospaced)).frame(width: 82)
                    .accessibilityLabel("Custom HEX color")
                    .help("Enter #RGB or #RRGGBB, then press Return or Apply")
                    .onSubmit { applyHex() }
                    .onChange(of: hexDraft) { _, _ in error = nil }
                Button("Apply") { applyHex() }.controlSize(.small)
                    .disabled(hexDraft == (style.customColor?.hex ?? ""))
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onAppear { hexDraft = style.customColor?.hex ?? "" }
        .onChange(of: style.customColorHex) { _, _ in hexDraft = style.customColor?.hex ?? ""; error = nil }
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { style.color }, set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            func byte(_ component: CGFloat) -> Int { Int((min(1, max(0, component)) * 255).rounded()) }
            let hex = String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
            hexDraft = hex; error = nil
            style.customColorHex = hex
        })
    }

    private func applyHex() {
        if hexDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            style.customColorHex = nil; hexDraft = ""; error = nil
        } else if let color = HexColor(hexDraft) {
            style.customColorHex = color.hex; hexDraft = color.hex; error = nil
        } else {
            error = L10n.string("Enter #RGB or #RRGGBB, for example #A78BFA.")
        }
    }
}
