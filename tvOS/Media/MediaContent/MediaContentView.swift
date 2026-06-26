import Observation
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

struct MediaHomeShelfDescriptor {
    let category: Category
    let title: String
}

struct MediaHomeShelfItem: Identifiable {
    let media: Media
    let autoResumePlaybackPosition: Double?

    var id: String {
        media.id
    }
}

struct MediaHomeShelf: Identifiable {
    let descriptor: MediaHomeShelfDescriptor
    let items: [MediaHomeShelfItem]

    var id: Category {
        descriptor.category
    }
}

@MainActor
@Observable
final class MediaHomeViewModel {
    var phase = DataFetchPhase<[MediaHomeShelf]>.fetching

    private let descriptors: [MediaHomeShelfDescriptor]
    private let mediaRepository: MediaRepository

    var shelves: [MediaHomeShelf] {
        phase.value ?? []
    }

    init(mediaRepository: MediaRepository) {
        self.descriptors = Self.defaultDescriptors
        self.mediaRepository = mediaRepository
    }

    func load() async {
        if Task.isCancelled { return }

        let cachedShelves = await loadCachedShelves()
        if Task.isCancelled { return }

        phase = cachedShelves.isEmpty ? .fetching : .fetchingNextPage(cachedShelves)

        var refreshedShelves: [MediaHomeShelf] = continueWatchingShelf().map { [$0] } ?? []
        var firstError: Error?

        for descriptor in descriptors {
            do {
                let medias = try await mediaRepository.refreshMediaList(
                    category: descriptor.category,
                    filter: nil,
                    genre: nil,
                    page: 1
                )

                if Task.isCancelled { return }

                guard medias.isEmpty == false else {
                    continue
                }

                refreshedShelves.append(Self.makeShelf(from: descriptor, medias: medias))
            } catch {
                if Task.isCancelled { return }
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if refreshedShelves.isEmpty == false {
            phase = .success(refreshedShelves)
        } else if cachedShelves.isEmpty == false {
            phase = .success(cachedShelves)
        } else if let firstError {
            phase = .failure(firstError)
        } else {
            phase = .success([])
        }
    }

    private func loadCachedShelves() async -> [MediaHomeShelf] {
        var cachedShelves: [MediaHomeShelf] = continueWatchingShelf().map { [$0] } ?? []

        for descriptor in descriptors {
            guard
                let medias = await mediaRepository.cachedMediaList(
                    category: descriptor.category,
                    filter: nil,
                    genre: nil
                ),
                medias.isEmpty == false
            else {
                continue
            }

            cachedShelves.append(Self.makeShelf(from: descriptor, medias: medias))
        }

        return cachedShelves
    }

    private static func makeShelf(from descriptor: MediaHomeShelfDescriptor, medias: [Media]) -> MediaHomeShelf {
        MediaHomeShelf(
            descriptor: descriptor,
            items: Array(medias.prefix(12)).map {
                MediaHomeShelfItem(media: $0, autoResumePlaybackPosition: nil)
            }
        )
    }

    private func continueWatchingShelf() -> MediaHomeShelf? {
        let items = (ContinueWatchingStore.load()?.items ?? [])
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(12)
            .map { item in
                MediaHomeShelfItem(
                    media: Media(
                        title: item.title,
                        url: item.mediaURL,
                        descriptionShort: item.subtitle,
                        description: nil,
                        coverUrl: item.coverURL,
                        seriesInfo: item.isSeries ? seriesInfo(for: item) : nil,
                        category: item.isSeries ? .series : .films,
                        quality: .unknown
                    ),
                    autoResumePlaybackPosition: item.playbackPosition
                )
            }

        guard items.isEmpty == false else {
            return nil
        }

        return MediaHomeShelf(
            descriptor: MediaHomeShelfDescriptor(
                category: .general,
                title: "Продолжить просмотр"
            ),
            items: items
        )
    }

    private func seriesInfo(for item: ContinueWatchingPayload.Item) -> String? {
        let parts = [item.seasonTitle, item.episodeTitle]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        if parts.isEmpty {
            return "Сериал"
        }

        return parts.joined(separator: " • ")
    }

    private static let defaultDescriptors = [
        MediaHomeShelfDescriptor(
            category: .films,
            title: "Фильмы"
        ),
        MediaHomeShelfDescriptor(
            category: .series,
            title: "Сериалы"
        ),
        MediaHomeShelfDescriptor(
            category: .animation,
            title: "Аниме"
        ),
        MediaHomeShelfDescriptor(
            category: .cartoons,
            title: "Мультфильмы"
        )
    ]
}

struct MediaHomeView: View {
    @State private var viewModel: MediaHomeViewModel
    @StateObject private var bookmarkViewModel = MediaBookmarksViewModel.shared

    private let onMoveLeftToProfileMenu: () -> Void

    init(viewModel: MediaHomeViewModel, onMoveLeftToProfileMenu: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: viewModel)
        self.onMoveLeftToProfileMenu = onMoveLeftToProfileMenu
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 38) {
                    ForEach(viewModel.shelves) { shelf in
                        shelfSection(shelf)
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 34)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            .allowsHitTesting(isBlockingOverlayPresented == false)

            overlayView
        }
        .onFirstAppear(refreshTask)
    }

