import Foundation

struct NavigationRezkaApi {

    private let session = RezkaURLSession.shared
    
    func fetch() async throws -> NavigationPayload {
        try await fetchNavigation(from: generateNavigationUrl())
    }
    
    private func fetchNavigation(from url: URL) async throws -> NavigationPayload {
        let request = request(for: url)
        
        let (data, response) = try await session.data(for: request)
        
        guard let response = response as? HTTPURLResponse else {
            throw DataError.generate(for: .navigationRezkaApi, error: .bad)
        }
        
        switch response.statusCode {
        case 200...299:
            let html = String(decoding: data, as: UTF8.self)
            guard !html.isEmpty else {
                throw DataError.generate(for: .navigationRezkaApi, error: .empty)
            }

            guard !html.isRezkaLoginPage else {
                throw DataError.generate(for: .navigationRezkaApi, error: .authorization)
            }
            
            let response = try NavigationRezkaApiResponse(from: html)
            return NavigationPayload(categories: response.categories, userProfile: response.userProfile)
        default:
            throw DataError.generate(for: .navigationRezkaApi, error: .server)
        }
    }
    
    func generateNavigationUrl() -> URL {
        URL(string: ConstantsApi.server)!
    }
    
    private func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = ApiConstants.HttpMethod.get.rawValue
        request.setValue(ApiConstants.userAgent, forHTTPHeaderField: ApiConstants.userAgentKey)
        request.addValue(ApiConstants.defaultContentType, forHTTPHeaderField: ApiConstants.contentTypeKey)
        request.addValue(ApiConstants.AcceptTypeHtml, forHTTPHeaderField: ApiConstants.AcceptTypeKey)
        return request
    }
}
