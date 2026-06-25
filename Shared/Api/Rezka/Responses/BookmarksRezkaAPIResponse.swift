import Foundation
import SwiftSoup

struct BookmarksRezkaAPIResponse {
    let library: BookmarkLibrary

    init(from html: String, currentFolderID: String?) throws {
        let doc = try SwiftSoup.parse(html)
        let folders = try Self.folders(in: doc)
        let medias = try MediaRezkaAPIResponse(from: html).medias
        var updatedFolders = folders

        if let currentFolderID,
           let index = updatedFolders.firstIndex(where: { $0.id == currentFolderID }) {
            updatedFolders[index] = BookmarkFolder(
                id: updatedFolders[index].id,
                name: updatedFolders[index].name,
                count: updatedFolders[index].count,
                url: updatedFolders[index].url,
                medias: medias
            )
        }

        library = BookmarkLibrary(folders: updatedFolders, medias: medias)
    }

    private static func folders(in document: Document) throws -> [BookmarkFolder] {
        var foldersByID: [String: BookmarkFolder] = [:]

        let containerSelectors = [
            "#main .b-userset__fav_categories",
            "#main .b-userset__fav_category",
            "#main .b-userset__fav_sections",
            "#main .b-userset__fav_section",
            "#main .b-favorites__sections",
            "#main .b-favorites__section",
            "#main [class*=\"fav_categories\"]",
            "#main [class*=\"fav_sections\"]",
            "#main [class*=\"favorites__sections\"]"
        ]

        for selector in containerSelectors {
            for container in try document.select(selector).array() {
                for element in try container.select("a, [data-id], [data-section_id], [data-folder_id], [data-category_id], [data-fav_id]").array() {
                    guard let folder = try folder(from: element) else {
                        continue
                    }
                    foldersByID[folder.id] = folder
                }
            }
        }

        if foldersByID.isEmpty {
            for element in try document.select("#main a[href*=\"/favorites/\"]").array() {
                guard let folder = try folder(from: element) else {
                    continue
                }
                foldersByID[folder.id] = folder
            }
        }

        return foldersByID.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func folder(from element: Element) throws -> BookmarkFolder? {
        let rawText = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawText.isEmpty == false else {
            return nil
        }

        let href = try element.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedURL = href.isEmpty ? nil : ConstantsApi.secureURL(from: href)
        let count = count(from: rawText)
        let name = rawText
            .replacingOccurrences(of: #" \(\d+\)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard name.isEmpty == false else {
            return nil
        }

        let explicitIDAttributes = [
            "data-id",
            "data-section_id",
            "data-folder_id",
            "data-category_id",
            "data-fav_id"
        ]

        for attribute in explicitIDAttributes {
            let value = try element.attr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty == false {
                return BookmarkFolder(id: value, name: name, count: count, url: normalizedURL, medias: [])
            }
        }

        if let normalizedURL {
            let queryID = Self.queryID(from: normalizedURL)
            if let queryID {
                return BookmarkFolder(id: queryID, name: name, count: count, url: normalizedURL, medias: [])
            }

            let pathID = normalizedURL.path
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .split(separator: "/")
                .last
                .map(String.init)

            if let pathID, pathID != "favorites" {
                return BookmarkFolder(id: pathID, name: name, count: count, url: normalizedURL, medias: [])
            }
        }

        return nil
    }

    private static func queryID(from url: URL) -> String? {
        let idKeys = [
            "id",
            "folder",
            "folder_id",
            "section",
            "section_id",
            "category",
            "category_id",
            "fav",
            "fav_id"
        ]

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let value = components.queryItems?
            .first(where: { idKeys.contains($0.name) })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let value, value.isEmpty == false else {
            return nil
        }

        return value
    }

    private static func count(from text: String) -> Int {
        guard let range = text.range(of: #"\((\d+)\)"#, options: .regularExpression) else {
            return 0
        }

        let value = text[range]
            .filter(\.isNumber)

        return Int(String(value)) ?? 0
    }
}
