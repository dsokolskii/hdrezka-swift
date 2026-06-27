import Foundation
import Security

private struct PersistedCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool

    init(cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.expiresDate = cookie.expiresDate
        self.isSecure = cookie.isSecure
    }

    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]

        if let expiresDate {
            properties[.expires] = expiresDate
        }

        if isSecure {
            properties[.secure] = "TRUE"
        }

        return HTTPCookie(properties: properties)
    }

    var isExpired: Bool {
        guard let expiresDate else {
            return false
        }

        return expiresDate < Date()
    }
}

private enum RezkaCookieStore {
    private static let service = "com.dsoft.rezka-player.authorization"
    private static let account = "rezka.fi.cookies"

    static func save(_ data: Data) {
        let query = keychainQuery()
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> Data? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return data
    }

    static func clear() {
        SecItemDelete(keychainQuery() as CFDictionary)
    }

    private static func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private enum LegacyRezkaCredentialsStore {
    private static let service = "com.dsoft.rezka-player.authorization"
    private static let account = "rezka.fi.credentials"

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct RezkaAuthorizationResponse: Decodable {
    let success: Bool
    let message: String?
}

final class RezkaAuthorizationService {
    static let shared = RezkaAuthorizationService()

    private enum K {
        static let storageKey = "rezka.authorization.cookies"
        static let authCookieNames = Set(["dle_user_id", "dle_password", "dle_hash"])
    }

    private let session = RezkaURLSession.shared
    private let cookieStorage = HTTPCookieStorage.shared
    private let defaults = UserDefaults.standard

    private init() {}

    var hasActiveSession: Bool {
        rezkaCookies().contains(where: { K.authCookieNames.contains($0.name) })
    }

    func restorePersistedCookies() {
        LegacyRezkaCredentialsStore.clear()

        guard let data = RezkaCookieStore.load() ?? defaults.data(forKey: K.storageKey),
              let cookies = try? JSONDecoder().decode([PersistedCookie].self, from: data) else {
            defaults.removeObject(forKey: K.storageKey)
            return
        }

        for cookie in cookies where cookie.isExpired == false {
            guard let restoredCookie = cookie.cookie else { continue }
            cookieStorage.setCookie(restoredCookie)
        }

        syncHostWithAuthCookiesIfNeeded()
        persistCookies()
    }

    func persistCookies() {
        guard hasActiveSession else {
            defaults.removeObject(forKey: K.storageKey)
            RezkaCookieStore.clear()
            return
        }

        let cookies = rezkaCookies(includeSessionCookie: true)
            .map(PersistedCookie.init(cookie:))
            .filter { $0.isExpired == false }

        guard cookies.isEmpty == false else {
            defaults.removeObject(forKey: K.storageKey)
            RezkaCookieStore.clear()
            return
        }

        guard let data = try? JSONEncoder().encode(cookies) else {
            return
        }

        RezkaCookieStore.save(data)
        defaults.removeObject(forKey: K.storageKey)
    }

    func clearSession() {
        for cookie in rezkaCookies(includeSessionCookie: true) {
            cookieStorage.deleteCookie(cookie)
        }

        defaults.removeObject(forKey: K.storageKey)
        RezkaCookieStore.clear()
        LegacyRezkaCredentialsStore.clear()
    }

    func login(email: String, password: String) async throws {
        clearSession()

        guard let url = URL(string: "\(ConstantsApi.server)/ajax/login/") else {
            throw DataError.generate(for: .rezkaConstantsApi, error: .bad)
        }

        var request = URLRequest(url: url)
        request.httpMethod = ApiConstants.HttpMethod.post.rawValue
        request.setValue(ApiConstants.userAgent, forHTTPHeaderField: ApiConstants.userAgentKey)
        request.setValue(ApiConstants.formContentType, forHTTPHeaderField: ApiConstants.contentTypeKey)
        request.setValue(ApiConstants.AcceptTypeJson, forHTTPHeaderField: ApiConstants.AcceptTypeKey)

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "login_name", value: email),
            URLQueryItem(name: "login_password", value: password),
            URLQueryItem(name: "login_not_save", value: "0")
        ]
        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let response = response as? HTTPURLResponse else {
            throw DataError.generate(for: .rezkaConstantsApi, error: .bad)
        }

        let headers = response.allHeaderFields.reduce(into: [String: String]()) { partialResult, item in
            guard let key = item.key as? String,
                  let value = item.value as? String else {
                return
            }

            partialResult[key] = value
        }

        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
            cookieStorage.setCookie(cookie)
        }

        guard response.statusCode == 200 else {
            throw DataError.generate(for: .rezkaConstantsApi, error: .server)
        }

        let loginResponse = try JSONDecoder().decode(RezkaAuthorizationResponse.self, from: data)

        guard loginResponse.success else {
            clearSession()

            let message = loginResponse.message ?? "Login failed"
            throw NSError(
                domain: ApiConstants.Domains.rezkaConstantsApi.rawValue,
                code: ApiConstants.ResponseError.default.code,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        guard hasActiveSession else {
            clearSession()
            throw DataError.generate(for: .rezkaConstantsApi, error: .authorization)
        }

        syncHostWithAuthCookiesIfNeeded()
        persistCookies()
    }

    private func rezkaCookies(includeSessionCookie: Bool = false) -> [HTTPCookie] {
        let cookies = cookieStorage.cookies ?? []

        return cookies.filter { cookie in
            let isCurrentHostCookie = cookieAppliesToCurrentHost(cookie)
            let isAuthCookie = K.authCookieNames.contains(cookie.name)

            if includeSessionCookie {
                return isCurrentHostCookie || isAuthCookie
            }

            return isCurrentHostCookie && isAuthCookie
        }
    }

    private func syncHostWithAuthCookiesIfNeeded() {
        guard ConstantsApi.hasCustomHost == false else {
            return
        }

        let authCookies = (cookieStorage.cookies ?? [])
            .filter { K.authCookieNames.contains($0.name) }

        guard authCookies.isEmpty == false else {
            return
        }

        if authCookies.contains(where: cookieAppliesToCurrentHost) {
            return
        }

        let inferredHosts = authCookies.compactMap { cookie in
            normalizedCookieHost(from: cookie.domain)
        }

        guard let inferredHost = inferredHosts.first,
              inferredHosts.allSatisfy({ $0 == inferredHost }) else {
            return
        }

        ConstantsApi.setHost(inferredHost)
    }

    private func cookieAppliesToCurrentHost(_ cookie: HTTPCookie) -> Bool {
        cookieDomain(cookie.domain, appliesTo: ConstantsApi.host)
    }

    private func normalizedCookieHost(from rawDomain: String) -> String? {
        let trimmedDomain = rawDomain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return ConstantsApi.normalizedHost(from: trimmedDomain)
    }

    private func cookieDomain(_ rawDomain: String, appliesTo host: String) -> Bool {
        guard let normalizedDomain = normalizedCookieHost(from: rawDomain) else {
            return false
        }

        return host == normalizedDomain || host.hasSuffix(".\(normalizedDomain)")
    }
}
