import Foundation

public enum KeyboardReadiness: Equatable, Sendable {
    case needsAccessibility, listenerFailed, ready
    public init(accessibility: Bool, listener: Bool) {
        self = !accessibility ? .needsAccessibility : (!listener ? .listenerFailed : .ready)
    }
    public var isReady: Bool { self == .ready }
    public func needsSetup(completed: Bool) -> Bool { !completed || !isReady }
}
