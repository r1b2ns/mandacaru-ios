import ActivityKit
import WidgetKit
import SwiftUI

struct SyncLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SyncActivityAttributes.self) { context in
            LockScreenView(
                state: context.state,
                network: context.attributes.networkName
            )
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.05))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "bonjour").foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.callout.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(stateLabel(for: context.state, network: context.attributes.networkName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(value: context.state.progress).tint(Color.accentColor)
                        StatsRow(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: "bonjour").foregroundStyle(.tint)
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%")
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "bonjour").foregroundStyle(.tint)
            }
        }
    }

    private func stateLabel(for state: SyncActivityAttributes.ContentState, network: String) -> String {
        state.inIBD ? "Mandaracu • Syncing \(network)" : "Synced \(network)"
    }
}

private struct LockScreenView: View {
    let state: SyncActivityAttributes.ContentState
    let network: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "bonjour").foregroundStyle(.tint)
                Text(state.inIBD ? "Syncing \(network)" : "Synced \(network)")
                    .font(.headline)
                Spacer()
                Text("\(Int(state.progress * 100))%")
                    .font(.callout.monospacedDigit())
            }
            ProgressView(value: state.progress).tint(Color.accentColor)
            StatsRow(state: state)
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
