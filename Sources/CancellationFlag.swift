import Foundation
import Synchronization

/// Bridges Swift task cancellation to synchronous C-library work on a queue.
/// A running decode finishes its current piece; subsequent pieces are skipped.
final class CancellationFlag: Sendable {
    private let cancelled = Atomic<Bool>(false)
    var isCancelled: Bool { cancelled.load(ordering: .relaxed) }
    func cancel() { cancelled.store(true, ordering: .relaxed) }
    func check() throws {
        if isCancelled { throw CancellationError() }
    }
}
