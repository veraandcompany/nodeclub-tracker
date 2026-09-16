import Foundation
import Observation

/// Ticks `now` on the main actor so the menu bar label and popover stay live.
@MainActor
@Observable
public final class ClockTicker {
    public private(set) var now: Date
    private var tickerTask: Task<Void, Never>?

    public init(now: Date = Date()) {
        self.now = now
    }

    public func start(interval: Duration = .seconds(1)) {
        guard tickerTask == nil else { return }
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                self.now = Date()
            }
        }
    }

    public func stop() {
        tickerTask?.cancel()
        tickerTask = nil
    }
    // No deinit: the ticker task captures `weak self`, so it exits on the next
    // tick after deallocation without `stop()` being called.
}
