import Foundation
import Observation
import os
import Floresta

@MainActor
protocol HomeViewModel: AnyObject, Observable {
    var status: SyncStatus { get }
    var isRunning: Bool { get }
    var errorMessage: String? { get }
    var network: FlorestaNetwork { get }
    var ffiVersion: String { get }
    var stateLabel: String { get }

    func start() async
    func stop() async
}

@MainActor
@Observable
final class DefaultHomeViewModel: HomeViewModel {

    private(set) var status: SyncStatus = .initial
    private(set) var isRunning: Bool = false
    private(set) var errorMessage: String?

    let network: FlorestaNetwork = .signet
    let config: FlorestaConfig
    var ffiVersion: String { service.ffiVersion }
    var stateLabel: String {
        if !isRunning { return "stopped" }
        return status.inIBD ? "syncing" : "synced"
    }

    @ObservationIgnored
    private let service: FlorestaNodeServicing
    @ObservationIgnored
    private let liveActivity: SyncActivityControlling
    @ObservationIgnored
    private var streamTask: Task<Void, Never>?

    init(
        service: FlorestaNodeServicing,
        liveActivity: SyncActivityControlling,
        config: FlorestaConfig = FlorestaConfig()
    ) {
        self.service = service
        self.liveActivity = liveActivity
        self.config = config
    }

    func start() async {
        errorMessage = nil
        Log.node.info("[Node] Iniciando node (network: \(self.network.pathComponent, privacy: .public))")
        do {
            let dataDir = URL.applicationSupportDirectory
                .appending(path: "floresta")
                .appending(path: network.pathComponent)
            Log.node.debug("[Node] Data dir: \(dataDir.path, privacy: .public)")

            try await service.start(dataDir: dataDir, network: network, config: config)
            isRunning = true
            Log.node.info("[Node] Node iniciado, ffi=\(self.ffiVersion, privacy: .public)")
            Log.floresta.info("[Sync] Iniciando sincronização")

            liveActivity.start(network: network)
            startStatusStream()
        } catch {
            Log.node.error("[Node] Falha ao iniciar: \(String(describing: error), privacy: .public)")
            errorMessage = String(describing: error)
        }
    }

    func stop() async {
        Log.node.info("[Node] Parando node…")
        Log.floresta.info("[Sync] Sincronização interrompida")
        streamTask?.cancel()
        streamTask = nil
        await service.stop()
        await liveActivity.end()
        isRunning = false
        Log.node.info("[Node] Node parado")
    }

    private func startStatusStream() {
        streamTask = Task { [weak self] in
            guard let self else { return }
            guard let stream = await self.service.statusStream(every: .seconds(1)) else { return }
            var lastLoggedPercent: Int = -1
            var lastInIBD = true
            var lastActivityUpdate: ContinuousClock.Instant = .now
            let activityThrottle: Duration = .seconds(2)
            for await snapshot in stream {
                self.status = snapshot
                if snapshot.inIBD != lastInIBD {
                    Log.floresta.info("[Sync] IBD: \(lastInIBD) -> \(snapshot.inIBD)")
                    lastInIBD = snapshot.inIBD
                    await self.liveActivity.update(snapshot)
                    lastActivityUpdate = .now
                }
                let percent = Int(snapshot.progress * 100)
                if percent != lastLoggedPercent {
                    Log.floresta.info(
                        "[Sync] progresso de sincronização \(percent)% (height=\(snapshot.height) headers=\(snapshot.headers))"
                    )
                    lastLoggedPercent = percent
                }
                // Refresh the Live Activity on a fixed cadence so peers / height /
                // headers stay current even when `progress` is stuck at 0% (which
                // happens during the header-download phase before any block lands).
                if ContinuousClock.now - lastActivityUpdate >= activityThrottle {
                    await self.liveActivity.update(snapshot)
                    lastActivityUpdate = .now
                }
            }
            Log.floresta.debug("[Sync] Stream encerrado")
        }
    }
}
