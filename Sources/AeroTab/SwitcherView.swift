import SwiftUI
import AeroTabCore

struct SwitcherView: View {
    let model: AppModel
    let monitorID: Int?
    let metrics: SwitcherMetrics
    var useSolidBackground = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var workspaces: [Workspace] { model.workspaces.filter { monitorID == nil || $0.monitorID == monitorID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("AeroTab").font(.system(size: 12, weight: .semibold))
                Text("\(workspaces.count) workspaces").font(.system(size: 10)).foregroundStyle(.secondary)
                if let issue = model.previews.captureIssue {
                    Text("· Previews unavailable").font(.system(size: 10)).foregroundStyle(.secondary).help(issue)
                }
                Spacer(minLength: 8)
                if !model.keyboardReady {
                    Button { model.onSetup?() } label: {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    }.buttonStyle(.plain).help("Keyboard control is not ready: open setup")
                        .accessibilityLabel("Permissions & Setup")
                }
                Button { model.openSettings() } label: {
                    Image(systemName: "gearshape").foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("Settings (⌘,)").accessibilityLabel("Settings")
                Button { model.dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Cancel (Esc)")
            }.padding(.horizontal, 18).padding(.top, 13).padding(.bottom, 10)
            if !model.screenCaptureGranted && model.settings.configuration.capturePreviews {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.dashed")
                    Text("Showing window layouts")
                    Spacer()
                    Button("Enable window previews…") { model.onSetup?() }.buttonStyle(.plain).foregroundStyle(.tint)
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 18).padding(.bottom, 8)
            }
            if let error = model.lastError {
                ContentUnavailableView("Cannot connect to AeroSpace", systemImage: "wifi.exclamationmark", description: Text(error))
            } else if workspaces.isEmpty {
                ContentUnavailableView("No workspaces with windows", systemImage: "macwindow",
                                       description: Text("Empty workspaces are hidden. Open a window and try again."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: metrics.columns), spacing: 12) {
                            ForEach(workspaces) { workspace in
                                WorkspacePreviewCard(model: model, workspace: workspace).id(workspace.name)
                            }
                        }.padding(.horizontal, 16).padding(.vertical, 3)
                    }.scrollIndicators(.automatic)
                        .onChange(of: model.selection.selected) { _, name in
                            guard let name else { return }
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.1)) { proxy.scrollTo(name) }
                        }
                        .onAppear { if let name = model.selection.selected { proxy.scrollTo(name) } }
                }
                if monitorID == nil || model.selectedWorkspace?.monitorID == monitorID {
                    appShortcuts
                } else { Color.clear.frame(height: 30) }
            }
            HStack(spacing: 5) {
                Text("⇥ / ⇧⇥ Select").lineLimit(1)
                Text("· Letter to jump").lineLimit(1)
                Spacer(minLength: 4)
                Text(model.settings.configuration.releaseToCommit ? LocalizedStringKey("Release ⌥ to confirm") : LocalizedStringKey("Space / ↩ Confirm")).lineLimit(1)
                Text("· esc Cancel").lineLimit(1)
            }.font(.system(size: 10)).foregroundStyle(.secondary)
                .padding(.horizontal, 18).padding(.bottom, 11).padding(.top, 5)
        }
        .frame(width: metrics.width, height: metrics.height)
        .background {
            if reduceTransparency || useSolidBackground || !model.settings.configuration.glassBackground {
                RoundedRectangle(cornerRadius: 19).fill(Color(nsColor: .windowBackgroundColor))
            } else {
                RoundedRectangle(cornerRadius: 19).fill(.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 19))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(.primary.opacity(0.12), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 19))
        .environment(\.locale, model.settings.configuration.language.locale)
    }

    private var appShortcuts: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(model.selectedApps.enumerated()), id: \.element.id) { index, app in
                    Button { model.chooseApp(at: index) } label: {
                        HStack(spacing: 4) {
                            Image(nsImage: AppIconCache.shared.icon(for: app)).resizable().frame(width: 18, height: 18)
                            Text(app.name).font(.system(size: 10)).lineLimit(1)
                            if let key = model.appShortcutLabel(at: index) {
                                Text(key).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                            }
                        }
                    }.buttonStyle(.plain)
                        .contextMenu {
                            ForEach(app.windows) { window in
                                Button(window.title.isEmpty ? app.name : window.title) { model.chooseWindow(window.id) }
                            }
                        }
                }
            }.padding(.horizontal, 18)
        }.scrollIndicators(.hidden).frame(height: 30)
    }
}

