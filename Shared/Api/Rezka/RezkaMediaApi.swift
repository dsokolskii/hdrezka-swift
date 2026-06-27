import Foundation

struct MediaRezkaApi {
    
    private let session = RezkaURLSession.shared
    
    func fetch(from category: Category, subCategory: SubCategoryList?, page: Int = 1) async throws -> [Media] {
        try await fetch(from: category, filter: subCategory, genre: nil, page: page)
    }

    func fetch(from category: Category, filter: SubCategoryList?, genre: SubCategoryList?, page: Int = 1) async throws -> [Media] {
        try await fetchMedias(from: generateNewMediaURL(from: category, filter: filter, genre: genre, page: page))
    }

    /// Подборки новинок с главной сайта: AJAX-endpoint
    /// `/engine/ajax/get_newest_slider_content.php?cat_id=<id>`.
    func fetchNewestSlider(category: Category) async throws -> [Media] {
        guard let catId = category.sliderCatId else {
            throw DataError.generate(for: .rezkaConstantsApi, error: .bad)
        }
        return try await fetchMedias(using: sliderRequest(for: catId))
    }
    
    func fetchDetails(from media: Media, translation: Int? = nil) async throws -> DetailedMedia {
        var detailedMedia = try await fetchMedia(from: media.mediaURL)
        guard let currentTranslationId = translation ?? detailedMedia.translations.keys.first else {
            throw DataError.generate(for: .rezkaConstantsApi, error: .mapping)
        }
        
        if media.isSeries {
            detailedMedia = try await fetchSeriesDetails(for: detailedMedia, translation: currentTranslationId)
        }
        
        return detailedMedia
    }
    
    func fetchSeriesDetails(for media: DetailedMedia, translation: Int) async throws -> DetailedMedia {
        var detailedMedia = media
        let seasons = try await seasons(mediaId: detailedMedia.mediaId, translationId: translation)
        detailedMedia.setup(seasons: seasons, for: translation)
        
        return detailedMedia
    }
    
    func search(for query: String, page: Int = 1) async throws -> [Media] {
        try await fetchMedias(from: generateSearchURL(from: query, page: page))
    }
    
    func seasons(mediaId: Int, translationId: Int) async throws -> SeasonsData {
        try await fetchSeasons(mediaId: mediaId, translationId: translationId)
    }
    
    func stream(mediaId: Int, translationId: Int, season: Int?, episode: Int?) async throws -> StreamMedia {
        let request = streamRequest(mediaId: mediaId, translationId: translationId, season: season, episode: episode)
        
        let (data, response) = try await session.data(for: request)
        
        guard let response = response as? HTTPURLResponse else {
            throw DataError.generate(for: .rezkaConstantsApi, error: .bad)
        }
        
        switch response.statusCode {
            
        case (200...299), (400...499):
            let dirtyBase64 = String(decoding: data, as: UTF8.self)
            guard !dirtyBase64.isEmpty else {
                throw DataError.generate(for: .rezkaConstantsApi, error: .empty)
            }

            guard !dirtyBase64.isRezkaLoginPage else {
                throw DataError.generate(for: .rezkaConstantsApi, error: .authorization)
            }
            
            return try StreamRezkaApiResponse(from: dirtyBase64, isJson: true).streams
        default:
            throw DataError.generate(for: .rezkaConstantsApi, error: .server)
        }
    }
    
    private func fetchMedias(from url: URL) async throws -> [Media] {
        try await fetchMedias(using: request(for: url))
    }

    private func fetchMedias(using request: URLRequest) async throws -> [Media] {
        let (data, response) = try await session.data(for: request)
        
        guard let response = response as? HTTPURLResponse else {
            throw DataError.generate(for: .rezkaConstantsApi, error: .bad)
        }
        
        switch response.statusCode {
        case 200...299:
            let html = String(decoding: data, as: UTF8.self)
            guard html.isEmpty == false else {
                throw DataError.generate(for: .rezkaConstantsApi, error: .empty)
            }

            guard html.isRezkaLoginPage == false else {
                throw DataError.generate(for: .rezkaConstantsApi, error: .authorization)
            }
            
            return try MediaRezkaAPIResponse(from: html).medias
        default:
            throw DataError.generate(for: .rezkaConstantsApi, error: .server)
        }
    }
    
