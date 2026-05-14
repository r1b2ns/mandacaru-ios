import Foundation
import FlorestaFFI

public enum FlorestaNetwork: UInt32, Sendable {
    case bitcoin = 0
    case testnet = 1
    case signet = 2
    case regtest = 3

    /// Filesystem-safe identifier for this network. Used to keep per-network
    /// chain databases and peer caches isolated so switching networks does not
    /// reuse peers from a different chain (which causes magic-byte mismatches
    /// and constant "early eof" handshake failures).
    public var pathComponent: String {
        switch self {
        case .bitcoin: "bitcoin"
        case .testnet: "testnet"
        case .signet:  "signet"
        case .regtest: "regtest"
        }
    }
}

public struct SyncStatus: Sendable, Equatable {
    public let height: UInt32
    public let headers: UInt32
    public let peers: UInt32
    public let inIBD: Bool
    public let progress: Double

    public static let initial = SyncStatus(
        height: 0, headers: 0, peers: 0, inIBD: true, progress: 0
    )
}

public enum FlorestaError: Error, Sendable {
    case initFailed
    case alreadyRunning
    case startFailed
}

/// Runtime tuning knobs for the Floresta node. Mirrors `FlorestaConfig` on
/// the Rust side. Default values are mobile-friendly: snapshot-based fast
/// sync (assumeutreexo) with background backfill to verify historical blocks.
public struct FlorestaConfig: Sendable {
    /// Start syncing from the network's hardcoded utreexo snapshot — the big
    /// speedup on mainnet (~940K blocks skipped). Trusts the snapshot baked
    /// into the Floresta fork.
    public var assumeUtreexo: Bool
    /// When `assumeUtreexo` is on, also download and verify historical blocks
    /// in the background. Upgrades from "trusted snapshot" to "fully validated".
    public var backfill: Bool
    /// PoW fraud proofs — alternative to assumeutreexo. Off by default.
    public var powFraudProofs: Bool
    /// Disable DNS seeds. Useful for tests; in production we want them on.
    public var disableDnsSeeds: Bool
    /// Allow falling back to P2P v1 if the v2 handshake fails. Default true.
    public var allowV1Fallback: Bool
    /// Peer misbehaviour threshold before disconnecting. Floresta default 100.
    public var maxBanscore: UInt32

    public init(
        assumeUtreexo: Bool = true,
        backfill: Bool = true,
        powFraudProofs: Bool = false,
        disableDnsSeeds: Bool = false,
        allowV1Fallback: Bool = true,
        maxBanscore: UInt32 = 100
    ) {
        self.assumeUtreexo = assumeUtreexo
        self.backfill = backfill
        self.powFraudProofs = powFraudProofs
        self.disableDnsSeeds = disableDnsSeeds
        self.allowV1Fallback = allowV1Fallback
        self.maxBanscore = maxBanscore
    }

    fileprivate func cValue() -> FlorestaFFI.FlorestaConfig {
        FlorestaFFI.FlorestaConfig(
            assume_utreexo: assumeUtreexo,
            backfill: backfill,
            pow_fraud_proofs: powFraudProofs,
            disable_dns_seeds: disableDnsSeeds,
            allow_v1_fallback: allowV1Fallback,
            max_banscore: maxBanscore
        )
    }
}

public actor FlorestaNode {
    private var handle: OpaquePointer?
    private var isRunning = false

    public init(dataDir: URL, network: FlorestaNetwork, config: FlorestaConfig = FlorestaConfig()) throws {
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        var cConfig = config.cValue()
        let raw = dataDir.path.withCString { cstr in
            withUnsafePointer(to: &cConfig) { cfgPtr in
                floresta_node_new(cstr, network.rawValue, cfgPtr)
            }
        }
        guard let raw else { throw FlorestaError.initFailed }
        self.handle = raw
    }

    deinit {
        if let handle {
            floresta_node_free(handle)
        }
    }

    public func start() throws {
        guard let handle else { throw FlorestaError.initFailed }
        guard !isRunning else { throw FlorestaError.alreadyRunning }
        guard floresta_node_start(handle) else {
            throw FlorestaError.startFailed
        }
        isRunning = true
    }

    public func stop() {
        guard let handle, isRunning else { return }
        floresta_node_stop(handle)
        isRunning = false
    }

    public func status() -> SyncStatus {
        guard let handle else { return .initial }
        let s = floresta_node_status(handle)
        return SyncStatus(
            height: s.height,
            headers: s.headers,
            peers: s.peers,
            inIBD: s.in_ibd,
            progress: s.progress
        )
    }

    public func statusStream(every interval: Duration = .seconds(1)) -> AsyncStream<SyncStatus> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let snapshot = self.status()
                    continuation.yield(snapshot)
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public static var ffiVersion: String {
        guard let ptr = floresta_ffi_version() else { return "unknown" }
        let s = String(cString: ptr)
        floresta_ffi_string_free(ptr)
        return s
    }
}
