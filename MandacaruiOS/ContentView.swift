import SwiftUI
import os
import Floresta

@Observable
@MainActor
final class NodeController {
    private var node: FlorestaNode?
    private var streamTask: Task<Void, Never>?

    var status: SyncStatus = .initial
    var isRunning = false
    var errorMessage: String?

    func start() async {
        errorMessage = nil
        let network: FlorestaNetwork = .signet
        Log.node.info("[Node] Iniciando node (network: \(network.pathComponent, privacy: .public))")
        do {
            let dataDir = URL.applicationSupportDirectory
                .appending(path: "floresta")
                .appending(path: network.pathComponent)
            Log.node.debug("[Node] Data dir: \(dataDir.path, privacy: .public)")

            let node = try FlorestaNode(dataDir: dataDir, network: network)
            self.node = node
            Log.node.info("[Node] Node alocado, ffi=\(FlorestaNode.ffiVersion, privacy: .public)")

            try await node.start()
            isRunning = true
            Log.node.info("[Node] Node iniciado")
            Log.floresta.info("[Sync] Iniciando sincronização")

            streamTask = Task { [weak self] in
                guard let self else { return }
                guard let stream = await self.node?.statusStream(every: .seconds(1)) else { return }
                var lastLoggedPercent: Int = -1
                var lastInIBD = true
                for await snapshot in stream {
                    self.status = snapshot

                    if snapshot.inIBD != lastInIBD {
                        Log.floresta.info("[Sync] IBD: \(lastInIBD) -> \(snapshot.inIBD)")
                        lastInIBD = snapshot.inIBD
                    }

                    // Throttle: log once per whole percentage point.
                    let percent = Int(snapshot.progress * 100)
                    if percent != lastLoggedPercent {
                        Log.floresta.info(
                            "[Sync] progresso de sincronização \(percent)% (height=\(snapshot.height) headers=\(snapshot.headers))"
                        )
                        lastLoggedPercent = percent
                    }
                }
                Log.floresta.debug("[Sync] Stream encerrado")
            }
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
        await node?.stop()
        node = nil
        isRunning = false
        Log.node.info("[Node] Node parado")
    }
}

struct ContentView: View {
    @State private var controller = NodeController()

    var body: some View {
        VStack(spacing: 24) {
            header

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Network", value: "Signet")
                    .help("Per-network datadir: …/floresta/signet")
                LabeledContent("State", value: stateLabel)
                LabeledContent("Peers", value: "\(controller.status.peers)")
                LabeledContent("Validated height", value: "\(controller.status.height)")
                LabeledContent("Best headers", value: "\(controller.status.headers)")
            }
            .font(.callout.monospaced())
            .padding()
            .background(.gray.opacity(0.1), in: .rect(cornerRadius: 12))

            ProgressView(value: controller.status.progress) {
                Text(String(format: "%.2f%%", controller.status.progress * 100))
                    .font(.caption.monospacedDigit())
            }

            if let error = controller.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            controlButton

            Text("Floresta FFI v\(FlorestaNode.ffiVersion)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf.fill").foregroundStyle(.green)
            Text("Mandacaru").font(.title2.bold())
        }
    }

    private var stateLabel: String {
        if !controller.isRunning { return "stopped" }
        return controller.status.inIBD ? "syncing (IBD)" : "synced"
    }

    @ViewBuilder
    private var controlButton: some View {
        if controller.isRunning {
            Button(role: .destructive) {
                Log.ui.info("[UI] Botão Stop pressionado")
                Task { await controller.stop() }
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                Log.ui.info("[UI] Botão Start pressionado")
                Task { await controller.start() }
            } label: {
                Label("Start sync", systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ContentView()
}
