#if os(macOS)
import SwiftUI

struct MacMediaSearchView: View {
    @State private var text = ""
    @State private var viewModel: MediaSearchContentViewModel
    @State private var searchTask: Task<Void, Never>?

    init(viewModel: MediaSearchContentViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    SectionHeader(
                        eyebrow: "Поиск",
                        title: "Найти фильм или сериал",
                        subtitle: "Результаты выглядят как единая витрина: крупные постеры, мягкий свет и быстрые действия."
                    )

                    LazyVGrid(columns: columns, alignment: .center, spacing: AppTheme.gridSpacing) {
                        ForEach(viewModel.newMedias, id: \.id) { media in
                            let isBookmarked = bookmarkViewModel.isBookmarked(for: media)

                            NavigationLink {
                                DetailedMediaItemView(
                                    viewModel: DetailedMediaItemViewModel(media: media),
                                    bookmarkViewModel: bookmarkViewModel
                                )
                            } label: {
                                MediaItemViewView(media: media, isBookmarked: isBookmarked)
                                    .frame(width: MediaItemViewView.coverSize.width, height: MediaItemViewView.coverSize.height)
                            }
                            .buttonStyle(.borderless)
                        }

                        if viewModel.canLoadMore {
                            Color.clear
                                .frame(height: 1)
                                .onAppear(perform: loadMoreTask)
                        }
                    }
                    .padding(.bottom, 48)
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 18)
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            .allowsHitTesting(isBlockingOverlayPresented == false)
            .searchable(text: $text, prompt: "Поиск по всему каталогу")
            .onChange(of: text) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard Task.isCancelled == false else { return }
                    await viewModel.updateSearch(text: newValue)
                    await viewModel.submitSearch()
                }
            }
            .onFirstAppear {
                Task {
                    await viewModel.submitSearch()
                }
            }

            overlayView
        }
    }

    @StateObject private var bookmarkViewModel = MediaBookmarksViewModel.shared

    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 210, maximum: 260), spacing: AppTheme.gridSpacing, alignment: .top)
        ]
    }

    @ViewBuilder
    private var overlayView: some View {
        switch viewModel.phase {
        case .fetching:
            LoadingPanel()
        case .success(let medias) where medias.isEmpty:
            EmptyPlaceholderView(text: "No Medias", image: nil)
        case .failure(let error):
            RetryView(text: error.localizedDescription, retryAction: refreshTask)
        default:
            EmptyView()
        }
    }

    private func refreshTask() {
        Task {
            await viewModel.searchMedias()
        }
    }

    private func loadMoreTask() {
        Task {
            await viewModel.loadMore()
        }
    }

    private var isBlockingOverlayPresented: Bool {
        switch viewModel.phase {
        case .fetching:
            true
        case .success(let medias):
            medias.isEmpty
        case .failure:
            true
        case .fetchingNextPage:
            false
        }
    }
}
#endif
