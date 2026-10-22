import Foundation

/// Buffers input while CLI queries run. Escape invalidates the generation so a late
/// response can never reopen the overlay or perform an unwanted switch.
public struct Invocation: Sendable {
    public enum Phase: Sendable { case idle, loading, visible }
    public private(set) var phase: Phase = .idle
    public private(set) var generation = 0
    public private(set) var advance = 0
    public private(set) var commitWhenReady = false
    public private(set) var pendingShortcut: String?
    public private(set) var followsOptionRelease = false

    public init() {}
    public var isActive: Bool { phase != .idle }

    @discardableResult
    public mutating func begin(advance: Int, followsOptionRelease: Bool) -> Int {
        generation += 1
        phase = .loading; self.advance = advance
        commitWhenReady = false; pendingShortcut = nil
        self.followsOptionRelease = followsOptionRelease
        return generation
    }

    public mutating func enqueueCycle(_ delta: Int) { advance += delta }
    public mutating func enqueueShortcut(_ key: String) { pendingShortcut = key }
    public mutating func requestCommit() { commitWhenReady = true }

    public mutating func markReady(generation: Int) -> Bool {
        guard generation == self.generation, phase == .loading else { return false }
        phase = .visible
        return true
    }

    public mutating func cancel() {
        generation += 1; phase = .idle
        commitWhenReady = false; pendingShortcut = nil; followsOptionRelease = false
    }
}
