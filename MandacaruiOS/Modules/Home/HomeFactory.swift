import SwiftUI

enum HomeFactory {

    @MainActor
    static func make() -> some View {
        let service = DefaultFlorestaNodeService()
        let viewModel = DefaultHomeViewModel(service: service)
        return HomeView(viewModel: viewModel)
    }
}
