import Foundation

struct MediaSettings: Codable, Equatable {
    
    var quality: Media.Quality = .unknown
    var translationId: Int = -1
}
