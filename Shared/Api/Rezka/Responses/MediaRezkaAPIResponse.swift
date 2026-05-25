import Foundation
import SwiftSoup

struct MediaRezkaAPIResponse: Decodable {
    let medias: [Media]
    
    init(from html: String) throws {
        let doc = try SwiftSoup.parse(html)
        let items = try doc.body()?.getElementById("main")?.getElementsByClass("b-content__inline_items").first?.getElementsByClass("b-content__inline_item")
        
        var medias: [Media] = []
        
        try items?.forEach({ item in
            let coverElement = try item.getElementsByClass("b-content__inline_item-cover").first
            let linkElement = try item.getElementsByClass("b-content__inline_item-link").first
            
            let aTag = try linkElement?.getElementsByTag("a").first
            
            let url = try aTag?.attr("href") ?? ""
            let title = (try aTag?.text() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            
            let desc = (try linkElement?.getElementsByTag("div").last?.text() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            
            var category: Category = .general
            var seriesInfo: String?
            if let _ = try coverElement?.getElementsByClass("series").last {
                seriesInfo = (try coverElement?.getElementsByClass("info").last?.text() ?? nil)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                category = .series
            } else if let _ = try coverElement?.getElementsByClass("films").last {
                category = .films
            } else if let _ = try coverElement?.getElementsByClass("cartoons").last {
                seriesInfo = (try coverElement?.getElementsByClass("info").last?.text() ?? nil)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                category = .cartoons
            } else if let _ = try coverElement?.getElementsByClass("animation").last {
                seriesInfo = (try coverElement?.getElementsByClass("info").last?.text() ?? nil)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                category = .animation
            }
            
            let imgTag = try coverElement?.getElementsByTag("img").first
            let img = try Self.resolveImageURL(from: imgTag)
            
            let media = Media(title: title, url: url, descriptionShort: desc, description: nil, coverUrl: img, seriesInfo: seriesInfo, category: category, quality: .p1080)
            
            medias.append(media)
        })
        
        self.medias = medias
    }

    private static func resolveImageURL(from imgTag: Element?) throws -> String {
        guard let imgTag else { return "" }

        let srcsetAttributes = [
            try imgTag.attr("srcset"),
            try imgTag.attr("data-srcset"),
            try imgTag.attr("data-lazy-srcset")
        ]

        for srcset in srcsetAttributes where srcset.isEmpty == false {
            let urls = srcset
                .split(separator: ",")
                .compactMap { candidate -> String? in
                    let raw = candidate
                        .split(separator: " ")
                        .first
                        .map(String.init)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let raw, raw.isEmpty == false else {
                        return nil
                    }
                    return raw
                }

            if let last = urls.last {
                return normalize(urlString: last)
            }
        }

        let candidates = [
            try imgTag.attr("data-src"),
            try imgTag.attr("data-original"),
            try imgTag.attr("src")
        ]

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return normalize(urlString: trimmed)
            }
        }

        return ""
    }

    private static func normalize(urlString: String) -> String {
        if urlString.hasPrefix("//") {
            return "https:\(urlString)"
        }
        if urlString.hasPrefix("/") {
            return "\(ConstantsApi.server)\(urlString)"
        }

        return urlString
    }
}
