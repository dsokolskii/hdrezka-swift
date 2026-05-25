import Foundation

final class DetailedHistoryMedia: ObservableObject, Codable {
    
    private(set) var mediaId: Int
    
    @Published var translation: Int
    
    @Published var season: Int?
    
    @Published var episode: Int?
    
    @Published var quality: Media.Quality = Media.Quality.unknown

    @Published var playbackPosition: Double

    @Published var playbackDuration: Double

    @Published var title: String

    @Published var coverURL: String

    @Published var mediaURL: String

    @Published var isSeries: Bool

    @Published var seasonTitle: String

    @Published var episodeTitle: String

    @Published var updatedAt: Date
    
    init(
        mediaId: Int,
        translation: Int = 0,
        season: Int? = nil,
        episode: Int? = nil,
        quality: Media.Quality = Media.Quality.unknown,
        playbackPosition: Double = 0,
        playbackDuration: Double = 0,
        title: String = "",
        coverURL: String = "",
        mediaURL: String = "",
        isSeries: Bool = false,
        seasonTitle: String = "",
        episodeTitle: String = "",
        updatedAt: Date = .distantPast
    ) {
        self.mediaId = mediaId
        self.translation = translation
        self.season = season
        self.episode = episode
        self.quality = quality
        self.playbackPosition = playbackPosition
        self.playbackDuration = playbackDuration
        self.title = title
        self.coverURL = coverURL
        self.mediaURL = mediaURL
        self.isSeries = isSeries
        self.seasonTitle = seasonTitle
        self.episodeTitle = episodeTitle
        self.updatedAt = updatedAt
    }
    
    enum CodingKeys: String, CodingKey {
        case mediaId, translation, season, episode, quality, playbackPosition, playbackDuration, title, coverURL, mediaURL, isSeries, seasonTitle, episodeTitle, updatedAt
    }
    
    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        mediaId = try values.decode(Int.self, forKey: .mediaId)
        translation = try values.decode(Int.self, forKey: .translation)
        season = try? values.decodeIfPresent(Int.self, forKey: .season)
        episode = try? values.decodeIfPresent(Int.self, forKey: .episode)
        quality = try values.decode(Media.Quality.self, forKey: .quality)
        playbackPosition = (try? values.decodeIfPresent(Double.self, forKey: .playbackPosition)) ?? 0
        playbackDuration = (try? values.decodeIfPresent(Double.self, forKey: .playbackDuration)) ?? 0
        title = (try? values.decodeIfPresent(String.self, forKey: .title)) ?? ""
        coverURL = (try? values.decodeIfPresent(String.self, forKey: .coverURL)) ?? ""
        mediaURL = (try? values.decodeIfPresent(String.self, forKey: .mediaURL)) ?? ""
        isSeries = (try? values.decodeIfPresent(Bool.self, forKey: .isSeries)) ?? false
        seasonTitle = (try? values.decodeIfPresent(String.self, forKey: .seasonTitle)) ?? ""
        episodeTitle = (try? values.decodeIfPresent(String.self, forKey: .episodeTitle)) ?? ""
        updatedAt = (try? values.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? .distantPast
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mediaId, forKey: .mediaId)
        try container.encode(translation, forKey: .translation)
        try container.encode(season, forKey: .season)
        try container.encode(episode, forKey: .episode)
        try container.encode(quality, forKey: .quality)
        try container.encode(playbackPosition, forKey: .playbackPosition)
        try container.encode(playbackDuration, forKey: .playbackDuration)
        try container.encode(title, forKey: .title)
        try container.encode(coverURL, forKey: .coverURL)
        try container.encode(mediaURL, forKey: .mediaURL)
        try container.encode(isSeries, forKey: .isSeries)
        try container.encode(seasonTitle, forKey: .seasonTitle)
        try container.encode(episodeTitle, forKey: .episodeTitle)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

extension DetailedHistoryMedia: Equatable {
    static func == (lhs: DetailedHistoryMedia, rhs: DetailedHistoryMedia) -> Bool {
        return lhs.mediaId == rhs.mediaId &&
            lhs.translation == rhs.translation &&
            lhs.season == rhs.season &&
            lhs.episode == rhs.episode &&
            lhs.quality == rhs.quality &&
            lhs.playbackPosition == rhs.playbackPosition &&
            lhs.playbackDuration == rhs.playbackDuration &&
            lhs.title == rhs.title &&
            lhs.coverURL == rhs.coverURL &&
            lhs.mediaURL == rhs.mediaURL &&
            lhs.isSeries == rhs.isSeries &&
            lhs.seasonTitle == rhs.seasonTitle &&
            lhs.episodeTitle == rhs.episodeTitle &&
            lhs.updatedAt == rhs.updatedAt
    }
}
