import Foundation
import Observation

@MainActor
@Observable
final class MediaSearchContentViewModel {
    var phase = DataFetchPhase<[Media]>.fetching

    private var searchText: String?
    private let mediaRepository: MediaRepository

    private var page = 1
    private(set) var isFetching = true
    private(set) var canLoadMore = false

    var newMedias: [Media] {
        phase.value ?? []
    }

    init(search: String = "", mediaRepository: MediaRepository) {
        self.searchText = search
        self.mediaRepository = mediaRepository
    }

    func updateSearch(text: String) async {
        searchText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func submitSearch() async {
        await searchMedias()
    }
    
    func searchMedias() async {
        if Task.isCancelled { return }

        guard let search = normalizedSearchText, search.isEmpty == false else {
            phase = .success([])
            isFetching = false
            canLoadMore = false
            return
        }

        if let articles = await mediaRepository.cachedSearchResults(for: search) {
            phase = .fetchingNextPage(articles)
            canLoadMore = articles.isEmpty == false
        } else {
            phase = .fetching
            canLoadMore = false
        }
        self.page = 1

        await loadData(page: page)
    }

    func loadMore() async {
        guard isFetching == false, canLoadMore else { return }

        phase = .fetchingNextPage(newMedias)

        await loadData(page: page)
    }

    private func loadData(page: Int = 1) async {
        guard let search = normalizedSearchText, search.isEmpty == false else {
            phase = .success([])
            isFetching = false
            canLoadMore = false
            return
        }

        isFetching = true
        do {
            let categoryMedias = try await mediaRepository.search(query: search, page: page)

            isFetching = false

            if Task.isCancelled { return }
            let medias = (page == 1 ? [] : newMedias) + categoryMedias

            canLoadMore = categoryMedias.isEmpty == false
            phase = .success(medias)
            self.page = page + 1
        } catch {
            isFetching = false
            canLoadMore = false
            if Task.isCancelled { return }
            if let medias = phase.value, medias.isEmpty == false {
                phase = .success(medias)
            } else {
                phase = .failure(error)
            }
        }
    }

    private var normalizedSearchText: String? {
        searchText?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
