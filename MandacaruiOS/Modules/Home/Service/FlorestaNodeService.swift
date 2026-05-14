import Foundation
import Floresta

@MainActor
protocol FlorestaNodeServicing: AnyObject {
    var ffiVersion: String { get }
    func start(dataDir: URL, network: FlorestaNetwork, config: FlorestaConfig) async throws
    func stop() async
    func statusStream(every interval: Duration) async -> AsyncStream<SyncStatus>?
}

@MainActor
final class DefaultFlorestaNodeService: FlorestaNodeServicing {

    let ffiVersion: String = FlorestaNode.ffiVersion

    private var node: FlorestaNode?

    func start(dataDir: URL, network: FlorestaNetwork, config: FlorestaConfig) async throws {
        let node = try FlorestaNode(dataDir: dataDir, network: network, config: config)
        self.node = node
        try await node.start()
    }

    func stop() async {
        await node?.stop()
        node = nil
    }

    func statusStream(every interval: Duration) async -> AsyncStream<SyncStatus>? {
        guard let node else { return nil }
        return await node.statusStream(every: interval)
    }
}