private struct WorkspacePreviewCard: View {
    let model: AppModel
    let workspace: Workspace
    @State private var hovered = false
    private var selected: Bool { model.selection.selected == workspace.name }
    private var style: WorkspaceStyle { model.settings.configuration.style(for: workspace.name) }
    private var windows: [WorkspaceWindow] {
        model.snapshot.orderedWindows(in: workspace.name, layout: model.previews.layouts[workspace.name])
    }
    private var apps: [WorkspaceApp] {
        model.snapshot.apps(in: workspace.name, layout: model.previews.layouts[workspace.name])
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(workspace.name).font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? style.selectedForeground : style.color)
                    .frame(minWidth: 23).padding(.horizontal, 3).padding(.vertical, 2)
                    .background(selected ? style.color : style.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                if !style.label.isEmpty { Text(style.label).font(.system(size: 11, weight: .medium)).lineLimit(1) }
                Spacer(minLength: 0)
                Text(model.snapshot.monitors.first { $0.id == workspace.monitorID }?.name ?? "")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                if workspace.isVisible {
                    Circle().fill(workspace.isFocused ? style.color : .secondary).frame(width: 5, height: 5)
                }
            }
            WorkspaceMiniature(model: model, workspace: workspace, tint: style.color)
        }
        .padding(8).frame(height: SwitcherMetrics.cardHeight)
        .background(selected ? style.color.opacity(0.12) : .primary.opacity(hovered ? 0.055 : 0.025), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? style.color : .primary.opacity(0.09), lineWidth: selected ? 2 : 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { model.chooseWorkspace(workspace.name) }
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Enter \(workspace.name)") { model.chooseWorkspace(workspace.name) }
            Divider()
            ForEach(windows) { window in
                Button("\(window.appName) · \(window.title)") { model.chooseWindow(window.id) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workspace \(workspace.name), \(windows.count) windows, apps: \(apps.map { L10n.string("\($0.name) \($0.windows.count) windows") + ($0.hasFloatingWindows ? L10n.string(" (includes floating windows)") : "") }.joined(separator: ", "))")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction { model.chooseWorkspace(workspace.name) }
    }
}

struct WorkspaceMiniature: View {
    let model: AppModel
    let workspace: Workspace
    let tint: Color
    private var windows: [WorkspaceWindow] {
        model.snapshot.orderedWindows(in: workspace.name, layout: model.previews.layouts[workspace.name])
    }
    private var layout: WorkspaceGeometry {
        model.previews.layouts[workspace.name] ?? WorkspaceGeometry(placements: [], unplacedWindowIDs: windows.map(\.id))
    }

    var body: some View {
        GeometryReader { proxy in
            let iconLayout = model.snapshot.windowIconLayout(in: workspace.name, layout: layout)
            let canvasWidth = min(proxy.size.width, proxy.size.height * layout.aspectRatio)
            let canvasHeight = canvasWidth / layout.aspectRatio
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.14))
                if layout.placements.isEmpty {
                    unknownWindows
                } else {
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(tint.opacity(0.035))
                        ForEach(layout.placements) { placement in
                            if let window = windows.first(where: { $0.id == placement.id }) {
                                WindowSurface(window: window, image: model.previews.images[window.id], tint: tint)
                                    .frame(width: max(1, placement.rect.width * canvasWidth), height: max(1, placement.rect.height * canvasHeight))
                                    .offset(x: placement.rect.minX * canvasWidth, y: placement.rect.minY * canvasHeight)
                                    .zIndex(Double(placement.zOrder))
                            }
                        }
                    }.frame(width: canvasWidth, height: canvasHeight).clipped()
                }
            }.frame(width: proxy.size.width, height: proxy.size.height)
                // One workspace inventory, above the entire window stack, inside the preview.
                .overlay(alignment: .bottomLeading) {
                    WorkspaceWindowIcons(groups: iconLayout.groups,
                                      availableWidth: max(20, proxy.size.width - 10 - (iconLayout.rootAxis == nil ? 0 : 30)))
                        .padding(5)
                }
                .overlay(alignment: .bottomTrailing) {
                    if let axis = iconLayout.rootAxis {
                        Image(systemName: axis == .horizontal ? "arrow.left.and.right" : "arrow.up.and.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary).frame(width: 24, height: 24)
                            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                            .help(axis == .horizontal ? LocalizedStringKey("Outer layout: horizontal; lines mark subgroups") : LocalizedStringKey("Outer layout: vertical; lines mark subgroups"))
                            .accessibilityLabel(axis == .horizontal ? LocalizedStringKey("Horizontal outer layout") : LocalizedStringKey("Vertical outer layout"))
                            .padding(5)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let status = layoutStatus {
                        Text(status).font(.system(size: 8)).foregroundStyle(.secondary).padding(3)
                            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 3))
                            .padding(4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var layoutStatus: LocalizedStringKey? {
        if windows.isEmpty { return nil }
        if layout.placements.isEmpty { return "Layout not recorded" }
        if !layout.unplacedWindowIDs.isEmpty { return "\(layout.unplacedWindowIDs.count) window positions not recorded" }
        return layout.isRemembered ? "Last layout" : nil
    }

    private var unknownWindows: some View {
        Group {
            if windows.isEmpty {
                Text("No windows").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(windows.prefix(4))) { window in
                        WindowSurface(window: window, image: model.previews.images[window.id], tint: tint)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }.padding(5)
    }
}

private struct WindowSurface: View {
    let window: WorkspaceWindow
    let image: CGImage?
    let tint: Color
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Rectangle().fill(Color(nsColor: .controlBackgroundColor))
                    Rectangle().fill(tint.opacity(0.06))
                    if proxy.size.width > 24 && proxy.size.height > 26 {
                        VStack(spacing: 3) {
                            Text(window.appName).font(.system(size: 9, weight: .medium)).lineLimit(1)
                            if proxy.size.width > 70 {
                                if proxy.size.height > 75 && !window.title.isEmpty && window.title != window.appName {
                                    Text(window.title).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }.padding(4)
                    }
                }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
                .overlay(alignment: .top) {
                    if image == nil { Rectangle().fill(.primary.opacity(0.06)).frame(height: min(9, proxy.size.height)) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.35), lineWidth: 0.65))
                .help("\(window.appName) · \(window.title)")
        }
    }
}
