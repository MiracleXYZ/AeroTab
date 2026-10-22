import SwiftUI
import AeroTabCore

/// A single compact inventory anchored to the preview, never to individual windows.
struct WorkspaceWindowIcons: View {
    let groups: [WindowIconGroup]
    let availableWidth: CGFloat

    private struct Item {
        let window: WorkspaceWindow
        let group: Int
        let subgroup: Bool
        var floating: Bool { window.isFloating }
    }
    private var items: [Item] {
        groups.enumerated().flatMap { index, group in
            group.windows.map { Item(window: $0, group: index, subgroup: group.isSubgroup) }
        }
    }

    var body: some View {
        let items = items
        let hasMarkers = items.contains { $0.subgroup || $0.floating }
        let columns = max(1, min(items.count, Int((max(20, availableWidth - 8) + 4) / 24)))
        if !items.isEmpty {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(20), spacing: 4), count: columns), spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.element.window.id) { index, item in
                    let joinsLeft = index % columns > 0 && items[index - 1].group == item.group
                    let joinsRight = index % columns < columns - 1 && index + 1 < items.count && items[index + 1].group == item.group
                    Image(nsImage: AppIconCache.shared.icon(for: item.window.appIdentity)).resizable().frame(width: 20, height: 20)
                        .padding(.top, hasMarkers ? 6 : 0)
                        .overlay(alignment: .top) {
                            if item.floating {
                                Circle().fill(.primary.opacity(0.85)).frame(width: 3, height: 3).offset(y: 0.5)
                            } else if item.subgroup {
                                Rectangle().fill(.primary.opacity(0.75))
                                    .frame(width: 20 + (joinsLeft ? 2 : 0) + (joinsRight ? 2 : 0), height: 1.5)
                                    .offset(x: (joinsRight ? 1 : 0) - (joinsLeft ? 1 : 0), y: 1)
                            }
                        }
                        .help(item.window.appName + (item.window.title.isEmpty ? "" : " · \(item.window.title)") +
                              (item.floating ? L10n.string(" (floating window)") : item.subgroup ? L10n.string(" (layout subgroup)") : ""))
                }
            }.frame(width: CGFloat(columns * 24 - 4)).padding(4)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
        }
    }
}
