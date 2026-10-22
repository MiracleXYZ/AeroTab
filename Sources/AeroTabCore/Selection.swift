import Foundation

/// Selection stays fixed for one invocation even if MRU history changes underneath it.
public struct Selection: Sendable {
    public private(set) var names: [String] = []
    public private(set) var selected: String?
    public private(set) var history: [String] = []

    public init() {}

    public mutating func recordFocus(_ name: String) {
        history.removeAll { $0 == name }
        history.insert(name, at: 0)
        history = Array(history.prefix(100))
    }

    public mutating func begin(workspaces: [Workspace], focused: String?, order: CycleOrder, advance: Int) {
        let available = workspaces.map(\.name)
        if let focused { recordFocus(focused) }
        if order == .recent {
            names = history.filter { available.contains($0) } + available.filter { !history.contains($0) }
        } else {
            names = available
        }
        selected = focused.flatMap { names.contains($0) ? $0 : nil } ?? names.first
        if advance != 0 { cycle(advance) }
    }

    public mutating func cycle(_ delta: Int) {
        guard !names.isEmpty else { selected = nil; return }
        let index = selected.flatMap { names.firstIndex(of: $0) } ?? 0
        selected = names[((index + delta) % names.count + names.count) % names.count]
    }

    public mutating func select(_ name: String) {
        if names.contains(name) { selected = name }
    }

    public mutating func end() { names = []; selected = nil }
}

public enum SwitchTarget: Equatable, Sendable {
    case workspace(String)
    case window(Int)

    public var arguments: [String] {
        switch self {
        case .workspace(let name): return ["workspace", "--", name]
        case .window(let id): return ["focus", "--window-id", String(id)]
        }
    }
}
