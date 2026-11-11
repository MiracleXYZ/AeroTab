import Foundation

/// A conservative reconstruction from window rectangles and the CLI's parent-layout hints.
/// AeroSpace does not expose container IDs: indistinguishable/contradictory regions must
/// fall back to ungrouped icons, rather than treating overlap as a missing window.
struct InferredWindowLayout {
    struct Node {
        var windows: [WorkspaceWindow]
        var rect: CGRect
        var kind: String?
        var parentHint: String?
        var children: [Node] = []
    }
    var children: [Node]
    var windows: [WorkspaceWindow] { children.flatMap(\.windows) }

    private static let kinds = ["h_tiles", "v_tiles", "h_accordion", "v_accordion"]
    private static let tolerance: CGFloat = 0.002

    static func supports(_ windows: [WorkspaceWindow], root: String?) -> Bool {
        guard let root, kinds.contains(root) else { return false }
        return windows.allSatisfy { kinds.contains($0.layoutKind ?? "") }
    }

    static func infer(_ windows: [WorkspaceWindow], placements: [Int: WindowPlacement], root: String?) -> Self? {
        guard supports(windows, root: root), let root, windows.count > 1,
              windows.count <= 64, windows.allSatisfy({ placements[$0.id] != nil }) else { return nil }
        var nodes = windows.map {
            Node(windows: [$0], rect: placements[$0.id]!.rect, parentHint: $0.layoutKind)
        }
        guard nodes.allSatisfy({ $0.rect.minX.isFinite && $0.rect.minY.isFinite &&
            $0.rect.width.isFinite && $0.rect.height.isFinite && $0.rect.width > 0 && $0.rect.height > 0
        }) else { return nil }

        // Each pass removes at least one node. Both layout modes use the same
        // bottom-up grouping; only the interval relationship differs.
        while nodes.count > 1 {
            if compatible(nodes, kind: root) {
                // Same-kind intermediate merges do not establish a distinct subgroup,
                // but their differently oriented/modeled descendants still do.
                func rootChildren(_ node: Node) -> [Node] {
                    node.kind == root ? node.children.flatMap(rootChildren) : [node]
                }
                return Self(children: sorted(nodes, kind: root).flatMap(rootChildren))
            }
            struct Candidate { var indices: Set<Int>; var kind: String; var rect: CGRect }
            var candidates: [Candidate] = []
            for kind in kinds {
                let axis = LayoutAxis(layoutKind: kind)!
                let eligible = nodes.indices.filter { nodes[$0].parentHint == nil || nodes[$0].parentHint == kind }
                // Cross-axis bounds distinguish containers even when their children
                // overlap along the accordion's axis. Do not cluster by z-order.
                var seen: Set<Set<Int>> = []
                for index in eligible {
                    let indices = Set(eligible.filter { sameSpan(nodes[index].rect, nodes[$0].rect, axis: axis.opposite) })
                    guard indices.count > 1, indices.count < nodes.count, seen.insert(indices).inserted else { continue }
                    let group = indices.sorted().map { nodes[$0] }
                    guard compatible(group, kind: kind) else { continue }
                    let rect = group.dropFirst().reduce(group[0].rect) { $0.union($1.rect) }
                    // With identical outer bounds, two hidden containers can have
                    // exactly the same observations as one. Never combine them by guesswork.
                    guard !nodes.indices.contains(where: { !indices.contains($0) &&
                        sameSpan(rect, nodes[$0].rect, axis: .horizontal) &&
                        sameSpan(rect, nodes[$0].rect, axis: .vertical)
                    }) else { continue }
                    candidates.append(Candidate(indices: indices, kind: kind, rect: rect))
                }
            }
            // Competing interpretations involving any of the same nodes are ambiguous.
            // Disjoint regions can still be reconstructed independently on later passes.
            let certain = candidates.filter { candidate in
                !candidates.contains { other in
                    (other.indices != candidate.indices || other.kind != candidate.kind) &&
                    !other.indices.isDisjoint(with: candidate.indices)
                }
            }
            guard let candidate = certain.min(by: { lhs, rhs in
                let a = lhs.rect.width * lhs.rect.height, b = rhs.rect.width * rhs.rect.height
                return a == b ? lhs.indices.min()! < rhs.indices.min()! : a < b
            }) else { return nil }
            let children = sorted(candidate.indices.sorted().map { nodes[$0] }, kind: candidate.kind)
            let merged = Node(windows: children.flatMap(\.windows), rect: candidate.rect, kind: candidate.kind, children: children)
            nodes = nodes.indices.filter { !candidate.indices.contains($0) }.map { nodes[$0] } + [merged]
        }
        return nil
    }

    private static func sameSpan(_ a: CGRect, _ b: CGRect, axis: LayoutAxis) -> Bool {
        let x = bounds(a, axis), y = bounds(b, axis)
        return abs(x.0 - y.0) <= tolerance && abs(x.1 - y.1) <= tolerance
    }

    private static func bounds(_ rect: CGRect, _ axis: LayoutAxis) -> (CGFloat, CGFloat) {
        axis == .horizontal ? (rect.minX, rect.maxX) : (rect.minY, rect.maxY)
    }

    private static func compatible(_ nodes: [Node], kind: String) -> Bool {
        let axis = LayoutAxis(layoutKind: kind)!
        guard nodes.allSatisfy({ $0.parentHint == nil || $0.parentHint == kind }) else { return false }
        // Check every pair so tolerance cannot chain together unrelated regions.
        for i in nodes.indices {
            for j in nodes.indices where j > i {
                guard sameSpan(nodes[i].rect, nodes[j].rect, axis: axis.opposite) else { return false }
                let a = bounds(nodes[i].rect, axis), b = bounds(nodes[j].rect, axis)
                let overlap = min(a.1, b.1) - max(a.0, b.0)
                if kind.hasSuffix("_tiles") {
                    if overlap > tolerance { return false }
                } else if overlap <= tolerance { return false }
            }
        }
        return true
    }

    private static func sorted(_ nodes: [Node], kind: String) -> [Node] {
        let axis = LayoutAxis(layoutKind: kind)!
        return nodes.enumerated().sorted {
            let a = bounds($0.element.rect, axis), b = bounds($1.element.rect, axis)
            if a.0 != b.0 { return a.0 < b.0 }
            // The first and last accordion children can have equal origins but
            // different extents. Indistinguishable middle children keep fallback order.
            if a.1 != b.1 { return a.1 < b.1 }
            return $0.offset < $1.offset
        }.map(\.element)
    }
}
