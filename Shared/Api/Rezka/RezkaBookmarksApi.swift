import Foundation

struct RezkaBookmarksApi {
    private let session = RezkaURLSession.shared

    func fetchBookmarks(folderID: String? = nil) async throws -> BookmarkLibrary {
        let baseLibrary = try await fetchBookmarksPage(url: URL(string: "\(ConstantsApi.server)/favorites/")!, folderID: nil)

        guard let folderID,
              let folder = baseLibrary.folders.first(where: { $0.id == folderID }),
              let url = folder.url else {
            return baseLibrary
        }

        return try await fetchBookmarksPage(url: url, folderID: folderID)
    }

    func fetchBookmarks(in folder: BookmarkFolder) async throws -> [Media] {
        guard let url = folder.url else {
            return []
        }

        return try await fetchBookmarksPage(url: url, folderID: folder.id).medias
    }

    func createFolder(named name: String) async throws {
        try await performMutation(
            body: [
                URLQueryItem(name: "name", value: name),
                URLQueryItem(name: "action", value: "add_cat")
            ]
        )
    }

    func addBookmark(mediaID: Int, folderID: String) async throws {
        try await performMutation(
            body: bookmarkMutationBody(mediaID: mediaID, folderID: folderID)
        )
    }

    func removeBookmark(mediaID: Int, folderID: String?) async throws {
        guard let folderID else {
            throw DataError.generate(for: .rezkaConstantsApi, error: .bad)
        }

        // Rezka toggles membership in a folder with the same add_post action.
        try await performMutation(
            body: bookmarkMutationBody(mediaID: mediaID, folderID: folderID)
        )
    }

    private func fetchBookmarksPage(url: URL, folderID: String?) async throws -> BookmarkLibrary {
        let request = request(for: url, method: .get)
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
            return try BookmarksRezkaAPIResponse(from: html, currentFolderID: folderID).library
        default:
            throw DataError.generate(for: .rezkaConstantsApi, error: .server)
        }
    }

    private func performMutation(body: [URLQueryItem]) async throws {
        let success = try await performMutation(url: mutationURL, body: body)

        guard success else {
            throw DataError.generate(for: .rezkaConstantsApi, error: .server)
        }
    }

    private func performMutation(url: URL, body: [URLQueryItem]) async throws -> Bool {
        var request = request(for: url, method: .post)
        var components = URLComponents()
        components.queryItems = body
        request.httpBody = components.query?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let response = response as? HTTPURLResponse else {
            throw DataError.generate(for: .rezkaConstantsApi, error: .bad)
        }

        let text = String(decoding: data, as: UTF8.self)

        guard (200...299).contains(response.statusCode) else {
            return false
        }

        guard text.isRezkaLoginPage == false else {
            throw DataError.generate(for: .rezkaConstantsApi, error: .authorization)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let success = json["success"] as? Bool {
                return success
            }
            if let status = json["status"] as? String {
                return ["ok", "success", "done"].contains(status.lowercased())
            }
            if let error = json["error"] as? Bool {
                return error == false
            }
        }

        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["ok", "success", "done", "1", "true"].contains(normalized)
    }

    private func request(for url: URL, method: ApiConstants.HttpMethod) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(ApiConstants.userAgent, forHTTPHeaderField: ApiConstants.userAgentKey)
        request.setValue(ConstantsApi.server, forHTTPHeaderField: "Origin")
        request.setValue("\(ConstantsApi.server)/favorites/", forHTTPHeaderField: "Referer")

        switch method {
        case .get:
            request.setValue(ApiConstants.AcceptTypeHtml, forHTTPHeaderField: ApiConstants.AcceptTypeKey)
            request.setValue(ApiConstants.defaultContentType, forHTTPHeaderField: ApiConstants.contentTypeKey)
        case .post:
            request.setValue(ApiConstants.AcceptTypeJson, forHTTPHeaderField: ApiConstants.AcceptTypeKey)
            request.setValue(ApiConstants.formContentType, forHTTPHeaderField: ApiConstants.contentTypeKey)
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        }

        return request
    }

    private func bookmarkMutationBody(mediaID: Int, folderID: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "post_id", value: "\(mediaID)"),
            URLQueryItem(name: "cat_id", value: folderID),
            URLQueryItem(name: "action", value: "add_post")
        ]
    }

    private var mutationURL: URL {
        URL(string: "\(ConstantsApi.server)/ajax/favorites/")!
    }
}
