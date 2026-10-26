import Foundation

/// A resumable clock: stopping decoration preserves its last frame.
struct MotionClock {
    private var accumulated: TimeInterval = 0
    private var startedAt: Date?
    var isRunning: Bool { startedAt != nil }

    mutating func setRunning(_ running: Bool, at date: Date = Date()) {
        if running, startedAt == nil { startedAt = date }
        else if !running, let startedAt {
            accumulated += max(0, date.timeIntervalSince(startedAt))
            self.startedAt = nil
        }
    }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
}

/// A failed image may retry after a cooldown. Superseded tasks cannot finish
/// the new source's attempt or clear its loading indicator.
struct ArtworkAttempts {
    private(set) var generation = UUID()
    private(set) var isLoading = false
    private var retryAt = Date.distantPast

    mutating func reset() { generation = UUID(); isLoading = false; retryAt = .distantPast }
    mutating func begin(at date: Date = Date()) -> UUID? {
        guard !isLoading, date >= retryAt else { return nil }
        isLoading = true
        return generation
    }
    @discardableResult mutating func finish(_ token: UUID, succeeded: Bool, at date: Date = Date()) -> Bool {
        guard token == generation else { return false }
        isLoading = false
        retryAt = succeeded ? .distantFuture : date.addingTimeInterval(15)
        return true
    }
}
