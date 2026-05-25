import Foundation

struct NavigationPayload: Codable {
    let categories: [CategoryList]
    let userProfile: RezkaUserProfile?
}

struct RezkaUserProfile: Codable, Equatable {
    let displayName: String
    let avatarURLString: String?

    var avatarURL: URL? {
        guard let avatarURLString, avatarURLString.isEmpty == false else {
            return nil
        }

        return URL(string: avatarURLString)
    }
}

protocol NavigationRepository {
    func cachedNavigation() async -> NavigationPayload?
    func refreshNavigation() async throws -> NavigationPayload
}

protocol MediaRepository {
    func cachedMediaList(category: Category, filter: SubCategoryList?, genre: SubCategoryList?) async -> [Media]?
    func refreshMediaList(category: Category, filter: SubCategoryList?, genre: SubCategoryList?, page: Int) async throws -> [Media]
    func cachedSearchResults(for query: String) async -> [Media]?
    func search(query: String, page: Int) async throws -> [Media]
    func fetchDetails(from media: Media, translation: Int?) async throws -> DetailedMedia
    func fetchSeriesDetails(for media: DetailedMedia, translation: Int) async throws -> DetailedMedia
    func seasons(mediaId: Int, translationId: Int) async throws -> SeasonsData
    func stream(mediaId: Int, translationId: Int, season: Int?, episode: Int?) async throws -> StreamMedia
}

struct LiveNavigationRepository: NavigationRepository {
    private let api = NavigationRezkaApi()
    private let cache = DiskCache<NavigationPayload>(filename: "navigationcache", expirationInterval: 5 * 60)

    func cachedNavigation() async -> NavigationPayload? {
        try? await cache.loadFromDisk()
        return await cache.value(forKey: CacheKeys.categoriesList)
    }

    func refreshNavigation() async throws -> NavigationPayload {
        let navigation = try await api.fetch()
        await cache.setValue(navigation, forKey: CacheKeys.categoriesList)
        try? await cache.saveToDisk()
        return navigation
    }
}

struct LiveMediaRepository: MediaRepository {
    private let api = MediaRezkaApi()
    private let mediaCache = DiskCache<[Media]>(filename: "xcamediacache", expirationInterval: 30 * 60)
    private let searchCache = DiskCache<[Media]>(filename: "xcasearchcache", expirationInterval: 5 * 60)

    func cachedMediaList(category: Category, filter: SubCategoryList?, genre: SubCategoryList?) async -> [Media]? {
        try? await mediaCache.loadFromDisk()
        return await mediaCache.value(forKey: CacheKeys.mediaList(category: category, filter: filter, genre: genre))
    }

    func refreshMediaList(category: Category, filter: SubCategoryList?, genre: SubCategoryList?, page: Int) async throws -> [Media] {
        let medias = try await api.fetch(from: category, filter: filter, genre: genre, page: page)
        if page == 1 {
            await mediaCache.setValue(medias, forKey: CacheKeys.mediaList(category: category, filter: filter, genre: genre))
            try? await mediaCache.saveToDisk()
        }
        return medias
    }

    func cachedSearchResults(for query: String) async -> [Media]? {
        try? await searchCache.loadFromDisk()
        return await searchCache.value(forKey: CacheKeys.search(query: query))
    }

    func search(query: String, page: Int) async throws -> [Media] {
        let medias = try await api.search(for: query, page: page)
        if page == 1 {
            await searchCache.setValue(medias, forKey: CacheKeys.search(query: query))
            try? await searchCache.saveToDisk()
        }
        return medias
    }

    func fetchDetails(from media: Media, translation: Int? = nil) async throws -> DetailedMedia {
        try await api.fetchDetails(from: media, translation: translation)
    }

    func fetchSeriesDetails(for media: DetailedMedia, translation: Int) async throws -> DetailedMedia {
        try await api.fetchSeriesDetails(for: media, translation: translation)
    }

    func seasons(mediaId: Int, translationId: Int) async throws -> SeasonsData {
        try await api.seasons(mediaId: mediaId, translationId: translationId)
    }

    func stream(mediaId: Int, translationId: Int, season: Int?, episode: Int?) async throws -> StreamMedia {
        try await api.stream(mediaId: mediaId, translationId: translationId, season: season, episode: episode)
    }
}

private enum CacheKeys {
    static let categoriesList = "categories_list"

    static func mediaList(category: Category, filter: SubCategoryList?, genre: SubCategoryList?) -> String {
        [
            category.rawValue,
            filter?.uri ?? "default",
            genre?.uri ?? "all"
        ].joined(separator: "_")
    }

    static func search(query: String) -> String {
        "search_media_list_\(query.lowercased())"
    }
}
