import Foundation
import SwiftSoup
import OrderedCollections

struct DetailedMediaRezkaAPIResponse: Decodable {
    var detailedMedia: DetailedMedia
    
    init(from html: String) throws {
        let doc = try SwiftSoup.parse(html)
        let item = try doc.body()?.getElementById("main")?.getElementsByClass("b-content__main").first
        
        let mediaIdElement = try item?.getElementsByClass("b-userset__fav_holder").first
        let mediaId = try mediaIdElement?.attr("data-post_id") ?? "0"
        
        let title = try item?.getElementsByClass("b-post__title").first?.text() ?? ""
        let originalTitle = try item?.getElementsByClass("b-post__origtitle").first?.text() ?? ""
        
        var info: OrderedDictionary<String, String> = [:]
        let infoItems = try item?.getElementsByClass("b-post__info").first?.getElementsByTag("tr")
        try infoItems?.forEach({ infoLine in
            let items = try infoLine.getElementsByTag("td")
            if items.count == 2 {
                info[try items.first?.text() ?? ""] = try items.last?.text() ?? ""
            }
            else if let list = try infoLine.getElementsByClass("persons-list-holder").first {
                let spans = try list.getElementsByTag("span")
                let title = try spans.first?.text() ?? ""
                let index = title.index(title.startIndex, offsetBy: title.count)
                let persons = (try items.first?.text() ?? "")[index...]
                info[title] = String(persons)
            }
        })
                
        let defaultTranslation = info["В переводе:"] ?? ""
        
        let desc = try item?.getElementsByClass("b-post__description_text").last?.text() ?? ""
        
        let coverElement = try item?.getElementsByClass("b-sidecover").first
        
        let img = ConstantsApi.secureURLString(
            from: try coverElement?.getElementsByTag("img").first?.attr("src") ?? ""
        )
        
        let translation = try DetailedMediaRezkaAPIResponse.translations(in: doc, default: defaultTranslation)
        var relatedTitles = try DetailedMediaRezkaAPIResponse.relatedTitles(in: doc, currentTitle: title)
        if relatedTitles.isEmpty == false,
           relatedTitles.contains(where: \.isCurrent) == false {
            relatedTitles.insert(
                RelatedMediaTitle(
                    title: title,
                    url: "",
                    year: info["Год:"],
                    rating: nil,
                    isCurrent: true
                ),
                at: 0
            )
        }
        let episodeSchedule = try DetailedMediaRezkaAPIResponse.episodeSchedule(in: doc)
        
        detailedMedia = DetailedMedia(
            mediaId: Int(mediaId)!,
            title: title,
            titleOriginal: originalTitle,
            info: info,
            description: desc,
            translations: translation,
            seasons: [:],
            coverUrl: img,
            relatedTitles: relatedTitles,
            episodeSchedule: episodeSchedule
        )
    }
    
    private static func translations(in doc: Document, default translation: String) throws -> OrderedDictionary<Int, String> {
        var translations: OrderedDictionary<Int, String> = [:]
        
        let scripts = try doc.getElementsByTag("script")
        
        scripts.forEach { element in
            let script = element.data()
            
            for search in ["initCDNSeriesEvents", "initCDNMoviesEvents"] {
                if let pos = script.firstRange(of: search) {
                    let startIndex = script.index(pos.upperBound, offsetBy: 1)
                    let components = String(script[startIndex...]).split(separator: ", ")
                    if components.count > 1, let id = Int(components[1]) {
                        translations[id] = translation
                        break
                    }
                }
            }
        }
        
        let list = try doc.getElementsByClass("b-translators__list").first
        let itemsLi = try list?.getElementsByTag("li")
        let itemsA = try list?.getElementsByTag("a")
        let items = itemsLi?.isEmpty() == true ? itemsA : itemsLi
        try items?.forEach({ translationElement in
            let title = try translationElement.attr("title")
            let id = Int(try translationElement.attr("data-translator_id")) ?? 0
            
            translations[id] = title
        })
        
        return translations
    }

