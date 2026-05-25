import Foundation
import SwiftSoup
import OrderedCollections

// MARK: - Seasons
struct SeasonsData: Codable {
    let seasons: OrderedDictionary<Int, String>
    let episodes: [Int: [Episode]]
    let url: String
    let quality: String
    let subtitle: String?
    let subtitlesList: [String: String]?
    let subtitleDefault: String?
    let thumbnails: String
    
    enum CodingKeys: String, CodingKey {
        case seasons, episodes, url, quality, subtitle
        case subtitlesList = "subtitle_lns"
        case subtitleDefault = "subtitle_def"
        case thumbnails
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        let seasonsHtml = try values.decode(String.self, forKey: .seasons)
        seasons = SeasonsData.parseSeasons(html: seasonsHtml)
        let episodesHtml = try values.decode(String.self, forKey: .episodes)
        episodes = SeasonsData.parseEpisodes(html: episodesHtml, seasons: seasons.keys.sorted())
        url = try values.decode(String.self, forKey: .url)
        quality = try values.decode(String.self, forKey: .quality)
        subtitle = try? values.decode(String.self, forKey: .subtitle)
        subtitlesList = try? values.decode([String: String].self, forKey: .subtitlesList)
        subtitleDefault = try? values.decode(String.self, forKey: .subtitleDefault)
        thumbnails = try values.decode(String.self, forKey: .thumbnails)
    }
    
    private static func parseSeasons(html: String) -> OrderedDictionary<Int, String> {
        var value: OrderedDictionary<Int, String> = [:]
        do {
            let doc = try SwiftSoup.parse(html)
            let seasons = try doc.body()?.getElementsByClass("b-simple_season__item")
            try seasons?.forEach({ season in
                let id = try season.attr("data-tab_id")
                value[Int(id)!] = try season.text()
            })
        } catch {
            print(error.localizedDescription)
        }
        
        return value
    }
    
    private static func parseEpisodes(html: String, seasons: [Int]) -> [Int: [Episode]] {
        var value = [Int: [Episode]]()

        seasons.forEach { season in
            value[season] = []
        }

        do {
            let doc = try SwiftSoup.parse(html)
            let seasonEpisodeLists = try doc.select("[id^=simple-episodes-list-]")

            for seasonList in seasonEpisodeLists {
                let listID = try seasonList.id()
                let seasonIDString = listID.replacingOccurrences(of: "simple-episodes-list-", with: "")
                guard let seasonID = Int(seasonIDString) else {
                    continue
                }

                var episodes = [Episode]()
                let lis = try seasonList.getElementsByTag("li")
                for (index, episode) in lis.enumerated() {
                    let urlsBase64 = (try? episode.attr("data-cdn_url")) ?? ""
                    let numericEpisode = Int((try? episode.attr("data-episode_num")) ?? "")
                        ?? Int((try? episode.attr("data-episode_id")) ?? "")
                        ?? (index + 1)
                    let title = ((try? episode.text()) ?? "Эпизод \(numericEpisode)")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let streams = urlsBase64.isEmpty ? nil : (try? StreamRezkaApiResponse(from: urlsBase64).streams)
                    episodes.append(Episode(id: numericEpisode, title: title, streams: streams))
                }

                value[seasonID] = episodes
            }
        } catch {
            print(error.localizedDescription)
        }
        
        return value
    }
}

struct Episode: Codable {
    let id: Int
    let title: String
    let streams: StreamMedia?
}

extension Episode: Equatable {
    static func == (lhs: Episode, rhs: Episode) -> Bool {
        return lhs.id == rhs.id
    }
}
extension Episode: Identifiable {}
