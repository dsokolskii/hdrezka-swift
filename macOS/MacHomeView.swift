#if os(macOS)
import SwiftUI

/// macOS-обёртка над `MediaHomeView`: показывает полку «Продолжить просмотр»
/// и подборки по категориям (Фильмы, Сериалы, Аниме, Мультфильмы).
struct MacHomeView: View {
    @State private var viewModel: MediaHomeViewModel

    init(viewModel: MediaHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        MediaHomeView(viewModel: viewModel)
    }
}
#endif
