import Foundation
import Observation

@MainActor
@Observable
final class ContentViewModel {
    var phase = DataFetchPhase<NavigationPayload>.fetching
    private(set) var isFetching = true

    private let navigationRepository: NavigationRepository

    init(navigationRepository: NavigationRepository) {
        self.navigationRepository = navigationRepository
    }

    var categories: [CategoryList] {
        (phase.value?.categories ?? []).normalizedForNavigation
    }

    var userProfile: RezkaUserProfile? {
        phase.value?.userProfile
    }

    func load() async {
        if Task.isCancelled { return }

        if let navigation = await navigationRepository.cachedNavigation() {
            phase = .fetchingNextPage(navigation)
        } else {
            phase = .fetching
        }

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
                phase = .failure(error)
            }
            isFetching = false
        }
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
