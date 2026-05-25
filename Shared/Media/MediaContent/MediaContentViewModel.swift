import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class MediaContentViewModel {
    var phase = DataFetchPhase<[Media]>.fetching
    private var medias: [Media] = []

    private let category: Category
    private let mediaRepository: MediaRepository

    private(set) var filters: [SubCategoryList]
    private(set) var genres: [SubCategoryList]
    private(set) var selectedFilter: SubCategoryList?
    private(set) var selectedGenre: SubCategoryList?

    private var page = 1
    private(set) var isFetching = true

    var newMedias: [Media] {
        medias
    }

    var selectedSubCategory: SubCategoryList? {
        selectedFilter ?? selectedGenre
    }

    init(
        category: Category = .general,
        filters: [SubCategoryList] = [],
        genres: [SubCategoryList] = [],
        mediaRepository: MediaRepository
    ) {
        self.category = category
        self.filters = filters
        self.genres = genres
        self.mediaRepository = mediaRepository
        selectedFilter = Self.defaultFilter(from: filters)
        selectedGenre = nil
    }

    func setFilter(_ filter: SubCategoryList) async {
        withoutAnimation {
            selectedFilter = filter
        }
        await loadMedias()
    }

    func setGenre(_ genre: SubCategoryList?) async {
        withoutAnimation {
            selectedGenre = genre
        }
        await loadMedias()
    }
    
    func loadMedias() async {
        if Task.isCancelled { return }

        if let articles = await mediaRepository.cachedMediaList(
            category: category,
            filter: selectedFilter,
            genre: selectedGenre
        ) {
            withoutAnimation {
                medias = articles
                phase = .fetchingNextPage(articles)
            }
        } else {
            withoutAnimation {
                phase = .fetching
            }
        }
        self.page = 1
        
        await loadData(page: page)
    }
    
    func loadMore() async {
        if isFetching == false {
            withoutAnimation {
                phase = .fetchingNextPage(newMedias)
            }
            
            await loadData(page: page)
        }
    }
    
    private func loadData(page: Int = 1) async {
        let filter = selectedFilter
        let genre = selectedGenre

        isFetching = true
        do {
            let categoryMedias = try await mediaRepository.refreshMediaList(
                category: category,
                filter: filter,
                genre: genre,
                page: page
            )
            if Task.isCancelled { return }

            let currentMedias = page == 1 ? [] : newMedias.filter { $0.category != .loadMore }
            let updatedMedias = currentMedias + categoryMedias
            let displayMedias = categoryMedias.isEmpty ? updatedMedias : updatedMedias + [.empty]

            withoutAnimation {
                medias = displayMedias
                phase = .success(medias)
            }
            self.page = page + 1
            isFetching = false
            
        } catch {
            if Task.isCancelled { return }
            if medias.isEmpty == false {
                withoutAnimation {
                    phase = .success(medias)
                }
            } else {
                phase = .failure(error)
            }
            isFetching = false
        }
    }

    private func withoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    }

    private static func defaultFilter(from filters: [SubCategoryList]) -> SubCategoryList? {
        filters.first(where: \.isNowWatchingFilter)
            ?? filters.first(where: \.isPopularFilter)
            ?? filters.first
    }
}

private extension SubCategoryList {
    var isNowWatchingFilter: Bool {
        let normalizedName = normalizedFilterName
        let normalizedURI = uri.lowercased()

        return (normalizedName.contains("сейчас") && normalizedName.contains("смотр"))
            || normalizedURI.contains("watching")
            || normalizedURI.contains("now")
    }

    var isPopularFilter: Bool {
        let normalizedName = normalizedFilterName
        let normalizedURI = uri.lowercased()

        return normalizedName.contains("популяр")
            || normalizedName.contains("popular")
            || normalizedURI.contains("popular")
    }

    private var normalizedFilterName: String {
        name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
