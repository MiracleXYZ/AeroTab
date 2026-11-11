import Foundation
import Testing
@testable import AeroTabCore

@Suite("Accordion subgroups in workspace icons")
struct AccordionIconLayoutTests {
    private indirect enum Tree {
        case window(Int)
        case container(String, [Tree])

    }

    /// Synthetic AeroSpace observations, generated from a known tree. Accordion
    /// children share the cross-axis extent and expose only narrow edge strips.
    private func fixture(_ tree: Tree, padding: CGFloat = 0.025) -> (Snapshot, WorkspaceGeometry) {
        var windows: [WorkspaceWindow] = []
        var placements: [WindowPlacement] = []
        func visit(_ node: Tree, rect: CGRect, parent: String? = nil) {
            switch node {
            case .window(let id):
                windows.append(.init(id: id, appName: "Finder", bundleID: "com.apple.finder", workspace: "T", layoutKind: parent))
                placements.append(.init(id: id, rect: rect))
            case .container(let kind, let children):
                let horizontal = kind.hasPrefix("h_")
                let length = horizontal ? rect.width : rect.height
                for (index, child) in children.enumerated() {
                    var frame = rect
                    let start: CGFloat, size: CGFloat
                    if kind.hasSuffix("_tiles") {
                        size = (length - 0.01 * CGFloat(children.count - 1)) / CGFloat(children.count)
                        start = CGFloat(index) * (size + 0.01)
                    } else {
                        let before = index == 0 ? 0 : padding
                        let after = index == children.count - 1 ? 0 : padding
                        start = before; size = length - before - after
                    }
                    if horizontal { frame.origin.x += start; frame.size.width = size }
                    else { frame.origin.y += start; frame.size.height = size }
                    visit(child, rect: frame, parent: kind)
                }
            }
        }
        visit(tree, rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard case .container(let root, _) = tree else { fatalError("Fixture needs a root") }
        return (Snapshot(monitors: [], workspaces: [.init(name: "T", monitorID: 1, rootLayoutKind: root)], windows: windows.reversed()),
                WorkspaceGeometry(placements: placements.reversed()))
    }

    private let kinds = ["h_tiles", "v_tiles", "h_accordion", "v_accordion"]

    @Test("Every root/child orientation and mode uses the same subgroup notation")
    func allRootAndChildModes() {
        for root in kinds {
            for child in kinds where child != root {
                let (data, geometry) = fixture(.container(root, [.container(child, [.window(1), .window(2)]), .window(3)]))
                for remembered in [false, true] {
                    var layout = geometry; layout.isRemembered = remembered
                    let result = data.windowIconLayout(in: "T", layout: layout)
                    #expect(result.groups.map { $0.windows.map(\.id) } == [[1, 2], [3]], "\(root) / \(child)")
                    #expect(result.groups.map(\.subgroupAxis) == [LayoutAxis(layoutKind: child), nil])
                    #expect(result.rootAxis == LayoutAxis(layoutKind: root))
                    #expect(result.groups.flatMap(\.windows) == data.orderedWindows(in: "T", layout: layout))
                }
            }
        }
    }

    @Test("Multiple accordion or split subgroups remain separate, including accordion roots")
    func multipleSubgroups() {
        for root in kinds {
            for child in kinds where LayoutAxis(layoutKind: child) != LayoutAxis(layoutKind: root) {
                let (data, layout) = fixture(.container(root, [
                    .container(child, [.window(1), .window(2)]),
                    .container(child, [.window(3), .window(4)]), .window(5)
                ]))
                let result = data.windowIconLayout(in: "T", layout: layout)
                #expect(result.groups.map { $0.windows.map(\.id) } == [[1, 2], [3, 4], [5]], "\(root) / \(child)")
                #expect(result.groups.map(\.isSubgroup) == [true, true, false])
                #expect(result.groups.flatMap(\.windows) == data.orderedWindows(in: "T", layout: layout))
            }
        }
    }

    @Test("Three mixed levels keep the entire outer child under one line")
    func mixedNesting() {
        for root in kinds {
            for child in kinds where LayoutAxis(layoutKind: child) != LayoutAxis(layoutKind: root) {
                for grandchild in kinds where LayoutAxis(layoutKind: grandchild) == LayoutAxis(layoutKind: root) {
                    let (data, layout) = fixture(.container(root, [
                        .container(child, [.window(1), .container(grandchild, [.window(2), .window(3)])]), .window(4)
                    ]))
                    let result = data.windowIconLayout(in: "T", layout: layout)
                    #expect(result.groups.map { $0.windows.map(\.id) } == [[1, 2, 3], [4]], "\(root) / \(child) / \(grandchild)")
                    #expect(result.groups.map(\.isSubgroup) == [true, false])
                    #expect(result.groups.flatMap(\.windows) == data.orderedWindows(in: "T", layout: layout))
                }
            }
        }
    }

    @Test("Containers without direct window children and uneven nesting preserve their outer groups")
    func containersOnlyAndUnevenNesting() {
        for root in kinds {
            for child in kinds where LayoutAxis(layoutKind: child) != LayoutAxis(layoutKind: root) {
                for inner in kinds where LayoutAxis(layoutKind: inner) == LayoutAxis(layoutKind: root) {
                    let (data, layout) = fixture(.container(root, [
                        .container(child, [.window(1), .window(2)]), .window(3),
                        .container(child, [.container(inner, [.window(4), .window(5)]),
                                           .container(inner, [.window(6), .window(7)])])
                    ]))
                    let result = data.windowIconLayout(in: "T", layout: layout)
                    #expect(result.groups.map { $0.windows.map(\.id) } == [[1, 2], [3], [4, 5, 6, 7]], "\(root) / \(child) / \(inner)")
                    #expect(result.groups.map(\.isSubgroup) == [true, false, true])
                    #expect(result.groups.flatMap(\.windows) == data.orderedWindows(in: "T", layout: layout))
                }
            }
        }
    }

    @Test("Indistinguishable zero-padding containers retain every repeated icon without guessed lines")
    func indistinguishableContainers() {
        for root in ["h_accordion", "v_accordion"] {
            let child = root == "h_accordion" ? "v_accordion" : "h_accordion"
            for hasDirectWindow in [false, true] {
                var children: [Tree] = [.container(child, [.window(1), .window(2)]), .container(child, [.window(3), .window(4)])]
                if hasDirectWindow { children.append(.window(5)) }
                let (data, layout) = fixture(.container(root, children), padding: 0)
                let result = data.windowIconLayout(in: "T", layout: layout)
                #expect(result.groups.allSatisfy { !$0.isSubgroup })
                #expect(result.groups.flatMap(\.windows).map(\.id).sorted() == data.windows.map(\.id).sorted())
                #expect(result.rootAxis == LayoutAxis(layoutKind: root))
            }
        }
    }

    private func snapshot(root: String, child: String?) -> Snapshot {
        Snapshot(monitors: [], workspaces: [.init(name: "T", monitorID: 1, rootLayoutKind: root)], windows: [
            .init(id: 1, appName: "Finder", bundleID: "com.apple.finder", workspace: "T", layoutKind: child),
            .init(id: 2, appName: "Finder", bundleID: "com.apple.finder", workspace: "T", layoutKind: child),
            .init(id: 3, appName: "Terminal", bundleID: "com.apple.Terminal", workspace: "T", layoutKind: root)
        ])
    }

    private func geometry(root: LayoutAxis, child: LayoutAxis, offset: Double = 0.02) -> WorkspaceGeometry {
        let a = CGRect(x: 0, y: 0, width: root == .horizontal ? 0.48 : 1, height: root == .vertical ? 0.48 : 1)
        let b = child == .horizontal
            ? CGRect(x: offset, y: 0, width: a.width - offset, height: a.height)
            : CGRect(x: 0, y: offset, width: a.width, height: a.height - offset)
        let c = root == .horizontal
            ? CGRect(x: 0.52, y: 0, width: 0.48, height: 1)
            : CGRect(x: 0, y: 0.52, width: 1, height: 0.48)
        return .init(placements: [.init(id: 1, rect: a), .init(id: 2, rect: b), .init(id: 3, rect: c)])
    }

    @Test("Two overlapping accordion windows beside another window share one overline, in both orientations")
    func nestedAccordion() {
        for root in ["h_tiles", "v_tiles"] {
            for child in ["h_accordion", "v_accordion"] {
                let rootAxis = LayoutAxis(layoutKind: root)!
                let childAxis = LayoutAxis(layoutKind: child)!
                for offset in [0.0, 0.02] {
                    var data = snapshot(root: root, child: child)
                    // Neither CLI order nor frontmost-window changes should remove the group.
                    data.windows.reverse()
                    var layout = geometry(root: rootAxis, child: childAxis, offset: offset)
                    for remembered in [false, true] {
                        layout.isRemembered = remembered
                        let result = data.windowIconLayout(in: "T", layout: layout)
                        #expect(result.rootAxis == rootAxis)
                        #expect(result.groups.map { $0.windows.map(\.id) } == [[1, 2], [3]])
                        #expect(result.groups.map(\.subgroupAxis) == [childAxis, nil])
                        #expect(result.groups.flatMap(\.windows) == data.orderedWindows(in: "T", layout: layout))
                    }
                }
            }
        }
    }

    @Test("Overlap alone cannot imply an accordion subgroup, and incomplete geometry stays ungrouped")
    func ambiguousOverlap() {
        let layout = geometry(root: .horizontal, child: .vertical)
        for child: String? in [nil, "v_tiles", "future_layout"] {
            #expect(snapshot(root: "h_tiles", child: child).windowIconGroups(in: "T", layout: layout).allSatisfy { !$0.isSubgroup })
        }
        var data = snapshot(root: "h_tiles", child: "v_accordion")
        data.windows[1].layoutKind = "h_accordion"
        #expect(data.windowIconGroups(in: "T", layout: layout).allSatisfy { !$0.isSubgroup })
        data.windows[1].layoutKind = "v_accordion"
        let partial = WorkspaceGeometry(placements: Array(layout.placements.dropFirst()), unplacedWindowIDs: [1])
        #expect(data.windowIconGroups(in: "T", layout: partial).allSatisfy { !$0.isSubgroup })
    }

    @Test("A workspace containing only a root accordion does not gain a subgroup line")
    func rootAccordion() {
        for kind in ["h_accordion", "v_accordion"] {
            let data = snapshot(root: kind, child: kind)
            let layout = WorkspaceGeometry(placements: (1...3).map {
                WindowPlacement(id: $0, rect: CGRect(x: 0, y: 0, width: 1, height: 1))
            })
            let result = data.windowIconLayout(in: "T", layout: layout)
            #expect(result.rootAxis == LayoutAxis(layoutKind: kind))
            #expect(result.groups.count == 3)
            #expect(result.groups.allSatisfy { !$0.isSubgroup })
        }
    }

    @Test("Floating windows remain separate after an accordion subgroup")
    func floatingWindow() {
        var data = snapshot(root: "h_tiles", child: "v_accordion")
        data.windows.append(.init(id: 4, appName: "Finder", bundleID: "com.apple.finder", workspace: "T", layoutKind: "floating"))
        var layout = geometry(root: .horizontal, child: .vertical)
        layout.placements.append(.init(id: 4, rect: CGRect(x: 0, y: 0, width: 1, height: 1)))
        let groups = data.windowIconGroups(in: "T", layout: layout)
        #expect(groups.map { $0.windows.map(\.id) } == [[1, 2], [3], [4]])
        #expect(groups.map(\.isSubgroup) == [true, false, false])
        #expect(groups.last?.windows.first?.isFloating == true)
    }
}
