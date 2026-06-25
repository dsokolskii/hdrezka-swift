import SwiftUI

@main
struct RezkaWatchApp: App {
    @State private var container: AppContainer
    @State private var authorizationViewModel: AuthorizationViewModel

    init() {
        let container = AppContainer.live
        _container = State(initialValue: container)
        _authorizationViewModel = State(
            initialValue: AuthorizationViewModel(service: container.authorizationService)
        )
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(viewModel: container.makeContentViewModel())
                .environment(container)
                .environment(authorizationViewModel)
        }
    }
}
