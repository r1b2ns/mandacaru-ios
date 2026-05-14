use std::ffi::{c_char, CStr, CString};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Once};
use std::time::Duration;

use bitcoin::Network;
use floresta::chain::{BlockchainError, BlockchainInterface, ChainState};
use floresta::wire::node::UtreexoNode;
use floresta_chain::pruned_utreexo::chainparams::ChainParams;
use floresta_chain::{AssumeValidArg, FlatChainStore, FlatChainStoreConfig};
use floresta_mempool::Mempool;
use floresta_wire::address_man::{AddressMan, SUPPORTED_NETWORKS};
use floresta_wire::node::running_ctx::RunningNode;
use floresta_wire::UtreexoNodeConfig;
use tokio::sync::{Mutex, RwLock};
use tracing_subscriber::EnvFilter;

const MEMPOOL_SIZE: usize = 10_000;

static TRACING_INIT: Once = Once::new();

fn install_tracing() {
    TRACING_INIT.call_once(|| {
        // Sane defaults: info for everything Floresta-related; can be overridden via env.
        let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| {
            EnvFilter::new(concat!(
                "info,",
                "floresta_ffi=info,",
                "floresta_chain=info,",
                "floresta_wire=info,",
                // Verbose where the IBD/discovery work happens, so we can see DNS lookups,
                // peer dials, handshakes, and chain selection progress.
                "floresta_wire::p2p_wire::address_man=debug,",
                "floresta_wire::p2p_wire::node=debug,",
                "floresta_wire::p2p_wire::node::chain_selector_ctx=debug,",
                "floresta_wire::p2p_wire::node::conn=debug,",
                "floresta_wire::p2p_wire::peer=debug",
            ))
        });
        let _ = tracing_subscriber::fmt()
            .with_env_filter(filter)
            .with_target(true)
            .with_ansi(false)
            .with_writer(std::io::stderr)
            .try_init();
        tracing::info!(target: "floresta_ffi", "[Sync] tracing subscriber installed");
    });
}

#[repr(C)]
pub struct FlorestaSyncStatus {
    pub height: u32,
    pub headers: u32,
    pub peers: u32,
    pub in_ibd: bool,
    pub progress: f64,
}

/// Runtime tuning knobs forwarded to `UtreexoNodeConfig`. Pass NULL to
/// `floresta_node_new` to use the mobile-friendly defaults below.
#[repr(C)]
#[derive(Copy, Clone)]
pub struct FlorestaConfig {
    /// Enable assumeutreexo with the network's hardcoded snapshot — fast sync
    /// at the cost of trusting the snapshot baked into the fork.
    pub assume_utreexo: bool,
    /// When assumeutreexo is on, also download and verify historical blocks in
    /// the background to upgrade from "trusted" to "fully validated".
    pub backfill: bool,
    /// Use PoW fraud proofs to skip most of the chain validation. Off by
    /// default — exclusive with `assume_utreexo` in practice.
    pub pow_fraud_proofs: bool,
    /// Skip DNS seeds. Useful for tests; in production we want them on.
    pub disable_dns_seeds: bool,
    /// Allow falling back to P2P v1 if the v2 handshake fails.
    pub allow_v1_fallback: bool,
    /// Peer misbehaviour threshold before disconnecting. Floresta default is 100.
    pub max_banscore: u32,
}

impl FlorestaConfig {
    /// Recommended defaults for mobile: snapshot-based fast sync with backfill.
    fn defaults() -> Self {
        FlorestaConfig {
            assume_utreexo: true,
            backfill: true,
            pow_fraud_proofs: false,
            disable_dns_seeds: false,
            allow_v1_fallback: true,
            max_banscore: 100,
        }
    }
}

pub struct FlorestaNode {
    runtime: tokio::runtime::Runtime,
    chain: Arc<ChainState<FlatChainStore>>,
    network: Network,
    datadir: String,
    config: FlorestaConfig,
    kill_signal: Arc<RwLock<bool>>,
    peer_count: Arc<AtomicU32>,
    join_handle: Option<tokio::task::JoinHandle<()>>,
    peer_poll_handle: Option<tokio::task::JoinHandle<()>>,
}

fn network_from_u32(network: u32) -> Option<Network> {
    match network {
        0 => Some(Network::Bitcoin),
        1 => Some(Network::Testnet),
        2 => Some(Network::Signet),
        3 => Some(Network::Regtest),
        _ => None,
    }
}

#[no_mangle]
pub extern "C" fn floresta_ffi_version() -> *mut c_char {
    CString::new(env!("CARGO_PKG_VERSION")).unwrap().into_raw()
}

#[no_mangle]
pub extern "C" fn floresta_ffi_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

