import Foundation
import OrderedCollections

struct RelatedMediaTitle: Codable, Equatable, Identifiable {
    var id: String { url.isEmpty ? title : url }

    let title: String
    let url: String
    let year: String?
    let rating: String?
    let isCurrent: Bool

    func media(fallbackCategory: Category, isSeries: Bool) -> Media {
        Media(
            title: title,
            url: url,
            descriptionShort: [year, rating.map { "Рейтинг \($0)" }]
                .compactMap { $0 }
                .joined(separator: ", "),
            description: nil,
            coverUrl: "",
            seriesInfo: isSeries ? "" : nil,
            category: fallbackCategory,
            quality: .unknown
        )
    }
}

struct EpisodeReleaseScheduleItem: Codable, Equatable, Identifiable {
    var id: String {
        [episode, title, dateText].joined(separator: "|")
    }

    let episode: String
    let title: String
    let originalTitle: String?
    let dateText: String
    let isReleased: Bool
}

struct DetailedMedia {
    private enum CodingKeys: String, CodingKey {
        case id
        case mediaId
        case title
        case titleOriginal
        case info
        case description
        case translations
        case seasons
        case coverUrl
        case relatedTitles
        case episodeSchedule
    }

    private(set) var id = UUID()
    
    let mediaId: Int
    
    let title: String
    let titleOriginal: String
    
    let info: OrderedDictionary<String, String>
    let description: String
    
    let translations: OrderedDictionary<Int, String>
    
    private(set) var seasons: [Int: SeasonsData] = [:]
    func seasons(in translation: Int) -> OrderedDictionary<Int, String>? {
        return seasons[translation]?.seasons
    }
    
    func episodesIn(in season: Int, translation: Int) -> [Episode]? {
        return seasons[translation]?.episodes[season]
    }
    
    let coverUrl: String
    let relatedTitles: [RelatedMediaTitle]
    let episodeSchedule: [EpisodeReleaseScheduleItem]

    init(
        mediaId: Int,
        title: String,
        titleOriginal: String,
        info: OrderedDictionary<String, String>,
        description: String,
        translations: OrderedDictionary<Int, String>,
        seasons: [Int: SeasonsData] = [:],
        coverUrl: String,
        relatedTitles: [RelatedMediaTitle] = [],
        episodeSchedule: [EpisodeReleaseScheduleItem] = []
    ) {
        self.mediaId = mediaId
        self.title = title
        self.titleOriginal = titleOriginal
        self.info = info
        self.description = description
        self.translations = translations
        self.seasons = seasons
        self.coverUrl = ConstantsApi.secureURLString(from: coverUrl)
        self.relatedTitles = relatedTitles
        self.episodeSchedule = episodeSchedule
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        mediaId = try container.decode(Int.self, forKey: .mediaId)
        title = try container.decode(String.self, forKey: .title)
        titleOriginal = try container.decode(String.self, forKey: .titleOriginal)
        info = try container.decode(OrderedDictionary<String, String>.self, forKey: .info)
        description = try container.decode(String.self, forKey: .description)
        translations = try container.decode(OrderedDictionary<Int, String>.self, forKey: .translations)
        seasons = try container.decodeIfPresent([Int: SeasonsData].self, forKey: .seasons) ?? [:]
        coverUrl = ConstantsApi.secureURLString(from: try container.decode(String.self, forKey: .coverUrl))
        relatedTitles = try container.decodeIfPresent([RelatedMediaTitle].self, forKey: .relatedTitles) ?? []
        episodeSchedule = try container.decodeIfPresent([EpisodeReleaseScheduleItem].self, forKey: .episodeSchedule) ?? []
    }
    
    mutating func setup(seasons: SeasonsData, for translation: Int) {
        self.seasons[translation] = seasons
    }
}

extension DetailedMedia: Codable {}
extension DetailedMedia: Equatable {
    static func == (lhs: DetailedMedia, rhs: DetailedMedia) -> Bool {
        return lhs.id == rhs.id
    }
}
extension DetailedMedia: Identifiable {}

extension DetailedMedia {
    
    static var previewData: DetailedMedia {
        return DetailedMedia(mediaId: .zero, title: "", titleOriginal: "", info: [:], description: "", translations: [:], seasons: [:], coverUrl: "")
    }
}
