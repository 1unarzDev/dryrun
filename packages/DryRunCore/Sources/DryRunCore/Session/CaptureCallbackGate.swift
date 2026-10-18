import Foundation

/// An originating capture delegate carries the value returned by begin(). A callback must present that value;
/// checking only the controller's current phase would let an older room satisfy a newer room's pending finish.
public struct CaptureCallbackGate: Sendable {
    public private(set) var generation = 0
    private var pending: Int?
    public init() {}
    @discardableResult public mutating func begin() -> Int {
        generation &+= 1; pending = nil; return generation
    }
    @discardableResult public mutating func expectFinish(from origin: Int) -> Bool {
        guard origin == generation, pending == nil else { return false }
        pending = origin; return true
    }
    public mutating func accept(from origin: Int) -> Bool {
        guard pending == origin, generation == origin else { return false }
        pending = nil; return true
    }
    public mutating func invalidate() { generation &+= 1; pending = nil }
}
