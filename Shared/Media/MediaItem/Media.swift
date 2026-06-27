import Foundation

let activityTypeViewKey = "com.rezka-player.media.view"
let activityURLKey = "media.url.key"

struct Media {
    private enum CodingKeys: String, CodingKey {
        case title
        case url
        case descriptionShort
        case description
        case coverUrl
        case seriesInfo
        case category
        case quality
    }

    enum Quality: String, Codable {
        case p4k = "4K"
        case p2k = "2K"
        case p1080u = "1080p Ultra"
        case p1080 = "1080p"
        case p720 = "720p"
        case p480 = "480p"
        case p360 = "360p"
        case unknown
    }
    
    var id: String {
        if category == .loadMore {
            return "media-load-more"
        }

        let normalizedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedURL.isEmpty == false {
            return normalizedURL
        }

        return [
            category.rawValue,
            title,
            coverUrl
        ].joined(separator: "|")
    }
    
    let title: String
    let url: String
    var uri: String {
        let components = url.components(separatedBy: "/")
        return components.suffix(from: 3).joined(separator: "/")
    }
    let descriptionShort: String
    let description: String?
    let coverUrl: String
    let seriesInfo: String?
    let category: Category
    let quality: Quality

    init(
        title: String,
        url: String,
        descriptionShort: String,
        description: String?,
        coverUrl: String,
        seriesInfo: String?,
        category: Category,
        quality: Quality
    ) {
        self.title = title
        self.url = ConstantsApi.secureURLString(from: url)
        self.descriptionShort = descriptionShort
        self.description = description
        self.coverUrl = ConstantsApi.secureURLString(from: coverUrl)
        self.seriesInfo = seriesInfo
        self.category = category
        self.quality = quality
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        title = try container.decode(String.self, forKey: .title)
        url = ConstantsApi.secureURLString(from: try container.decode(String.self, forKey: .url))
        descriptionShort = try container.decode(String.self, forKey: .descriptionShort)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        coverUrl = ConstantsApi.secureURLString(from: try container.decode(String.self, forKey: .coverUrl))
        seriesInfo = try container.decodeIfPresent(String.self, forKey: .seriesInfo)
        category = try container.decode(Category.self, forKey: .category)
        quality = try container.decode(Quality.self, forKey: .quality)
    }
    
    var descriptionText: String {
        descriptionShort
    }
    
    var mediaURL: URL {
        if let url = ConstantsApi.secureURL(from: url) {
            return url
        }

        return URL(string: "\(ConstantsApi.server)/\(uri)")!
    }
    
    var coverURL: URL? {
        ConstantsApi.secureURL(from: coverUrl)
    }
    
    var isSeries: Bool {
        seriesInfo != nil
    }
}

extension Media: Codable {}
extension Media: Equatable {}
extension Media: Identifiable {}
extension Media: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Media {
    
    static var previewData: [Media] {
        [
            .init(title: "one", url: "https://example.com", descriptionShort: "description short", description: "description", coverUrl: "", seriesInfo: "", category: .films, quality: .unknown)
        ]
    }
    
    static var previewCategoryArticles: [CategoryMedias] {
        let articles = previewData
        return Category.allCases.map {
            .init(category: $0, medias: articles.shuffled())
        }
    }
}

extension Media {
    static var empty: Media {
        .init(title: "", url: "", descriptionShort: "", description: "", coverUrl: "", seriesInfo: "", category: .loadMore, quality: .unknown)
    }
}


extension Media.Quality: Comparable, Equatable{
    
    static func index(of aStatus: Media.Quality) -> Int {
        switch aStatus {
        case .p360: 1
        case .p480: 2
        case .p720: 3
        case .p1080: 4
        case .p1080u: 5
        case .p2k: 6
        case .p4k: 7
        default: 0
        }
    }
    
    static func > (lhs: Media.Quality, rhs: Media.Quality) -> Bool {
        Media.Quality.index(of: lhs) >  Media.Quality.index(of: rhs)
    }
    
    static func < (lhs: Media.Quality, rhs: Media.Quality) -> Bool {
        Media.Quality.index(of: lhs) <  Media.Quality.index(of: rhs)
    }
    
    static func == (lhs: Media.Quality, rhs: Media.Quality) -> Bool {
        Media.Quality.index(of: lhs) ==  Media.Quality.index(of: rhs)
    }
}
