import ActivityKit
import WidgetKit
import SwiftUI

struct SyncLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SyncActivityAttributes.self) { context in
            LockScreenView(
                state: context.state,
                network: context.attributes.networkName,
                isStale: context.isStale
            )
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.05))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HeaderIcon(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TrailingBadge(state: context.state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(stateLabel(for: context.state, network: context.attributes.networkName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    BodyView(state: context.state, isStale: context.isStale, dense: true)
                }
            } compactLeading: {
                HeaderIcon(state: context.state)
            } compactTrailing: {
                CompactTrailing(state: context.state, isStale: context.isStale)
            } minimal: {
                HeaderIcon(state: context.state)
            }
        }
    }

    private func stateLabel(for state: SyncActivityAttributes.ContentState, network: String) -> String {
        if !state.inIBD { return "Mandacaru • Node synced" }
        return "Mandacaru • Syncing \(network)"
    }
}

// MARK: - Lock screen

private struct LockScreenView: View {
    let state: SyncActivityAttributes.ContentState
    let network: String
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HeaderIcon(state: state)
                Text(state.inIBD ? "Syncing \(network)" : "Node synced")
                    .font(.headline)
                Spacer()
                TrailingBadge(state: state, isStale: isStale)
            }
            BodyView(state: state, isStale: isStale, dense: false)
        }
    }
}

// MARK: - Shared pieces

/// Bonjour icon during IBD, success badge once synced.
private struct HeaderIcon: View {
    let state: SyncActivityAttributes.ContentState

    var body: some View {
        if state.inIBD {
            Image(systemName: "bonjour")
                .foregroundStyle(Color.accentColor)
        } else {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
        }
    }
}

/// Top-right indicator: percent while syncing, warning icon when stale, nothing
/// once synced (the header already says it).
private struct TrailingBadge: View {
    let state: SyncActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if !state.inIBD {
            EmptyView()
        } else if isStale {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else {
            Text("\(Int(state.progress * 100))%")
                .font(.callout.monospacedDigit())
        }
    }
}

/// Same trailing affordance, but reduced to a single glyph for the compact
/// Dynamic Island slot.
private struct CompactTrailing: View {
    let state: SyncActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if !state.inIBD {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
        } else if isStale {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else {
            Text("\(Int(state.progress * 100))%")
                .font(.caption2.monospacedDigit())
        }
    }
}

/// Bottom section: synced → success banner; stale → warning to open the app;
/// otherwise → progress bar + stats row.
private struct BodyView: View {
    let state: SyncActivityAttributes.ContentState
    let isStale: Bool
    let dense: Bool

    var body: some View {
        if !state.inIBD {
            SyncedBanner(state: state, dense: dense)
        } else if isStale {
            StaleBanner()
        } else {
            VStack(spacing: dense ? 6 : 8) {
                ProgressView(value: state.progress)
                    .tint(Color.accentColor)
                StatsRow(state: state)
            }
        }
    }
}

private struct StaleBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Open the app to keep syncing")
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }
}

private struct SyncedBanner: View {
    let state: SyncActivityAttributes.ContentState
    let dense: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(dense ? .title3 : .title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Node fully synced")
                    .font(.callout.bold())
                Text("Validated up to height \(state.height)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct StatsRow: View {
    let state: SyncActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Stat(label: "validated", value: "\(state.height)")
            Stat(label: "best", value: "\(state.headers)")
            Stat(label: "peers", value: "\(state.peers)")
        }
        .font(.caption2.monospaced())
    }
}

private struct Stat: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