#[no_mangle]
pub extern "C" fn floresta_node_new(
    data_dir: *const c_char,
    network: u32,
    config: *const FlorestaConfig,
) -> *mut FlorestaNode {
    install_tracing();
    if data_dir.is_null() {
        tracing::error!(target: "floresta_ffi", "[Sync] node_new: data_dir is null");
        return std::ptr::null_mut();
    }
    let Some(net) = network_from_u32(network) else {
        tracing::error!(target: "floresta_ffi", "[Sync] node_new: unknown network {network}");
        return std::ptr::null_mut();
    };
    let datadir = unsafe { CStr::from_ptr(data_dir) }
        .to_string_lossy()
        .into_owned();
    let cfg = if config.is_null() {
        FlorestaConfig::defaults()
    } else {
        unsafe { std::ptr::read(config) }
    };
    tracing::info!(
        target: "floresta_ffi",
        "[Sync] node_new network={:?} datadir={} assume_utreexo={} backfill={} pow_fraud_proofs={}",
        net, datadir, cfg.assume_utreexo, cfg.backfill, cfg.pow_fraud_proofs
    );

    let runtime = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .worker_threads(2)
        .thread_name("floresta-ffi")
        .build()
    {
        Ok(rt) => rt,
        Err(_) => return std::ptr::null_mut(),
    };

    // Mirror floresta_node::Florestad's layout: chain data goes under
    // `<datadir>/chaindata/`. Lets us reuse a Floresta-installed datadir later
    // without surprises.
    let chaindata_path = format!("{}/chaindata", datadir);
    let chain_store = match FlatChainStore::new(FlatChainStoreConfig::new(chaindata_path.clone())) {
        Ok(s) => s,
        Err(e) => {
            tracing::error!(target: "floresta_ffi", "[Node] FlatChainStore::new failed: {e:?}");
            return std::ptr::null_mut();
        }
    };
    // Same load-or-initialize pattern florestad uses: try to load an existing
    // chain, and only if the store is empty (ChainNotInitialized) do we
    // create one from genesis.
    let chain = match ChainState::load_chain_state(chain_store, net, AssumeValidArg::Hardcoded) {
        Ok(c) => Arc::new(c),
        Err(BlockchainError::ChainNotInitialized) => {
            let chain_store = match FlatChainStore::new(FlatChainStoreConfig::new(chaindata_path)) {
                Ok(s) => s,
                Err(e) => {
                    tracing::error!(target: "floresta_ffi", "[Node] FlatChainStore::new (init) failed: {e:?}");
                    return std::ptr::null_mut();
                }
            };
            tracing::info!(target: "floresta_ffi", "[Node] initializing fresh chain state from genesis");
            Arc::new(ChainState::new(chain_store, net, AssumeValidArg::Hardcoded))
        }
        Err(e) => {
            tracing::error!(target: "floresta_ffi", "[Node] load_chain_state failed: {e}");
            return std::ptr::null_mut();
        }
    };

    let kill_signal = Arc::new(RwLock::new(false));

    Box::into_raw(Box::new(FlorestaNode {
        runtime,
        chain,
        network: net,
        datadir,
        config: cfg,
        kill_signal,
        peer_count: Arc::new(AtomicU32::new(0)),
        join_handle: None,
        peer_poll_handle: None,
    }))
}

