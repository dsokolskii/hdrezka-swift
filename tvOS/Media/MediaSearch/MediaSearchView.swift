import SwiftUI

struct MediaSearchView: View {
    @State private var text: String = ""

    @State private var viewModel: MediaSearchContentViewModel
    @State private var searchTask: Task<Void, Never>?
    private let onMoveLeftToProfileMenu: () -> Void
    private let focusRequest: Int

    init(
        viewModel: MediaSearchContentViewModel,
        onMoveLeftToProfileMenu: @escaping () -> Void = {},
        focusRequest: Int = 0
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onMoveLeftToProfileMenu = onMoveLeftToProfileMenu
        self.focusRequest = focusRequest
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 80)
            VStack(spacing: 12) {
                MediaSearchContentView(
                    viewModel: viewModel,
                    onMoveLeftToProfileMenu: onMoveLeftToProfileMenu,
                    focusRequest: focusRequest
                )
            }
            .onChange(of: text) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard Task.isCancelled == false else { return }
                    await viewModel.updateSearch(text: newValue)
                    await viewModel.submitSearch()
                }
            }
            .searchable(text: $text, prompt: "Поиск по всему каталогу")
            .onFirstAppear {
                Task {
                    await viewModel.submitSearch()
                }
            }
        }
        .screenBackground()
    }
}

struct MediaSearchContentView: View {
    private enum FocusTarget: Hashable {
        case media(String)
    }

    let viewModel: MediaSearchContentViewModel
    let onMoveLeftToProfileMenu: () -> Void
    let focusRequest: Int

    @StateObject private var bookmarkViewModel = MediaBookmarksViewModel.shared
    @FocusState private var focusedTarget: FocusTarget?

    private let columns = Array(
        repeating: GridItem(.fixed(MediaItemViewView.coverSize.width), spacing: AppTheme.gridSpacing),
        count: 5
    )
    
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
                        ForEach(Array(viewModel.newMedias.enumerated()), id: \.element.id) { index, media in
                            let isBookmarked = bookmarkViewModel.isBookmarked(for: media)
                            NavigationLink {
                                DetailedMediaItemView(
                                    viewModel: DetailedMediaItemViewModel(media: media),
                                    bookmarkViewModel: bookmarkViewModel,
                                    onMoveLeftToProfileMenu: onMoveLeftToProfileMenu
                                )
                            } label: {
                                MediaItemViewView(media: media, isBookmarked: isBookmarked)
                                    .frame(width: MediaItemViewView.coverSize.width, height: MediaItemViewView.coverSize.height)
                            }
                            .focusEffectDisabled()
                            .buttonStyle(.borderless)
                            .focused($focusedTarget, equals: .media(media.id))
                            .onMoveLeftToProfileMenu(isLeadingGridColumn(index), perform: onMoveLeftToProfileMenu)
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
                .padding(.top, 34)
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            .allowsHitTesting(isBlockingOverlayPresented == false)

            overlayView
        }
        .onChange(of: focusRequest) { _, _ in
            guard let firstMedia = viewModel.newMedias.first else { return }

            focusedTarget = .media(firstMedia.id)
        }
    }
    
    @ViewBuilder
    private var overlayView: some View {
        switch viewModel.phase {
        case .fetching:
            progress
        case .success(let medias) where medias.isEmpty:
            EmptyPlaceholderView(text: "No Medias", image: nil)
        case .failure(let error):
            RetryView(text: error.localizedDescription, retryAction: refreshTask)
        default: EmptyView()
        }
    }
    
    @ViewBuilder
    private var progress: some View {
        LoadingPanel()
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

    private func isLeadingGridColumn(_ index: Int) -> Bool {
        index.isMultiple(of: columns.count)
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

struct MediaSearchView_Previews: PreviewProvider {
    static var previews: some View {
        MediaSearchView(viewModel: AppContainer.live.makeSearchViewModel())
    }
}
