import Foundation
import Observation

@MainActor
@Observable
final class ContentViewModel {
    var phase: DataFetchPhase<NavigationPayload>
    private(set) var isFetching = true

    private let navigationRepository: NavigationRepository

    init(navigationRepository: NavigationRepository) {
        self.navigationRepository = navigationRepository
        self.phase = .fetchingNextPage(ContentViewModel.defaultPayload)
    }

    var categories: [CategoryList] {
        Self.mergedCategories(from: phase.value).normalizedForNavigation
    }

    var userProfile: RezkaUserProfile? {
        phase.value?.userProfile
    }

    func load() async {
        if Task.isCancelled { return }

        let initialPayload: NavigationPayload
        if let cached = await navigationRepository.cachedNavigation() {
            initialPayload = cached
        } else {
            initialPayload = Self.defaultPayload
        }
        phase = .fetchingNextPage(initialPayload)

        await loadNavigation()
    }

    private func loadNavigation() async {
        isFetching = true
        do {
            let navigation = try await navigationRepository.refreshNavigation()
            if Task.isCancelled { return }

            phase = .success(navigation)
            isFetching = false
        } catch {
            if Task.isCancelled { return }
            if let currentNavigation = phase.value, currentNavigation.categories.isEmpty == false {
                phase = .success(currentNavigation)
            } else {
                phase = .success(Self.defaultPayload)
            }
            isFetching = false
        }
    }

    // MARK: - Default categories

    /// Локальные категории, которые показываются сразу при запуске, не дожидаясь
    /// ответа сервера. Серверные данные (с фильтрами и жанрами) мерджатся поверх,
    /// когда навигация успешно загружается.
    private static let defaultCategories: [CategoryList] = [
        CategoryList(type: .search, items: [], name: "Поиск", iconName: "magnifyingglass"),
        CategoryList(type: .films, items: [], filters: [], genres: [], name: "Фильмы", iconName: ""),
        CategoryList(type: .series, items: [], filters: [], genres: [], name: "Сериалы", iconName: ""),
        CategoryList(type: .animation, items: [], filters: [], genres: [], name: "Аниме", iconName: ""),
        CategoryList(type: .cartoons, items: [], filters: [], genres: [], name: "Мультфильмы", iconName: ""),
        CategoryList(type: .new, items: [], filters: [], genres: [], name: "Новинки", iconName: "")
    ]

    static let defaultPayload = NavigationPayload(categories: defaultCategories, userProfile: nil)

    /// Объединяет серверные категории с локальными дефолтными: серверные имеют
    /// приоритет (в них есть фильтры и жанры), а недостающие типы берутся из дефолта.
    static func mergedCategories(from payload: NavigationPayload?) -> [CategoryList] {
        let serverCategories = payload?.categories ?? []
        guard serverCategories.isEmpty == false else {
            return defaultCategories
        }

        let serverTypes = Set(serverCategories.map { $0.type })
        let missing = defaultCategories.filter { serverTypes.contains($0.type) == false }
        return serverCategories + missing
    }
}

private extension Array where Element == CategoryList {
    var normalizedForNavigation: [CategoryList] {
        let normalized = filter { $0.type != .collections && $0.type != .announce }
            .map { category in
                CategoryList(
                    id: category.id,
                    type: category.type,
                    items: category.items,
                    filters: category.filters,
                    genres: category.genres,
                    name: category.type == .new ? "Новинки" : category.name,
                    iconName: category.iconName
                )
            }

        let preferredOrder: [Category] = [.search, .films, .series, .animation, .cartoons, .general, .new]
        return normalized.sorted { lhs, rhs in
            let lhsIndex = preferredOrder.firstIndex(of: lhs.type) ?? preferredOrder.count
            let rhsIndex = preferredOrder.firstIndex(of: rhs.type) ?? preferredOrder.count
            return lhsIndex == rhsIndex ? lhs.name < rhs.name : lhsIndex < rhsIndex
        }
    }
}
