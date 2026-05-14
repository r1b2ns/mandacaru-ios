import SwiftUI
import Floresta

enum HomeFactory {

    @MainActor
    static func make() -> some View {
        let service = DefaultFlorestaNodeService()
        let liveActivity = DefaultSyncActivityController()
        let viewModel = DefaultHomeViewModel(
            service: service,
            liveActivity: liveActivity,
            config: FlorestaConfig()
        )
        return HomeView(viewModel: viewModel)
    }
}
