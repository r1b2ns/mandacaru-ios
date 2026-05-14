import SwiftUI
import Floresta

enum HomeFactory {

    @MainActor
    static func make() -> some View {
        let service = DefaultFlorestaNodeService()
        let viewModel = DefaultHomeViewModel(service: service, config: FlorestaConfig())
        return HomeView(viewModel: viewModel)
    }
}