    private func fetchMedia(from url: URL) async throws -> DetailedMedia {
        let request = request(for: url)
        
        let (data, response) = try await session.data(for: request)
        
        guard let response = response as? HTTPURLResponse else {
            throw DataError.generate(for:. rezkaConstantsApi, error: .bad)
        }
        
        switch response.statusCode {
        case 200...299:
            let html = String(decoding: data, as: UTF8.self)
            guard !html.isEmpty else {
                throw DataError.generate(for: .rezkaConstantsApi, error: .empty)
            }

            guard !html.isRezkaLoginPage else {
                throw DataError.generate(for: .rezkaConstantsApi, error: .authorization)
            }
            
            return try DetailedMediaRezkaAPIResponse(from: html).detailedMedia
        default:
            throw DataError.generate(for: .rezkaConstantsApi, error: .server)
        }
    }
    
    private func fetchSeasons(mediaId: Int, translationId: Int) async throws -> SeasonsData {
        let request = seasonsRequest(mediaId: mediaId, translationId: translationId)
        
        let (data, response) = try await session.data(for: request)
        
        guard let response = response as? HTTPURLResponse else {
            throw DataError.generate(for: .rezkaConstantsApi, error: .bad)
        }
        
        switch response.statusCode {
            
        case (200...299), (400...499):
            let html = String(decoding: data, as: UTF8.self)
            guard !html.isEmpty else {
                throw DataError.generate(for:.rezkaConstantsApi, error: .empty)
            }

            guard !html.isRezkaLoginPage else {
                throw DataError.generate(for: .rezkaConstantsApi, error: .authorization)
            }
            
            guard let object = try? JSONDecoder().decode(SeasonsData.self , from: data) else {
                throw DataError.generate(for: .rezkaConstantsApi, error: .mapping)
            }
            
            return object
            
        default:
            throw DataError.generate(for: .rezkaConstantsApi, error: .server)
        }
    }
    
    private func generateSearchURL(from query: String, page: Int = 1) -> URL {
        var urlComponents = URLComponents(string: "\(ConstantsApi.server)/search")
        urlComponents?.queryItems = [URLQueryItem(name: "do", value: "search"),
                                     URLQueryItem(name: "subaction", value: "search"),
                                     URLQueryItem(name: "q", value: query),
        ]
        if page > 1 {
            urlComponents?.queryItems?.append(URLQueryItem(name: "page", value: "\(page)"))
        }
        
        return (urlComponents?.url)!
    }

    private func generateNewestSliderURL(catId: Int) -> URL {
        var components = URLComponents(string: "\(ConstantsApi.server)/engine/ajax/get_newest_slider_content.php")!
        components.queryItems = [URLQueryItem(name: "cat_id", value: "\(catId)")]
        return components.url!
    }
    
    private func generateNewMediaURL(from category: Category, filter: SubCategoryList?, genre: SubCategoryList?, page: Int = 1) -> URL {
        var pathComponents: [String] = []
        var queryItems: [URLQueryItem] = []

        if category != .general && category != .new {
            pathComponents.append(category.rawValue)
        }

        apply(route: genre?.uri, to: &pathComponents, queryItems: &queryItems)
        apply(route: filter?.uri, to: &pathComponents, queryItems: &queryItems)

        if page > 1 {
            pathComponents.append(contentsOf: ["page", "\(page)"])
        }

        var components = URLComponents(string: ConstantsApi.server)!
        components.path = pathComponents.isEmpty ? "" : "/" + pathComponents.joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        return components.url!
    }

