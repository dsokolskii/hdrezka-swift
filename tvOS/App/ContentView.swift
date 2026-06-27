import SwiftUI

struct ContentView: View {
    @State private var viewModel: ContentViewModel

    init(viewModel: ContentViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        PlatformAppView(viewModel: viewModel)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let container = AppContainer.live

        ContentView(viewModel: container.makeContentViewModel())
            .environment(container)
            .environment(AuthorizationViewModel(service: container.authorizationService))
    }
}
