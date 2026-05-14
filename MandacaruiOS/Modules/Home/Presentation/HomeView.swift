import SwiftUI
import os
import Floresta

struct HomeView<ViewModel: HomeViewModel>: View {

    @State var viewModel: ViewModel

    var body: some View {
        VStack(spacing: 24) {
            header

            statusCard

            ProgressView(value: viewModel.status.progress) {
                Text(String(format: "%.2f%%", viewModel.status.progress * 100))
                    .font(.caption.monospacedDigit())
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            controlButton

            Text("Floresta FFI v\(viewModel.ffiVersion)")
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

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Network", value: viewModel.network.pathComponent.capitalized)
                .help("Per-network datadir: …/floresta/\(viewModel.network.pathComponent)")
            LabeledContent("State", value: viewModel.stateLabel)
            LabeledContent("Peers", value: "\(viewModel.status.peers)")
            LabeledContent("Validated height", value: "\(viewModel.status.height)")
            LabeledContent("Best headers", value: "\(viewModel.status.headers)")
        }
        .font(.callout.monospaced())
        .padding()
        .background(.gray.opacity(0.1), in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var controlButton: some View {
        if viewModel.isRunning {
            Button(role: .destructive) {
                Log.ui.info("[UI] Botão Stop pressionado")
                Task { await viewModel.stop() }
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                Log.ui.info("[UI] Botão Start pressionado")
                Task { await viewModel.start() }
            } label: {
                Label("Start sync", systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .frame(height: 50)
        }
    }
}

#Preview {
    HomeFactory.make()
}
