import Foundation

enum ConstantsApi {
    static let scheme = "https://"
    static let defaultHost = "rezka.fi"
    static let domain = "RezkaAPI"
    static let iCloudKey = ""
    static let appGroupIdentifier = ""

    private static let hostStorageKey = "rezka.api.host"

    static var hasCustomHost: Bool {
        let storedHost = UserDefaults.standard.string(forKey: hostStorageKey) ?? ""
        return normalizedHost(from: storedHost)?.isEmpty == false
    }

    static var host: String {
        normalizedHost(from: UserDefaults.standard.string(forKey: hostStorageKey) ?? "") ?? defaultHost
    }

    static var server: String {
        scheme + host
    }

    static func setHost(_ value: String) {
        guard let normalizedHost = normalizedHost(from: value) else {
            return
        }

        if normalizedHost == defaultHost {
            UserDefaults.standard.removeObject(forKey: hostStorageKey)
        } else {
            UserDefaults.standard.set(normalizedHost, forKey: hostStorageKey)
        }
    }

    static func resetHost() {
        UserDefaults.standard.removeObject(forKey: hostStorageKey)
    }

    static func secureURLString(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("http://") {
            return "https://" + trimmed.dropFirst("http://".count)
        }

        if lowercased.hasPrefix("https://") {
            return trimmed
        }

        if trimmed.hasPrefix("//") {
            return "https:\(trimmed)"
        }

        if trimmed.hasPrefix("/") {
            return "\(server)\(trimmed)"
        }

        guard trimmed.contains("://") == false else {
            return trimmed
        }

        return "\(server)/\(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
    }

    static func secureURL(from value: String) -> URL? {
        URL(string: secureURLString(from: value))
    }

    static func normalizedHost(from value: String) -> String? {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard trimmed.isEmpty == false else {
            return nil
        }

        let hostValue: String
        if trimmed.contains("://") {
            guard let components = URLComponents(string: trimmed),
                  let host = components.host else {
                return nil
            }

            hostValue = host
        } else {
            let candidate = "https://\(trimmed)"
            guard let components = URLComponents(string: candidate),
                  let host = components.host else {
                return nil
            }

            hostValue = host
        }

        let normalized = hostValue.lowercased()
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard normalized.rangeOfCharacter(from: allowedCharacters.inverted) == nil,
              normalized.contains("."),
              normalized.split(separator: ".").allSatisfy({ $0.isEmpty == false }) else {
            return nil
        }

        return normalized
    }
}

final class RezkaURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completeAuthenticationChallenge(challenge, source: "session", completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completeAuthenticationChallenge(challenge, source: "task", completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        var resolvedRequest = request
        if let url = request.url,
           url.scheme?.lowercased() == "http",
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            if let secureURL = components.url {
                resolvedRequest.url = secureURL
            }
        }

        print("RezkaURLSession redirect \(response.statusCode) \(response.url?.absoluteString ?? "nil") -> \(resolvedRequest.url?.absoluteString ?? "nil")")
        completionHandler(resolvedRequest)
    }

    private func completeAuthenticationChallenge(_ challenge: URLAuthenticationChallenge,
                                                 source: String,
                                                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        let host = challenge.protectionSpace.host
        print("RezkaURLSession challenge[\(source)] method=\(method) host=\(host)")

        guard method == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

enum RezkaURLSession {
    private static let delegate = RezkaURLSessionDelegate()

    static let shared: URLSession = make()

    static func make(configuration: URLSessionConfiguration = .default) -> URLSession {
        URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}
