import Foundation

struct ContinueWatchingPayload: Codable {
    struct Item: Codable {
        let mediaId: Int
        let title: String
        let subtitle: String
        let coverURL: String
        let localCoverPath: String?
        let mediaURL: String
        let playbackPosition: Double
        let playbackDuration: Double
        let progress: Double
        let isSeries: Bool
        let seasonTitle: String
        let episodeTitle: String
        let updatedAt: Date

        init(
            mediaId: Int,
            title: String,
            subtitle: String,
            coverURL: String,
            localCoverPath: String?,
            mediaURL: String,
            playbackPosition: Double,
            playbackDuration: Double,
            progress: Double,
            isSeries: Bool,
            seasonTitle: String,
            episodeTitle: String,
            updatedAt: Date
        ) {
            self.mediaId = mediaId
            self.title = title
            self.subtitle = subtitle
            self.coverURL = coverURL
            self.localCoverPath = localCoverPath
            self.mediaURL = mediaURL
            self.playbackPosition = playbackPosition
            self.playbackDuration = playbackDuration
            self.progress = progress
            self.isSeries = isSeries
            self.seasonTitle = seasonTitle
            self.episodeTitle = episodeTitle
            self.updatedAt = updatedAt
        }

        enum CodingKeys: String, CodingKey {
            case mediaId
            case title
            case subtitle
            case coverURL
            case localCoverPath
            case mediaURL
            case playbackPosition
            case playbackDuration
            case progress
            case isSeries
            case seasonTitle
            case episodeTitle
            case updatedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            mediaId = (try? container.decode(Int.self, forKey: .mediaId)) ?? 0
            title = (try? container.decode(String.self, forKey: .title)) ?? ""
            subtitle = (try? container.decode(String.self, forKey: .subtitle)) ?? ""
            coverURL = (try? container.decode(String.self, forKey: .coverURL)) ?? ""
            localCoverPath = try? container.decodeIfPresent(String.self, forKey: .localCoverPath)
            mediaURL = (try? container.decode(String.self, forKey: .mediaURL)) ?? ""
            playbackPosition = (try? container.decode(Double.self, forKey: .playbackPosition)) ?? 0
            playbackDuration = (try? container.decode(Double.self, forKey: .playbackDuration)) ?? 0
            progress = (try? container.decode(Double.self, forKey: .progress)) ?? 0
            isSeries = (try? container.decode(Bool.self, forKey: .isSeries)) ?? false
            seasonTitle = (try? container.decode(String.self, forKey: .seasonTitle)) ?? ""
            episodeTitle = (try? container.decode(String.self, forKey: .episodeTitle)) ?? ""
            updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? .distantPast
        }
    }

    let generatedAt: Date
    let items: [Item]
}

enum ContinueWatchingStore {
	private static let fileName = "continue-watching.json"
	private static let appGroupIdentifier = "group.com.isoft.rezka-player.tvos"
	private static let sharedDefaultsKey = "continue-watching.payload"
	private static let hiddenMediaIdsKey = "continue-watching.hidden"

	/// Скрытые пользователем mediaId: тайтлы убраны из подборки «Продолжить просмотр»,
	/// но остаются в истории просмотра (CloudKit), чтобы прогресс не терялся.
	static func loadHiddenMediaIds() -> Set<Int> {
		guard let array = sharedDefaults()?.array(forKey: hiddenMediaIdsKey) else {
			return []
		}
		return Set(array.compactMap { ($0 as? NSNumber)?.intValue })
	}

	static func saveHiddenMediaIds(_ ids: Set<Int>) {
		sharedDefaults()?.set(Array(ids), forKey: hiddenMediaIdsKey)
	}

    static func load() -> ContinueWatchingPayload? {
        if let payload = loadFromSharedDefaults() {
            return payload
        }

        let primaryURL = outputURL()
        if let data = try? Data(contentsOf: primaryURL),
           let payload = try? JSONDecoder().decode(ContinueWatchingPayload.self, from: data) {
            return payload
        }

        let legacyURL = fallbackOutputURL()
        guard let legacyData = try? Data(contentsOf: legacyURL),
              let payload = try? JSONDecoder().decode(ContinueWatchingPayload.self, from: legacyData) else {
            return nil
        }

        // Migrate previously written fallback payload into the shared location when it becomes available.
        write(payload, to: primaryURL)
        return payload
    }

    static func save(_ payload: ContinueWatchingPayload) {
        saveToSharedDefaults(payload)
        write(payload, to: outputURL())
    }

    static func outputURL() -> URL {
        if let groupURL = appGroupContainerURL() {
            return groupURL.appendingPathComponent(fileName, isDirectory: false)
        }

        return fallbackOutputURL()
    }

    private static func fallbackOutputURL() -> URL {
        let fallbackDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return fallbackDirectory
            .appendingPathComponent("rezka-player", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func localCoversDirectoryURL() -> URL {
        if let groupURL = appGroupContainerURL() {
            return groupURL.appendingPathComponent("continue-watching-covers", isDirectory: true)
        }

        let fallbackDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return fallbackDirectory
            .appendingPathComponent("rezka-player", isDirectory: true)
            .appendingPathComponent("continue-watching-covers", isDirectory: true)
    }

    static func appGroupContainerURL() -> URL? {
        let appGroupID = appGroupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard appGroupID.isEmpty == false else { return nil }
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }

        return simulatorAppGroupContainerURL(appGroupID: appGroupID)
    }

    private static func write(_ payload: ContinueWatchingPayload, to url: URL) {
        guard let data = try? JSONEncoder().encode(payload) else {
            return
        }

        let directoryURL = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            print("ContinueWatchingStore write error: \(error.localizedDescription)")
        }
    }

    private static func loadFromSharedDefaults() -> ContinueWatchingPayload? {
        guard let data = sharedDefaults()?.data(forKey: sharedDefaultsKey),
              let payload = try? JSONDecoder().decode(ContinueWatchingPayload.self, from: data) else {
            return nil
        }

        return payload
    }

    private static func saveToSharedDefaults(_ payload: ContinueWatchingPayload) {
        guard let data = try? JSONEncoder().encode(payload) else {
            return
        }

        sharedDefaults()?.set(data, forKey: sharedDefaultsKey)
    }

    private static func sharedDefaults() -> UserDefaults? {
        let appGroupID = appGroupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard appGroupID.isEmpty == false else { return nil }
        return UserDefaults(suiteName: appGroupID)
    }

    private static func simulatorAppGroupContainerURL(appGroupID: String) -> URL? {
        let homePath = NSHomeDirectory()
        guard let dataContainersRange = homePath.range(of: "/data/Containers/") else {
            return nil
        }

        let deviceRoot = String(homePath[..<dataContainersRange.lowerBound])
        let appGroupsRoot = URL(fileURLWithPath: deviceRoot, isDirectory: true)
            .appendingPathComponent("data/Containers/Shared/AppGroup", isDirectory: true)

        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: appGroupsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for candidate in candidates {
            let metadataURL = candidate.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist", isDirectory: false)
            guard let metadata = NSDictionary(contentsOf: metadataURL) as? [String: Any],
                  let identifier = metadata["MCMMetadataIdentifier"] as? String,
                  identifier == appGroupID else {
                continue
            }

            return candidate
        }

        return nil
    }
}
