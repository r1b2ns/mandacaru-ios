import Foundation
import ActivityKit
import os
import Floresta

@MainActor
protocol SyncActivityControlling: AnyObject {
    func start(network: FlorestaNetwork)
    func update(_ status: SyncStatus) async
    func end() async
}

@MainActor
final class DefaultSyncActivityController: SyncActivityControlling {

    private var activity: Activity<SyncActivityAttributes>?

    func start(network: FlorestaNetwork) {
        guard activity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Log.node.info("[Activity] activities disabled by user")
            return
        }
        let attributes = SyncActivityAttributes(networkName: network.pathComponent)
        let state = SyncActivityAttributes.ContentState(
            height: 0, headers: 0, peers: 0, progress: 0, inIBD: true
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil)
            )
            Log.node.info("[Activity] started")
        } catch {
            Log.node.error("[Activity] start failed: \(String(describing: error), privacy: .public)")
        }
    }

    func update(_ status: SyncStatus) async {
        guard let activity else { return }
        let state = SyncActivityAttributes.ContentState(
            height: status.height,
            headers: status.headers,
            peers: status.peers,
            progress: status.progress,
            inIBD: status.inIBD
        )
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func end() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
        Log.node.info("[Activity] ended")
    }
}
