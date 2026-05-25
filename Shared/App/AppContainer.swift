import Foundation
import Observation

@Observable
final class AppContainer {
    let authorizationService: RezkaAuthorizationService
    let navigationRepository: NavigationRepository
    let mediaRepository: MediaRepository

    static let live = AppContainer(
        authorizationService: .shared,
        navigationRepository: LiveNavigationRepository(),
        mediaRepository: LiveMediaRepository()
    )

    init(
        authorizationService: RezkaAuthorizationService,
        navigationRepository: NavigationRepository,
        mediaRepository: MediaRepository
    ) {
        self.authorizationService = authorizationService
        self.navigationRepository = navigationRepository
        self.mediaRepository = mediaRepository
    }

    @MainActor
    func makeContentViewModel() -> ContentViewModel {
        ContentViewModel(navigationRepository: navigationRepository)
    }

    @MainActor
    func makeMediaContentViewModel(
        category: Category = .general,
        filters: [SubCategoryList] = [],
        genres: [SubCategoryList] = []
    ) -> MediaContentViewModel {
        MediaContentViewModel(
            category: category,
            filters: filters,
            genres: genres,
            mediaRepository: mediaRepository
        )
    }

    @MainActor
    func makeSearchViewModel(search: String = "") -> MediaSearchContentViewModel {
        MediaSearchContentViewModel(search: search, mediaRepository: mediaRepository)
    }
}
