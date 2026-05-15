# MandacaruiOS

A lightweight Bitcoin validator node for iOS, powered by [Utreexo](https://dci.mit.edu/utreexo) and [Floresta](https://github.com/getfloresta/Floresta). iOS port of the Android [Mandacaru](https://github.com/r1b2ns/mandacaru) app.

> **Status:** early MVP. Currently focused on getting Signet IBD running.

## Try it

A TestFlight build is available — join the beta at <https://testflight.apple.com/join/7jFeDPDC>.

## What it does

Runs a real validating Bitcoin node directly on the device, without the multi-gigabyte storage of a full node. Utreexo replaces the UTXO set with a few KB of accumulator roots; each new transaction comes with an inclusion proof that the node verifies. The result is a self-sovereign node that fits in your pocket.

The MVP in this repo only covers the **sync** path. Wallet integration, Electrum server, RPC, transaction broadcast, blockchain explorer — all the user-facing features the Android app already has — are not in scope yet.

## Architecture

The app embeds the Floresta Rust daemon and exposes it to Swift through a custom C ABI:

```
+-----------------------------+
|  SwiftUI app                |
|   └─ Floresta package       |  imports FlorestaFFI module
|       └─ FlorestaNode       |  Swift actor over the C API
+-----------------------------+
              |
              v  cbindgen-generated header + libfloresta_ffi.a
+-----------------------------+
|  FlorestaFFI.xcframework    |  ios-arm64 + ios-arm64_x86_64-simulator
|                             |
|   floresta-ffi (Rust)       |  C ABI: node_new / start / stop / status
|    └─ floresta (Rust)       |  the actual node (P2P, IBD, validation)
+-----------------------------+
```

Floresta is pinned to the **Mandacaru fork** (`jvsena42/Floresta-mandacaru` @ `e1270905`), and the `bitcoin` crate is pinned to **`=0.32.7`** — same as the production Android app. Newer `bitcoin` versions (0.32.8+) introduced a P2P parser regression that drops every peer with `Transport(SerdeV1/V2(OversizedVarInt))` right after the handshake.

## Requirements

- macOS with Xcode 26.4 or newer
- Rust toolchain (`rustup`)
- iOS Rust targets:
  ```sh
  rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
  ```
- `cbindgen`:
  ```sh
  cargo install cbindgen
  ```
- `xcodegen`:
  ```sh
  brew install xcodegen
  ```

## Setup

```sh
# 1. Cross-compile the Rust crate and produce the XCFramework.
./rust/build-xcframework.sh

# 2. Generate the Xcode project from project.yml.
xcodegen generate

# 3. Build the app.
xcodebuild -project MandacaruiOS.xcodeproj -scheme MandacaruiOS \
  -destination 'generic/platform=iOS Simulator' build
```

Or just open `MandacaruiOS.xcodeproj` in Xcode after steps 1 and 2 and run it on a simulator.

Whenever you change Rust sources, rerun `./rust/build-xcframework.sh`. Whenever you add or remove Swift source files (or change `project.yml`), rerun `xcodegen generate`.

## How the Floresta integration works

### Rust side — `rust/floresta-ffi/`

A small `staticlib` crate that exposes a C ABI:

```c
FlorestaNode*       floresta_node_new(const char* data_dir, uint32_t network);
bool                floresta_node_start(FlorestaNode*);
void                floresta_node_stop(FlorestaNode*);
FlorestaSyncStatus  floresta_node_status(FlorestaNode*);
void                floresta_node_free(FlorestaNode*);
```

Internally:

- `floresta_node_new` opens a `FlatChainStore` at `<data_dir>/chaindata/`. If the store already has data it calls `ChainState::load_chain_state`; on `ChainNotInitialized` it falls back to `ChainState::new` (genesis init), mirroring the load-or-create pattern used by `floresta_node::Florestad`.
- `floresta_node_start` spawns a multi-thread Tokio runtime running a `UtreexoNode<_, RunningNode>` against that chain, with DNS seeds enabled.
- A separate Tokio task polls `NodeInterface::get_peer_info` every 2 s and stores the count in an `AtomicU32`. The FFI `status` call reads it without blocking, so the Swift side can refresh on a tight loop.
- `tracing_subscriber` is installed lazily on the first `node_new` call and writes Floresta's internal logs to stderr — they show up in the Xcode console alongside the Swift logs.

### Header generation — `rust/floresta-ffi/cbindgen.toml`

`cbindgen` generates `rust/include/floresta_ffi.h` from the Rust source. `rust/include/module.modulemap` declares a `FlorestaFFI` Clang module so Swift can `import FlorestaFFI`.

### XCFramework build — `rust/build-xcframework.sh`

1. Regenerates the C header via cbindgen.
2. Cross-compiles to `aarch64-apple-ios`, `aarch64-apple-ios-sim`, and `x86_64-apple-ios`.
3. `lipo`s the two simulator slices into one fat universal binary.
4. Runs `xcodebuild -create-xcframework` to produce `Floresta/FlorestaFFI.xcframework`.

### Swift side — `Floresta/`

A local Swift Package with two targets:

- **`FlorestaFFI`** — a `binaryTarget` pointing at the XCFramework, exposing the raw C symbols.
- **`Floresta`** — a Swift library with `FlorestaNode`, an idiomatic `actor` wrapping the C API:
  - `init(dataDir: URL, network: FlorestaNetwork)` — creates the chain store and node.
  - `start()` / `stop()` — lifecycle.
  - `status()` — one-shot `SyncStatus` (height, headers, peers, in-IBD, progress).
  - `statusStream(every:)` — `AsyncStream<SyncStatus>` for polling from SwiftUI.

`project.yml` (XcodeGen) declares the package as a local dependency of the app target, so `import Floresta` works out of the box.

## Project structure

```
MandacaruiOS/
├── project.yml                        # XcodeGen spec (source of truth)
├── MandacaruiOS.xcodeproj/            # generated by `xcodegen generate`
├── MandacaruiOS/                      # SwiftUI app
│   ├── MandacaruiOSApp.swift
│   ├── ContentView.swift              # the sync screen
│   └── Utils/Log.swift                # os.Logger categories
├── Floresta/                          # local Swift Package
│   ├── Package.swift
│   ├── FlorestaFFI.xcframework/       # built by build-xcframework.sh
│   └── Sources/Floresta/FlorestaNode.swift
└── rust/                              # Cargo workspace
    ├── Cargo.toml
    ├── floresta-ffi/                  # the staticlib crate
    │   ├── Cargo.toml
    │   ├── cbindgen.toml
    │   └── src/lib.rs
    ├── include/                       # generated header + modulemap
    └── build-xcframework.sh
```

## Current MVP scope

- Hard-coded to Signet (mainnet IBD without an embedded `assumeutreexo` snapshot is impractical on a phone).
- Foreground-only execution. `BGProcessingTask` integration is on the roadmap.
- Sync UI only: peers, validated height, best headers, progress, start/stop.
- No wallet, no Electrum server, no RPC, no transaction broadcast.

## Logging

Inside the app, `Log.floresta` / `Log.node` / `Log.ui` write to `os.Logger` (filter by subsystem `zeroSixteen.br.com.MandacaruiOS` in Console.app). Floresta's internal `tracing` output goes to stderr and appears in the Xcode console. Filter is `info` by default; override at runtime by setting `RUST_LOG=debug` in the scheme's environment variables.

## License

MIT — see [LICENSE](LICENSE).

## Credits

- [Floresta](https://github.com/getfloresta/Floresta) — the embeddable Bitcoin client this app is built on.
- [Mandacaru (Android)](https://github.com/r1b2ns/mandacaru) — the original app and reference implementation.
- [jvsena42/Floresta-mandacaru](https://github.com/jvsena42/Floresta-mandacaru) — the Floresta fork used in production by the Android app, and pinned here for the same reasons.
