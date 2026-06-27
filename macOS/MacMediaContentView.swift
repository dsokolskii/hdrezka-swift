#if os(macOS)
import SwiftUI

struct MacMediaContentView: View {
    @State private var viewModel: MediaContentViewModel
    @StateObject private var bookmarkViewModel = MediaBookmarksViewModel.shared

    @State private var isFilterMenuPresented = false
    @State private var isGenreMenuPresented = false

    let pageTitle: String

    init(viewModel: MediaContentViewModel, pageTitle: String) {
        _viewModel = State(initialValue: viewModel)
        self.pageTitle = pageTitle
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    pageHeader

                    subcategoryRail

                    if let featuredMedia {
                        featuredMediaHero(featuredMedia)
                    }

                    LazyVGrid(columns: columns, alignment: .center, spacing: AppTheme.gridSpacing) {
                        ForEach(Array(gridMedias.enumerated()), id: \.element.id) { _, media in
                            if media.category == .loadMore {
                                Color.clear
                                    .frame(width: MediaItemViewView.coverSize.width, height: 1)
                                    .onAppear(perform: loadMoreTask)
                            } else {
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
                        }
                    }
                    .padding(.bottom, 48)
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 24)
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            .allowsHitTesting(isBlockingOverlayPresented == false)

            overlayView
        }
        .onFirstAppear(refreshTask)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pageTitle)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if let filterName = viewModel.selectedFilter?.name {
                Text(filterName)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 150, maximum: 170), spacing: AppTheme.gridSpacing, alignment: .top)
        ]
    }

    private var mediaItems: [Media] {
        viewModel.newMedias.filter { $0.category != .loadMore }
    }

    private var featuredMedia: Media? {
        mediaItems.first
    }

    private var hasLoadMoreMarker: Bool {
        viewModel.newMedias.contains { $0.category == .loadMore }
    }

    private var gridMedias: [Media] {
        let remainingItems = Array(mediaItems.dropFirst())
        return hasLoadMoreMarker ? remainingItems + [.empty] : remainingItems
    }

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
            Menu {
                ForEach(viewModel.filters) { filter in
                    Button {
                        guard filter != viewModel.selectedFilter else { return }

                        Task {
                            await viewModel.setFilter(filter)
                        }
                    } label: {
                        if filter == viewModel.selectedFilter {
                            Label(filter.name, systemImage: "checkmark")
                        } else {
                            Text(filter.name)
                        }
                    }
                }
            } label: {
                Label(
                    viewModel.selectedFilter?.name ?? viewModel.filters.first?.name ?? "Сортировка",
                    systemImage: "arrow.up.arrow.down.circle"
                )
                .frame(alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var genreMenu: some View {
        if viewModel.genres.isEmpty == false {
            Menu {
                Button {
                    Task {
                        await viewModel.setGenre(nil)
                    }
                } label: {
                    if viewModel.selectedGenre == nil {
                        Label("Все", systemImage: "checkmark")
                    } else {
                        Text("Все")
                    }
                }

                ForEach(viewModel.genres) { genre in
                    Button {
                        Task {
                            await viewModel.setGenre(genre)
                        }
                    } label: {
                        if genre == viewModel.selectedGenre {
                            Label(genre.name, systemImage: "checkmark")
                        } else {
                            Text(genre.name)
                        }
                    }
                }
            } label: {
                Label(viewModel.selectedGenre?.name ?? "Все", systemImage: "line.3.horizontal.decrease.circle")
                    .frame(alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .controlSize(.large)
        }
    }

    private func featuredMediaHero(_ media: Media) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.panelStrong)

            if let coverURL = media.coverURL {
                CacheAsyncImage(
                    url: coverURL,
                    targetSize: CGSize(width: 1600, height: 600),
                    session: RezkaURLSession.shared,
                    requestHeaders: ApiConstants.imageHeaders
                ) { phase in
                    phase.view
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }

            LinearGradient(
                colors: [.black.opacity(0.12), .black.opacity(0.28), .black.opacity(0.92)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(media.isSeries ? "Сериал" : "Фильм")
                        .font(.caption.weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.72))

                    Text(media.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(3)

                    if media.descriptionShort.isEmpty == false {
                        Text(media.descriptionShort)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(3)
                    }

                    NavigationLink {
                        DetailedMediaItemView(
                            viewModel: DetailedMediaItemViewModel(media: media),
                            bookmarkViewModel: bookmarkViewModel
                        )
                    } label: {
                        Label("Открыть", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Spacer(minLength: 0)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
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
            await viewModel.loadMedias()
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
