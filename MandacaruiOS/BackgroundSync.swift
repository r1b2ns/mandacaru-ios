import Foundation
import BackgroundTasks
import os
import Floresta

/// Coordinates `BGProcessingTask` runs for chain sync between foreground sessions.
/// One identifier is registered at app launch; the OS may fire it whenever the
/// device is plugged in / on Wi-Fi / not in heavy use. We start a node, sync
/// for as long as the OS lets us, then schedule the next request.
enum BackgroundSync {
    static let taskIdentifier = "zeroSixteen.br.com.MandacaruiOS.sync"

    /// Default network for background sync. Hard-coded for now since the UI is
    /// pinned to Signet — change once the network picker lands.
    static let network: FlorestaNetwork = .signet

    /// Register the BGTask handler. Call exactly once early in app launch.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task: processingTask)
        }
        Log.node.info("[BG] handler registered for \(taskIdentifier, privacy: .public)")
    }

    /// Request the next background run. Call when the scene enters `.background`.
    static func scheduleNextRun(after delay: TimeInterval = 15 * 60) {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: delay)
        do {
            try BGTaskScheduler.shared.submit(request)
            Log.node.info("[BG] scheduled next run in \(Int(delay))s")
        } catch {
            Log.node.error("[BG] schedule failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Cancel any pending request. Call when the scene becomes `.active` so the
    /// BG task does not fire while the foreground node holds the chain store.
    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        Log.node.info("[BG] cancelled pending request")
    }

    // MARK: - Task handler

    private static func handle(task: BGProcessingTask) {
        Log.node.info("[BG] task fired")
        // Schedule the next one early so we keep ticking even if this run crashes.
        scheduleNextRun()

        let dataDir = URL.applicationSupportDirectory
            .appending(path: "floresta")
            .appending(path: network.pathComponent)

        let node: FlorestaNode
        do {
            node = try FlorestaNode(dataDir: dataDir, network: network)
        } catch {
            Log.node.error("[BG] init failed: \(String(describing: error), privacy: .public)")
            task.setTaskCompleted(success: false)
            return
        }

        let runTask = Task<Void, Never> {
            do {
                try await node.start()
                Log.node.info("[BG] node started, syncing…")
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(30))
                    let s = await node.status()
                    Log.floresta.info(
                        "[BG] height=\(s.height) headers=\(s.headers) peers=\(s.peers) in_ibd=\(s.inIBD)"
                    )
                    if !s.inIBD {
                        Log.floresta.info("[BG] sync complete, stopping early")
                        break
                    }
                }
            } catch {
                Log.node.error("[BG] run failed: \(String(describing: error), privacy: .public)")
            }
            await node.stop()
            let cancelled = Task.isCancelled
            Log.node.info("[BG] task done (cancelled=\(cancelled))")
            task.setTaskCompleted(success: !cancelled)
        }

        task.expirationHandler = {
            Log.node.info("[BG] expirationHandler fired")
            runTask.cancel()
        }
    }
}