#[no_mangle]
pub extern "C" fn floresta_node_start(node: *mut FlorestaNode) -> bool {
    if node.is_null() {
        return false;
    }
    let node_ref = unsafe { &mut *node };
    if node_ref.join_handle.is_some() {
        return false;
    }

    let chain = node_ref.chain.clone();
    let kill_signal = node_ref.kill_signal.clone();
    let network = node_ref.network;
    let datadir = node_ref.datadir.clone();
    let peer_count = node_ref.peer_count.clone();
    let cfg = node_ref.config;

    // Channel so the run-loop spawn can hand the NodeInterface handle back to us,
    // so the peer-polling task can be spawned with it.
    let (handle_tx, handle_rx) = tokio::sync::oneshot::channel();

    let join_handle = node_ref.runtime.spawn(async move {
        let assume_utreexo = if cfg.assume_utreexo {
            Some(ChainParams::get_assume_utreexo(network))
        } else {
            None
        };
        let config = UtreexoNodeConfig {
            network,
            datadir: datadir.clone(),
            disable_dns_seeds: cfg.disable_dns_seeds,
            pow_fraud_proofs: cfg.pow_fraud_proofs,
            assume_utreexo: assume_utreexo.clone(),
            backfill: cfg.backfill,
            allow_v1_fallback: cfg.allow_v1_fallback,
            max_banscore: cfg.max_banscore,
            ..UtreexoNodeConfig::default()
        };
        tracing::info!(
            target: "floresta_ffi",
            "[Sync] starting UtreexoNode network={:?} datadir={} assume_utreexo={} backfill={}",
            network,
            config.datadir,
            assume_utreexo
                .as_ref()
                .map(|v| format!("Some(height={} roots={})", v.height, v.roots.len()))
                .unwrap_or_else(|| "None".to_string()),
            cfg.backfill
        );

        let mempool = Arc::new(Mutex::new(Mempool::new(MEMPOOL_SIZE)));
        let addrman = AddressMan::new(None, SUPPORTED_NETWORKS);

        let p2p: UtreexoNode<Arc<ChainState<FlatChainStore>>, RunningNode> =
            match UtreexoNode::new(config, chain, mempool, None, kill_signal, addrman) {
                Ok(n) => n,
                Err(e) => {
                    tracing::error!(target: "floresta_ffi", "[Sync] UtreexoNode::new failed: {e}");
                    let _ = handle_tx.send(None);
                    return;
                }
            };

        let node_handle = p2p.get_handle();
        let _ = handle_tx.send(Some(node_handle));

        tracing::info!(target: "floresta_ffi", "[Sync] UtreexoNode created; entering run loop");
        let (sender, _receiver) = tokio::sync::oneshot::channel();
        p2p.run(sender).await;
        tracing::info!(target: "floresta_ffi", "[Sync] UtreexoNode run loop returned");
    });

    // Wait synchronously for the handle to be produced (very fast — `get_handle`
    // is called right after `UtreexoNode::new`). This keeps `start` simple to
    // call from the FFI side without exposing async state.
    let node_handle = node_ref.runtime.block_on(handle_rx).ok().flatten();

    let peer_poll_handle = node_handle.map(|h| {
        let counter = peer_count.clone();
        node_ref.runtime.spawn(async move {
            // Poll cadence: short enough to feel responsive in the UI, long
            // enough that the cost is negligible compared to the IBD workload.
            let mut ticker = tokio::time::interval(Duration::from_secs(2));
            ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
            let mut last_logged: u32 = u32::MAX;
            loop {
                ticker.tick().await;
                match h.get_peer_info().await {
                    Ok(peers) => {
                        let n = peers.len() as u32;
                        counter.store(n, Ordering::Relaxed);
                        if n != last_logged {
                            tracing::info!(target: "floresta_ffi", "[Sync] peers conectados: {n}");
                            last_logged = n;
                        }
                    }
                    Err(_) => {
                        // Run loop ended → channel closed → exit polling task.
                        break;
                    }
                }
            }
        })
    });

    node_ref.join_handle = Some(join_handle);
    node_ref.peer_poll_handle = peer_poll_handle;
    true
}

#[no_mangle]
pub extern "C" fn floresta_node_stop(node: *mut FlorestaNode) {
    if node.is_null() {
        return;
    }
    let node_ref = unsafe { &mut *node };
    let kill_signal = node_ref.kill_signal.clone();
    node_ref.runtime.block_on(async move {
        *kill_signal.write().await = true;
    });
    if let Some(handle) = node_ref.join_handle.take() {
        let _ = node_ref.runtime.block_on(handle);
    }
}

#[no_mangle]
pub extern "C" fn floresta_node_status(node: *mut FlorestaNode) -> FlorestaSyncStatus {
    if node.is_null() {
        return FlorestaSyncStatus {
            height: 0,
            headers: 0,
            peers: 0,
            in_ibd: true,
            progress: 0.0,
        };
    }
    let node_ref = unsafe { &*node };
    let chain = &node_ref.chain;

    let height = chain.get_validation_index().unwrap_or(0);
    let headers = chain.get_best_block().map(|(h, _)| h).unwrap_or(0);
    let in_ibd = chain.is_in_ibd();
    let peers = node_ref.peer_count.load(Ordering::Relaxed);
    let progress = if headers > 0 {
        (height as f64) / (headers as f64)
    } else {
        0.0
    };

    FlorestaSyncStatus {
        height,
        headers,
        peers,
        in_ibd,
        progress,
    }
}

#[no_mangle]
pub extern "C" fn floresta_node_free(node: *mut FlorestaNode) {
    if node.is_null() {
        return;
    }
    unsafe {
        let mut boxed = Box::from_raw(node);
        if boxed.join_handle.is_some() {
            let kill = boxed.kill_signal.clone();
            boxed.runtime.block_on(async move {
                *kill.write().await = true;
            });
            if let Some(h) = boxed.peer_poll_handle.take() {
                h.abort();
                let _ = boxed.runtime.block_on(h);
            }
            if let Some(h) = boxed.join_handle.take() {
                let _ = boxed.runtime.block_on(h);
            }
        }
    }
}
