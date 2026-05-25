import Foundation

struct ApiConstants {
    
    enum HttpMethod: String {
        case get = "GET"
        case post = "POST"
    }
    
    enum ResponseError: String, CaseIterable {
        case `default`
        case empty = "Empty Response"
        case bad = "Bad Response"
        case server = "A server error occurred"
        case mapping = "Can't map response to model"
        case authorization = "Login required on rezka.fi"
        case unknownStreamQuality = "Wrong Stream Quality"
        case emptySearch = "Please enter searched text"
        
        var code: Int {
            return 12300 + (self.index ?? .zero)
        }
    }
        
    enum Domains: String, CaseIterable {
        case rezkaConstantsApi = "RezkaConstantsApi"
        case navigationRezkaApi = "NavigationRezkaApi"
        case streamRezkaApi = "StreamRezkaApi"
    }
    
    static let contentTypeKey = "Content-Type"
    static let defaultContentType = "text/html; charset=UTF-8"
    static let formContentType = "application/x-www-form-urlencoded"
    
    
    static let userAgentKey = "User-Agent"
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 12_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15"
    
    static let AcceptTypeKey = "Accept"
    static let AcceptTypeJson = "application/json"
    static let AcceptTypeHtml = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    static let AcceptTypeImage = "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"

    static var imageHeaders: [String: String] {
        [
            userAgentKey: userAgent,
            AcceptTypeKey: AcceptTypeImage,
            "Referer": "\(ConstantsApi.server)/"
        ]
    }
}

struct DataError {
    static func generate(for domain: ApiConstants.Domains, error: ApiConstants.ResponseError) -> Error {
        if error == .authorization {
            NotificationCenter.default.post(name: .rezkaAuthorizationRequired, object: nil)
        }
        return NSError(domain: domain.rawValue, code: error.code, userInfo: [NSLocalizedDescriptionKey: error.rawValue])
    }
}

extension String {
    var isRezkaLoginPage: Bool {
        contains("action=\"/ajax/login/\"") || contains("<title>Вход</title>")
    }
}

extension Error {
    var isRezkaAuthorizationError: Bool {
        let nsError = self as NSError
        let domains = ApiConstants.Domains.allCases.map(\.rawValue)

        return nsError.code == ApiConstants.ResponseError.authorization.code
            && domains.contains(nsError.domain)
    }
}

extension Notification.Name {
    static let rezkaAuthorizationRequired = Notification.Name("rezkaAuthorizationRequired")
}