    private func apply(route: String?, to pathComponents: inout [String], queryItems: inout [URLQueryItem]) {
        guard let route, route.isEmpty == false else {
            return
        }

        if route.contains("/") || route.contains("?") {
            let normalizedRoute = route.hasPrefix("/") ? route : "/" + route
            guard
                let url = URL(string: normalizedRoute, relativeTo: URL(string: ConstantsApi.server)),
                let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
            else {
                return
            }

            let routePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if routePath.isEmpty == false {
                pathComponents = routePath.split(separator: "/").map(String.init)
            }

            if let items = components.queryItems, items.isEmpty == false {
                queryItems = items
            }

            return
        }

        pathComponents.append(route)
    }
    
    private func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = ApiConstants.HttpMethod.get.rawValue
        request.setValue(ApiConstants.userAgent, forHTTPHeaderField: ApiConstants.userAgentKey)
        request.addValue(ApiConstants.defaultContentType, forHTTPHeaderField: ApiConstants.contentTypeKey)
        request.addValue(ApiConstants.AcceptTypeHtml, forHTTPHeaderField: ApiConstants.AcceptTypeKey)
        return request
    }

    private func sliderRequest(for catId: Int) -> URLRequest {
        var request = URLRequest(url: generateNewestSliderURL(catId: catId))
        request.httpMethod = ApiConstants.HttpMethod.get.rawValue
        request.setValue(ApiConstants.userAgent, forHTTPHeaderField: ApiConstants.userAgentKey)
        request.setValue("\(ConstantsApi.server)/", forHTTPHeaderField: "Referer")
        request.setValue(ConstantsApi.server, forHTTPHeaderField: "Origin")
        request.setValue(ApiConstants.AcceptTypeHtml, forHTTPHeaderField: ApiConstants.AcceptTypeKey)
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        return request
    }
    
    private func seasonsRequest(mediaId: Int, translationId: Int) -> URLRequest {
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [URLQueryItem(name: "id", value: "\(mediaId)"),
                                     URLQueryItem(name: "translator_id", value: "\(translationId)"),
                                     URLQueryItem(name: "action", value: "get_episodes"),
        ]
        
        var request = URLRequest(url: URL(string: "\(ConstantsApi.server)/ajax/get_cdn_series/")!)
        request.httpMethod = ApiConstants.HttpMethod.post.rawValue
        request.httpBody = bodyComponents.query?.data(using: .utf8)
        request.setValue(ApiConstants.userAgent, forHTTPHeaderField: ApiConstants.userAgentKey)
        request.addValue(ApiConstants.formContentType, forHTTPHeaderField: ApiConstants.contentTypeKey)
        request.addValue(ApiConstants.AcceptTypeJson, forHTTPHeaderField: ApiConstants.AcceptTypeKey)
        return request
    }
    
    private func streamRequest(mediaId: Int, translationId: Int, season: Int?, episode: Int?) -> URLRequest {
        var bodyComponents = URLComponents()
        var additionalData = [URLQueryItem]()
        
        if let season = season, let episode = episode {
            additionalData = [URLQueryItem(name: "season", value: "\(season)"),
                              URLQueryItem(name: "episode", value: "\(episode)"),
                              URLQueryItem(name: "action", value: "get_stream")]
        } else {
            additionalData = [URLQueryItem(name: "action", value: "get_movie")]
        }
        
        bodyComponents.queryItems = [URLQueryItem(name: "id", value: "\(mediaId)"),
                                     URLQueryItem(name: "translator_id", value: "\(translationId)")]
        
        bodyComponents.queryItems?.append(contentsOf: additionalData)
        
        var request = URLRequest(url: URL(string: "\(ConstantsApi.server)/ajax/get_cdn_series/")!)
        request.httpMethod = ApiConstants.HttpMethod.post.rawValue
        request.httpBody = bodyComponents.query?.data(using: .utf8)
        request.setValue(ApiConstants.userAgent, forHTTPHeaderField: ApiConstants.userAgentKey)
        request.addValue(ApiConstants.formContentType, forHTTPHeaderField: ApiConstants.contentTypeKey)
        request.addValue(ApiConstants.AcceptTypeJson, forHTTPHeaderField: ApiConstants.AcceptTypeKey)
        return request
    }
}