    private func shelfSection(_ shelf: MediaHomeShelf) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(systemName: shelf.descriptor.category.homeShelfIcon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text(shelf.descriptor.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: AppTheme.gridSpacing) {
                    ForEach(Array(shelf.items.enumerated()), id: \.element.id) { index, item in
                        let media = item.media
                        let isBookmarked = bookmarkViewModel.isBookmarked(for: media)

                        NavigationLink {
                            DetailedMediaItemView(
                                viewModel: DetailedMediaItemViewModel(media: media),
                                bookmarkViewModel: bookmarkViewModel,
                                autoResumePlaybackPosition: item.autoResumePlaybackPosition,
                                onMoveLeftToProfileMenu: onMoveLeftToProfileMenu
                            )
                        } label: {
                            MediaItemViewView(media: media, isBookmarked: isBookmarked)
                                .frame(
                                    width: MediaItemViewView.coverSize.width,
                                    height: MediaItemViewView.coverSize.height
                                )
                        }
                        .frame(
                            width: MediaItemViewView.coverSize.width,
                            height: MediaItemViewView.coverSize.height
                        )
                        .buttonStyle(.borderless)
                        .onMoveLeftToProfileMenu(index == 0, perform: onMoveLeftToProfileMenu)
                    }
                }
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .focusSection()
        }
    }

    @ViewBuilder
    private var overlayView: some View {
        switch viewModel.phase {
        case .fetching:
            LoadingPanel()
        case .success(let shelves) where shelves.isEmpty:
            EmptyPlaceholderView(text: "Нет подборок", image: nil)
        case .failure(let error):
            RetryView(text: error.localizedDescription, retryAction: refreshTask)
        default:
            EmptyView()
        }
    }

    private func refreshTask() {
        Task {
            await viewModel.load()
        }
    }

    private var isBlockingOverlayPresented: Bool {
        switch viewModel.phase {
        case .fetching:
            true
        case .success(let shelves):
            shelves.isEmpty
        case .failure:
            true
        case .fetchingNextPage:
            false
        }
    }
}

private extension Category {
    var homeShelfIcon: String {
        switch self {
        case .general:
            "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .films:
            "film.stack.fill"
        case .series:
            "tv.fill"
        case .animation:
            "sparkles.tv.fill"
        case .cartoons:
            "popcorn.fill"
        default:
            "play.square.stack.fill"
        }
    }
}

struct MediaNewContentView_Previews: PreviewProvider {
    static var previews: some View {
        MediaContentView(viewModel: AppContainer.live.makeMediaContentViewModel())
    }
}
