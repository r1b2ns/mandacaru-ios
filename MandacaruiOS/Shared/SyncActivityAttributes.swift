import ActivityKit
import Foundation

/// Attributes for the chain-sync Live Activity. Shared between the host app
/// (which starts/updates the activity) and the widget extension (which renders
/// the lock-screen + Dynamic Island views).
struct SyncActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        var height: UInt32
        var headers: UInt32
        var peers: UInt32
        var progress: Double
        var inIBD: Bool
        /// Wall-clock instant after which the snapshot is considered stale. The
        /// host app refreshes this to `Date.now + freshnessWindow` on every
        /// update; the widget renders a countdown to it and a "open the app"
        /// warning once it passes (mirrored by `context.isStale`).
        var staleAt: Date
    }

    var networkName: String

    /// How long a status snapshot stays "fresh" before the widget warns the
    /// user. Single source of truth for both the app's countdown reset and the
    /// widget's `Text(timerInterval:)` window.
    static let freshnessWindow: TimeInterval = 60
}
