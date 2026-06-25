import Foundation
import OrderedCollections

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

    init(
        mediaId: Int,
        title: String,
        titleOriginal: String,
        info: OrderedDictionary<String, String>,
        description: String,
        translations: OrderedDictionary<Int, String>,
        seasons: [Int: SeasonsData] = [:],
        coverUrl: String
    ) {
        self.mediaId = mediaId
        self.title = title
        self.titleOriginal = titleOriginal
        self.info = info
        self.description = description
        self.translations = translations
        self.seasons = seasons
        self.coverUrl = ConstantsApi.secureURLString(from: coverUrl)
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
