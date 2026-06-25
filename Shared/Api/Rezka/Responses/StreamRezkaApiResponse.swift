import Foundation
import SwiftSoup

private struct StreamData: Codable {
    let success: Bool
    let message: String
    let url: String?
    let quality: String
    let subtitle: String?
    let subtitlesList: [String: String]?
    let subtitleDefault: String?
    let thumbnails: String
    
    enum CodingKeys: String, CodingKey {
        case success, message, url, quality, subtitle
        case subtitlesList = "subtitle_lns"
        case subtitleDefault = "subtitle_def"
        case thumbnails
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        success = try values.decode(Bool.self, forKey: .success)
        message = try values.decode(String.self, forKey: .message)
        url = try values.decode(String.self, forKey: .url)
        quality = try values.decode(String.self, forKey: .quality)
        subtitle = try? values.decode(String.self, forKey: .subtitle)
        subtitlesList = try? values.decode([String: String].self, forKey: .subtitlesList)
        subtitleDefault = try? values.decode(String.self, forKey: .subtitleDefault)
        thumbnails = try values.decode(String.self, forKey: .thumbnails)
    }
}

// MARK: - Seasons
struct StreamMedia: Codable {
    var bestQualityId: Media.Quality {
        if let p = p4k, p.isEmpty == false {
            .p4k
        } else if let p = p2k, p.isEmpty == false {
            .p2k
        } else if let p = p1080u, p.isEmpty == false {
            .p1080u
        } else if let p = p1080, p.isEmpty == false {
            .p1080
        } else if let p = p720, p.isEmpty == false {
            .p720
        } else if let p = p480, p.isEmpty == false {
            .p480
        } else if let p = p360, p.isEmpty == false {
            .p360
        } else {
            //assert(false, "wrong stream data")
            .p360
        }
    }
    
    var bestQualityUrl: [String] {
        if let p = p4k, p.isEmpty == false {
            p
        } else if let p = p2k, p.isEmpty == false {
            p
        } else if let p = p1080u, p.isEmpty == false {
            p
        } else if let p = p1080, p.isEmpty == false {
            p
        } else if let p = p720, p.isEmpty == false {
            p
        } else if let p = p480, p.isEmpty == false {
            p
        } else if let p = p360, p.isEmpty == false {
            p
        } else {
            //assert(false, "wrong stream data")
            []
        }
    }
    
    var qualities: [Media.Quality]? {
        var qualities = [Media.Quality]()
        let list: [Media.Quality] = [.p4k, .p2k, .p1080u, .p1080, .p720, .p480, .p360]
        for q in list {
            if let _ = stream(q) {
                qualities.append(q)
            }
        }
        
        return qualities.isEmpty ? nil : qualities
    }
    
    private let p4k: [String]?
    private let p2k: [String]?
    private let p1080u: [String]?
    private let p1080: [String]?
    private let p720: [String]?
    private let p480: [String]?
    private let p360: [String]?
    
    init(p4k: [String]? = nil, p2k: [String]? = nil, p1080u: [String]? = nil, p1080: [String]? = nil, p720: [String]? = nil, p480: [String]? = nil, p360: [String]? = nil) {
        self.p4k = p4k
        self.p2k = p2k
        self.p1080u = p1080u
        self.p1080 = p1080
        self.p720 = p720
        self.p480 = p480
        self.p360 = p360
    }
    
    func stream(_ quality: Media.Quality) -> String? {
        streams(quality).first
    }

    func streams(_ quality: Media.Quality) -> [String] {
        switch quality {
        case .p4k: p4k ?? []
        case .p2k: p2k ?? []
        case .p1080u: p1080u ?? []
        case .p1080: p1080 ?? []
        case .p720: p720 ?? []
        case .p480: p480 ?? []
        case .p360: p360 ?? []
        case .unknown: []
        }
    }
    
    func alternativeStream(_ quality: Media.Quality) -> String? {
        streams(quality).last
    }
}

struct StreamRezkaApiResponse: Decodable {
    let streams: StreamMedia
    
