import SwiftUI

struct MediaContentView: View {
    @State private var viewModel: MediaContentViewModel

    @StateObject private var bookmarkViewModel = MediaBookmarksViewModel.shared
    @State private var isFilterMenuPresented = false
    @State private var isGenreMenuPresented = false
    private let onMoveLeftToProfileMenu: () -> Void

    private let columns = Array(
        repeating: GridItem(.fixed(MediaItemViewView.coverSize.width), spacing: AppTheme.gridSpacing),
        count: 5
    )

    init(viewModel: MediaContentViewModel, onMoveLeftToProfileMenu: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: viewModel)
        self.onMoveLeftToProfileMenu = onMoveLeftToProfileMenu
    }
    
    var body: some View {
        ZStack {
            catalogPage(showSubcategoryRail: true)
                .screenBackground()
                .allowsHitTesting(isBlockingOverlayPresented == false)

            overlayView
        }
        .onFirstAppear(refreshTask)
    }

    private func catalogPage(showSubcategoryRail: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if showSubcategoryRail {
                    subcategoryRail
                }

                LazyVGrid(columns: columns, alignment: .center, spacing: AppTheme.gridSpacing) {
                    ForEach(Array(viewModel.newMedias.enumerated()), id: \.element.id) { index, media in
                        if media.category == .loadMore {
                            Color.clear
                                .frame(width: MediaItemViewView.coverSize.width, height: 1)
                                .onAppear(perform: loadMoreTask)
                        } else {
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
//                            .focusEffectDisabled()
                            .buttonStyle(.borderless)
                            .onMoveLeftToProfileMenu(isLeadingGridColumn(index), perform: onMoveLeftToProfileMenu)
                        }
                    }
                }
                .padding(.bottom, 48)
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 34)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var subcategoryRail: some View {
        HStack(spacing: 24) {
            filterMenu
            genreMenu
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var filterMenu: some View {
        if viewModel.filters.isEmpty == false {
            Button {
                isFilterMenuPresented = true
            } label: {
                Label(viewModel.selectedFilter?.name ?? viewModel.filters.first?.name ?? "Сортировка", systemImage: "arrow.up.arrow.down.circle")
                    .frame(alignment: .leading)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .onMoveCommand { direction in
                if direction == .up || direction == .left {
                    onMoveLeftToProfileMenu()
                }
            }
            .alert("Сортировка", isPresented: $isFilterMenuPresented) {
                ForEach(viewModel.filters) { filter in
                    Button {
                        guard filter != viewModel.selectedFilter else { return }

                        Task {
                            await viewModel.setFilter(filter)
                        }
                    } label: {
                        Text(filter.name)
                    }
                }

                Button("Отмена", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private var genreMenu: some View {
        if viewModel.genres.isEmpty == false {
            Button {
                isGenreMenuPresented = true
            } label: {
                Label(viewModel.selectedGenre?.name ?? "Все", systemImage: "line.3.horizontal.decrease.circle")
                    .frame(alignment: .leading)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .onMoveCommand { direction in
                if direction == .up || (direction == .left && viewModel.filters.isEmpty) {
                    onMoveLeftToProfileMenu()
                }
            }
            .alert("Категория", isPresented: $isGenreMenuPresented) {
                Button {
                    Task {
                        await viewModel.setGenre(nil)
                    }
                } label: {
                    Text("Все")
                }

                ForEach(viewModel.genres) { genre in
                    Button {
                        Task {
                            await viewModel.setGenre(genre)
                        }
                    } label: {
                        Text(genre.name)
                    }
                }

                Button("Отмена", role: .cancel) {}
            }
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
            await viewModel.loadMedias()
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

struct MediaNewContentView_Previews: PreviewProvider {
    static var previews: some View {
        MediaContentView(viewModel: AppContainer.live.makeMediaContentViewModel())
    }
}