    private static func relatedTitles(in doc: Document, currentTitle: String) throws -> [RelatedMediaTitle] {
        var relatedByID: [String: RelatedMediaTitle] = [:]
        let containers = try relatedTitleContainers(in: doc)

        for container in containers {
            for link in try container.select("a[href]").array() {
                let href = try link.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
                guard href.isEmpty == false, href.hasPrefix("#") == false else {
                    continue
                }

                let title = cleanTitle(try link.text())
                guard title.isEmpty == false else {
                    continue
                }

                let context = try link.parent()?.text() ?? title
                let url = ConstantsApi.secureURLString(from: href)
                let item = RelatedMediaTitle(
                    title: title,
                    url: url,
                    year: firstMatch(in: context, pattern: #"\b(?:19|20)\d{2}\b"#),
                    rating: firstMatch(in: context, pattern: #"\b\d{1,2}\.\d{1,2}\b"#),
                    isCurrent: normalized(title) == normalized(currentTitle)
                )
                relatedByID[item.id] = item
            }
        }

        return Array(relatedByID.values).sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent {
                return lhs.isCurrent
            }
            return (lhs.year ?? "") > (rhs.year ?? "")
        }
    }

    private static func relatedTitleContainers(in doc: Document) throws -> [Element] {
        var containers: [Element] = []
        let selectors = [
            ".b-post__partcontent",
            ".b-post__parts",
            ".b-post__other_parts",
            ".b-post__related_parts",
            ".b-post__serials",
            "[class*=\"partcontent\"]",
            "[class*=\"related_parts\"]"
        ]

        for selector in selectors {
            containers.append(contentsOf: try doc.select(selector).array())
        }

        let headings = try doc.select("h1,h2,h3,h4,.b-post__subtitle,.b-post__parttitle").array()
        for heading in headings {
            let text = normalized(try heading.text())
            guard text.contains("все части") || text.contains("все сезоны") else {
                continue
            }

            if let parent = heading.parent() {
                containers.append(parent)
            }
            if let next = try heading.nextElementSibling() {
                containers.append(next)
            }
        }

        return uniqueElements(containers)
    }

    private static func episodeSchedule(in doc: Document) throws -> [EpisodeReleaseScheduleItem] {
        var itemsByID: [String: EpisodeReleaseScheduleItem] = [:]
        let containers = try episodeScheduleContainers(in: doc)

        for container in containers {
            let rows = try container.select("tr,li,div").array()
            for row in rows {
                let text = normalizedSpaces(try row.text())
                guard text.isEmpty == false,
                      matchCount(in: text, pattern: #"\d+\s+сезон\s+\d+\s+серия"#) == 1,
                      let episode = firstMatch(in: text, pattern: #"\d+\s+сезон\s+\d+\s+серия"#) else {
                    continue
                }

                let dateText = firstMatch(
                    in: text,
                    pattern: #"\d{1,2}\s+[А-Яа-яЁё]+\s+\d{4}|\d{1,2}\.\d{1,2}\.\d{4}"#
                ) ?? ""
                var title = text
                    .replacingOccurrences(of: episode, with: "")
                    .replacingOccurrences(of: dateText, with: "")
                    .replacingOccurrences(of: "✓", with: "")
                    .replacingOccurrences(of: "√", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if title.count > 120 {
                    title = ""
                }

                let item = EpisodeReleaseScheduleItem(
                    episode: episode,
                    title: title,
                    originalTitle: nil,
                    dateText: dateText,
                    isReleased: text.contains("✓") || text.contains("√") || normalized(text).contains("выш")
                )
                itemsByID[item.id] = item
            }
        }

        return Array(itemsByID.values)
    }

    private static func episodeScheduleContainers(in doc: Document) throws -> [Element] {
        var containers: [Element] = []
        let selectors = [
            ".b-post__schedule",
            ".b-post__schedule_block",
            ".b-post__schedule_list",
            "[class*=\"schedule\"]"
        ]

        for selector in selectors {
            containers.append(contentsOf: try doc.select(selector).array())
        }

        let headings = try doc.select("h1,h2,h3,h4,.b-post__subtitle").array()
        for heading in headings {
            let text = normalized(try heading.text())
            guard text.contains("график") || text.contains("даты выхода") else {
                continue
            }

            if let parent = heading.parent() {
                containers.append(parent)
            }
            if let next = try heading.nextElementSibling() {
                containers.append(next)
            }
        }

        return uniqueElements(containers)
    }

    private static func uniqueElements(_ elements: [Element]) -> [Element] {
        var seen = Set<String>()
        var unique: [Element] = []

        for element in elements {
            let key = element.description
            guard seen.insert(key).inserted else {
                continue
            }
            unique.append(element)
        }

        return unique
    }

    private static func cleanTitle(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+\((?:19|20)\d{2}\)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ text: String) -> String {
        normalizedSpaces(text).lowercased()
    }

    private static func normalizedSpaces(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }

        return String(text[matchRange])
    }

    private static func matchCount(in text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return 0
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, range: range)
    }
}
