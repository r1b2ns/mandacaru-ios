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
    }

    var networkName: String
}
