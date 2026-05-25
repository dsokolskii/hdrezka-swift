import SwiftUI

@main
struct rezka_playerApp: App {
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
            ContentView(viewModel: container.makeContentViewModel())
                .environment(container)
                .environment(authorizationViewModel)
        }
    }
}