    init(from dirtyBase64: String, isJson: Bool = false) throws {
        var cleanedBase64 = dirtyBase64
        var qualityHint: String?
        
        if isJson {
            guard let data = dirtyBase64.data(using: .utf8), let object = try? JSONDecoder().decode(StreamData.self , from: data) else {
                throw DataError.generate(for: .rezkaConstantsApi, error: .mapping)
            }
            
            guard let url = object.url else {
                throw DataError.generate(for: .rezkaConstantsApi, error: .mapping)
            }
            
            cleanedBase64 = url
            qualityHint = object.quality
        }
        
        cleanedBase64 = cleanedBase64.replacing("#h", with: "")
        
        let trashList = ["@", "#", "!", "^", "$"]
        var trashItems = [String]()
        for symbol1 in trashList {
            for symbol2 in trashList {
                let trash1 = "\(symbol1)\(symbol2)".toBase64()
                trashItems.append(trash1)
            }
            for symbol2 in trashList {
                for symbol3 in trashList {
                    let trash2 = "\(symbol1)\(symbol2)\(symbol3)".toBase64()
                    trashItems.append(trash2)
                }
            }
        }
        
        cleanedBase64 = cleanedBase64.split(separator: "//_//").joined()
        
        trashItems.forEach { trash in
            cleanedBase64 = cleanedBase64.replacing(trash, with: "")
        }
                
        var p4k: [String]?
        var p2k: [String]?
        var p1080u: [String]?
        var p1080: [String]?
        var p720: [String]?
        var p480: [String]?
        var p360: [String]?
        
        let payload = StreamRezkaApiResponse.decodedPayload(from: cleanedBase64)
        let entries = StreamRezkaApiResponse.parseEntries(from: payload, qualityHint: qualityHint)
        
        for (type, urls) in entries {
            switch type {
            case .p4k: p4k = urls
            case .p2k: p2k = urls
            case .p1080u: p1080u = urls
            case .p1080: p1080 = urls
            case .p720: p720 = urls
            case .p480: p480 = urls
            case .p360: p360 = urls
            case .unknown: break
            }
        }
        
        if [p4k, p2k, p1080u, p1080, p720, p480, p360].allSatisfy({ $0?.isEmpty != false }) {
            throw DataError.generate(for: .rezkaConstantsApi, error: .mapping)
        }
        
        self.streams = StreamMedia(p4k: p4k, p2k: p2k, p1080u: p1080u, p1080: p1080, p720: p720, p480: p480, p360: p360)
    }

    private static func decodedPayload(from value: String) -> String {
        let normalized = normalizedBase64(value)
        if let decoded = normalized.fromBase64(), decoded.isEmpty == false {
            return decoded
        }

        return value
    }

    private static func normalizedBase64(_ value: String) -> String {
        let sanitized = value
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = sanitized.count % 4
        guard padding != 0 else {
            return sanitized
        }

        return sanitized + String(repeating: "=", count: 4 - padding)
    }

    private static func parseEntries(from payload: String, qualityHint: String?) -> [(Media.Quality, [String])] {
        let normalizedPayload = payload.replacingOccurrences(of: "\\/", with: "/")
        let hintedQuality = quality(from: qualityHint)

        if normalizedPayload.contains("[") == false,
           let directURL = normalizedURL(normalizedPayload),
           hintedQuality != .unknown {
            return [(hintedQuality, [directURL])]
        }

        let pattern = #"\[([^\]]+)\](.*?)(?=,\s*\[|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(normalizedPayload.startIndex..., in: normalizedPayload)
        let matches = regex.matches(in: normalizedPayload, range: range)

        return matches.compactMap { match in
            guard
                let qualityRange = Range(match.range(at: 1), in: normalizedPayload),
                let urlsRange = Range(match.range(at: 2), in: normalizedPayload)
            else {
                return nil
            }

            let qualityValue = String(normalizedPayload[qualityRange])
            let urlsValue = String(normalizedPayload[urlsRange])
            let quality = quality(from: qualityValue)
            let urls = urlsValue
                .split(separator: " or ")
                .compactMap { normalizedURL(String($0)) }

            guard quality != .unknown, urls.isEmpty == false else {
                return nil
            }

            return (quality, urls)
        }
    }

    private static func quality(from value: String?) -> Media.Quality {
        guard let value else {
            return .unknown
        }

        let normalized = value.lowercased()

        if normalized.contains("2160") || normalized.contains("4k") || normalized.contains("uhd") {
            return .p4k
        }
        if normalized.contains("1440") || normalized.contains("2k") || normalized.contains("qhd") {
            return .p2k
        }
        if normalized.contains("1080") && normalized.contains("ultra") {
            return .p1080u
        }
        if normalized.contains("1080") {
            return .p1080
        }
        if normalized.contains("720") {
            return .p720
        }
        if normalized.contains("480") {
            return .p480
        }
        if normalized.contains("360") {
            return .p360
        }

        return .unknown
    }

    private static func normalizedURL(_ value: String) -> String? {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            return nil
        }

        return ConstantsApi.secureURLString(from: trimmed)
    }
}
