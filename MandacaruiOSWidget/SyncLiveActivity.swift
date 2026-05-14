import ActivityKit
import WidgetKit
import SwiftUI

struct SyncLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SyncActivityAttributes.self) { context in
            FreshnessGate(context: context) { stale in
                LockScreenView(
                    state: context.state,
                    network: context.attributes.networkName,
                    isStale: stale
                )
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.05))
                .activitySystemActionForegroundColor(.primary)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HeaderIcon(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FreshnessGate(context: context) { stale in
                        TrailingBadge(state: context.state, isStale: stale)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(stateLabel(for: context.state, network: context.attributes.networkName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FreshnessGate(context: context) { stale in
                        BodyView(state: context.state, isStale: stale, dense: true)
                    }
                }
            } compactLeading: {
                HeaderIcon(state: context.state)
            } compactTrailing: {
                FreshnessGate(context: context) { stale in
                    CompactTrailing(state: context.state, isStale: stale)
                }
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

/// Forces a re-render at `state.staleAt` so the widget switches to the "open
/// the app" UI the moment the freshness countdown hits zero, even if the
/// system has not yet flipped `context.isStale` (it sometimes lags). The
/// schedule needs a present-or-past entry first — an explicit schedule built
/// with only a future date causes SwiftUI to use that future date as the
/// initial render's `timeline.date`, which would make the gate consider the
/// content stale from the very first frame.
private struct FreshnessGate<Content: View>: View {
    let context: ActivityViewContext<SyncActivityAttributes>
    @ViewBuilder var content: (Bool) -> Content

    var body: some View {
        TimelineView(.explicit([Date(), context.state.staleAt])) { timeline in
            let stale = context.isStale || timeline.date >= context.state.staleAt
            content(stale)
        }
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

/// Top-right indicator: countdown + percent while syncing, warning icon when
/// stale, nothing once synced (the header already says it).
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
            HStack(spacing: 6) {
                FreshnessCountdown(staleAt: state.staleAt)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("\(Int(state.progress * 100))%")
                    .font(.callout.monospacedDigit())
            }
        }
    }
}

/// Single-glyph version for the Dynamic Island compact slot.
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

/// 60s countdown rendered by `Text(timerInterval:)` so the digits animate in
/// place without us forcing widget re-renders every second. `pauseTime`
/// freezes the display at 00:00 instead of letting it run negative.
private struct FreshnessCountdown: View {
    let staleAt: Date

    var body: some View {
        let start = staleAt.addingTimeInterval(-SyncActivityAttributes.freshnessWindow)
        Text(timerInterval: start...staleAt, pauseTime: staleAt, countsDown: true)
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
