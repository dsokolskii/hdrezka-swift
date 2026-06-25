import SwiftUI
import OrderedCollections

@MainActor
final class DetailedMediaItemViewModel: ObservableObject {
    private struct PlaybackStateSnapshot {
        let translation: Int
        let season: Int?
        let episode: Int?
        let quality: Media.Quality
        let streams: StreamMedia?
        let selectedPlaybackStream: String?
        let phase: DataFetchPhase<DetailedMedia>
    }
    
    @Published var phase = DataFetchPhase<DetailedMedia>.fetching
    @Published private(set) var isFetching = true
    @Published private(set) var isPreparingPlayback = false
    @Published private(set) var playbackErrorMessage: String?
    
    private let rezkaAPI = MediaRezkaApi()
    
    private let cache: DiskCache<[DetailedMedia]> = .init(filename: "xcadmediacache", expirationInterval: 30 * 60)
    
    private let historyStorage = CloudKitDataStore<[DetailedHistoryMedia]>(recordType: "HistoryMedia", recordName: "history")
    
    private let settingsStorage = CloudKitDataStore<MediaSettings>(recordType: "SettingsMedia", recordName: "settings")
    
    private var settings: MediaSettings = .init()
    
    private var history: [DetailedHistoryMedia] = .init()

    private let playbackProgressPersistenceInterval: TimeInterval = 30
    private let immediatePlaybackProgressThreshold = 20.0
    private let seekPlaybackProgressDelta = 60.0
    private var lastPlaybackProgressPersistenceDate: Date?
    private var lastPersistedPlaybackPosition: Double?
    private var historyPersistenceTask: Task<Void, Never>?
    private var needsHistoryPersistenceAfterCurrent = false
    
    let media: Media
    private var detailedMedia: DetailedMedia {
        phase.value ?? DetailedMedia.previewData
    }
    
    @Published private(set) var historyMedia: DetailedHistoryMedia
    
    private(set) var router = HLSURLRouter(cache: URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024, diskPath: "AVPlayerCache"))
    
    private(set) var loader: HLSCachingLoader
    
    init(media: Media) {
        self.media = media
        self.loader = HLSCachingLoader(router: router, cache: router.cache)
        historyMedia = DetailedHistoryMedia(mediaId: 0)
    }
    
    var title: String {
        detailedMedia.title
    }
    
    var originalTitle: String {
        detailedMedia.titleOriginal
    }
    
    var coverUrl: URL? {
        ConstantsApi.secureURL(from: detailedMedia.coverUrl)
    }
    
    var info: OrderedDictionary<String, String> {
        detailedMedia.info
    }
    
    var description: String {
        detailedMedia.description
    }
    
    var currentTranslationTitle: String? {
        detailedMedia.translations.isEmpty == false ? detailedMedia.translations[historyMedia.translation] : nil
    }
    
    var nextSeasonId: Int? {
        guard let seasons = seasonsInCurrentTranslation,
              let currentSeason = historyMedia.season else {
            return nil
        }

        let ids = Array(seasons.keys)
        guard let index = ids.firstIndex(of: currentSeason), ids.indices.contains(index + 1) else {
            return nil
        }

        return ids[index + 1]
    }
    
    var currentSeasonTitle: String {
        guard let currentSeason = historyMedia.season else {
            return "-"
        }
        
        return season?.seasons[currentSeason] ?? "-"
    }
    
    var seasonsInCurrentTranslation: OrderedDictionary<Int, String>? {
        return detailedMedia.seasons(in: historyMedia.translation)
    }
    
    var currentEpisodeTitle: String {
        episode?.title ?? "-"
    }

    var resumePlaybackPosition: Double? {
        ContinueWatchingEligibility.resumePosition(
            position: historyMedia.playbackPosition,
            duration: historyMedia.playbackDuration
        )
    }

    var resumePlaybackTitle: String {
        guard let seconds = resumePlaybackPosition else { return "Продолжить" }
        let time = formatPlaybackTime(seconds)
        guard media.isSeries else {
            return "Продолжить с \(time)"
        }

        let seasonTitle = currentSeasonTitle == "-" ? nil : currentSeasonTitle
        let episodeTitle = currentEpisodeTitle == "-" ? nil : currentEpisodeTitle
        let episodeInfo: String
        if let seasonTitle, let episodeTitle {
            episodeInfo = "\(seasonTitle) • \(episodeTitle)"
        } else if let episodeTitle {
            episodeInfo = episodeTitle
        } else if let seasonTitle {
            episodeInfo = seasonTitle
        } else {
            episodeInfo = ""
        }

        if episodeInfo.isEmpty {
            return "Продолжить с \(time)"
        }
        return "Продолжить \(episodeInfo) с \(time)"
    }

    var resumePlaybackCompactTitle: String {
        guard let seconds = resumePlaybackPosition else { return "Продолжить" }
        let time = formatPlaybackTime(seconds)

        guard media.isSeries else {
            return "Продолжить • \(time)"
        }

        let seasonTitle = currentSeasonTitle == "-" ? nil : currentSeasonTitle
        let episodeTitle = currentEpisodeTitle == "-" ? nil : currentEpisodeTitle

        var parts: [String] = []
        if let seasonTitle {
            parts.append(seasonTitle)
        }
        if let episodeTitle {
            parts.append(episodeTitle)
        }
        parts.append(time)
        return parts.joined(separator: " • ")
    }
    
    var nextEpisodeId: Int? {
        guard let episodes = episodes,
              let currentId = episode?.id,
              let index = episodes.firstIndex(where: { $0.id == currentId }),
              episodes.indices.contains(index + 1) else {
            return nil
        }

        return episodes[index + 1].id
    }

    var nextPlayableEpisode: (season: Int, episode: Int)? {
        if let currentSeason = historyMedia.season, let nextEpisodeId {
            return (currentSeason, nextEpisodeId)
        }

        guard let nextSeasonId,
              let firstEpisodeId = season?.episodes[nextSeasonId]?.first?.id else {
            return nil
        }

        return (nextSeasonId, firstEpisodeId)
    }

    var previousEpisodeId: Int? {
        guard let episodes = episodes,
              let currentId = episode?.id,
              let index = episodes.firstIndex(where: { $0.id == currentId }),
              episodes.indices.contains(index - 1) else {
            return nil
        }

        return episodes[index - 1].id
    }
    
    func setQuality(_ quality: Media.Quality) {
        guard let availableQualities = streams?.qualities, availableQualities.contains(quality) else {
            return
        }

        historyMedia.quality = quality
        selectedPlaybackStream = nil
        historyMedia.updatedAt = Date()
        phase = .success(detailedMedia)
        playbackErrorMessage = nil
        settings.quality = quality
        Task {
            try? await settingsStorage.save(settings)
            try? await persistHistory()
        }
    }

    func clearPlaybackProgress() {
        historyMedia.playbackPosition = 0
        historyMedia.playbackDuration = 0
        historyMedia.updatedAt = Date()
        objectWillChange.send()

        Task {
            try? await persistHistory()
        }
    }

    func persistPlaybackProgress(position: Double, duration: Double, didFinish: Bool = false, force: Bool = false) {
        if didFinish {
            historyMedia.playbackPosition = 0
            historyMedia.playbackDuration = 0
        } else {
            let safePosition = max(0, position)
            let safeDuration = max(0, duration)
            historyMedia.playbackPosition = min(safePosition, safeDuration > 0 ? safeDuration : safePosition)
            historyMedia.playbackDuration = safeDuration
        }
        historyMedia.updatedAt = Date()

        guard shouldPersistPlaybackProgress(didFinish: didFinish, force: force) else {
            return
        }

        lastPlaybackProgressPersistenceDate = Date()
        lastPersistedPlaybackPosition = historyMedia.playbackPosition
        objectWillChange.send()
        persistHistoryInBackground()
    }
    
    @Published private(set) var streams: StreamMedia?
    @Published private(set) var selectedPlaybackStream: String?
    var stream: String {
        selectedPlaybackStream ?? streams?.stream(historyMedia.quality) ?? ""
    }

    func loadDetailedMedia() async {
        if Task.isCancelled { return }
        
        try? await cache.loadFromDisk()
        history = (try? await historyStorage.load()) ?? .init()
        settings = (try? await settingsStorage.load()) ?? .init()
        
        if let medias = await cache.value(forKey: "detailed_media_\(media.id)"), let media = medias.first {
            phase = .success(media)
        } else {
            phase = .fetching
        }
        
        await loadData()
    }
    
    private func loadData() async {
        isFetching = true
        do {
            var detailedMedia = try await rezkaAPI.fetchDetails(from: media)
            if Task.isCancelled { return }
            
            guard var currentTranslationId = detailedMedia.translations.keys.first else {
                phase = .failure(DataError.generate(for: .rezkaConstantsApi, error: .empty))
                return
            }
            
            let preferedTranslation = settings.translationId
            if detailedMedia.translations.keys.contains(preferedTranslation) {
                currentTranslationId = preferedTranslation
            }
            
            if let history = history.first(where: { $0.mediaId ==  detailedMedia.mediaId }) {
                historyMedia = history
                currentTranslationId = history.translation
            } else {
                historyMedia = DetailedHistoryMedia(mediaId: detailedMedia.mediaId, translation: currentTranslationId)
            }
            syncHistoryMetadata(with: detailedMedia)

            if media.isSeries {
                detailedMedia = try await rezkaAPI.fetchSeriesDetails(for: detailedMedia, translation: currentTranslationId)
            }

            historyMedia.translation = currentTranslationId
            
            await cache.setValue([detailedMedia], forKey: "detailed_media_\(media.id)")
            try? await cache.saveToDisk()
            
            phase = .success(detailedMedia)
            syncSeriesSelectionToAvailableData()
            isFetching = false

            do {
                try await preloadInitialPlayback(translationId: currentTranslationId, mediaId: detailedMedia.mediaId)
            } catch {
                // Keep the detail screen usable even when the CDN stream is temporarily unavailable.
            }
            
        } catch {
            if Task.isCancelled { return }
            phase = .failure(error)
            isFetching = false
        }
    }
    
    var translations: OrderedDictionary<Int, String> {
        detailedMedia.translations
    }
    
    var season: SeasonsData? {
        detailedMedia.seasons[historyMedia.translation]
    }
    
    var episodes: [Episode]? {
        guard let currentSeason = historyMedia.season else {
            return nil
        }
        
        return season?.episodes[currentSeason]
    }
    
    var episode: Episode? {
        episodes?.first{ $0.id == historyMedia.episode }
    }
    
    func setCurrentTranslation(id: Int, mediaId: Int? = nil, resetPlaybackProgress: Bool = true) async throws {
        let snapshot = playbackStateSnapshot()

        do {
            historyMedia.translation = id

            if media.isSeries, (mediaId == nil || seasonsInCurrentTranslation == nil) {
                phase = .success(try await rezkaAPI.fetchSeriesDetails(for: detailedMedia, translation: id))
                syncSeriesSelectionToAvailableData()
            } else {
                phase = .success(detailedMedia)
            }

            if resetPlaybackProgress {
                historyMedia.playbackPosition = 0
                historyMedia.playbackDuration = 0
            }
            try await updateStreams(of: mediaId ?? detailedMedia.mediaId)

            settings.translationId = id
            try await settingsStorage.save(settings)
        } catch {
            restorePlaybackState(from: snapshot)
            throw error
        }
    }

    func setCurrentSeason(id: Int) async throws {
        let previousSeason = historyMedia.season

        do {
            historyMedia.season = id
            guard let firstEpisodeId = season?.episodes[id]?.first?.id else {
                historyMedia.episode = nil
                phase = .success(detailedMedia)
                return
            }
            try await setCurrentEpisode(id: firstEpisodeId)
        } catch {
            historyMedia.season = previousSeason
            throw error
        }
    }

    func setCurrentEpisode(id: Int) async throws {
        let snapshot = playbackStateSnapshot()

        do {
            historyMedia.episode = id

            historyMedia.playbackPosition = 0
            historyMedia.playbackDuration = 0
            try await updateStreams(of: detailedMedia.mediaId)

            phase = .success(detailedMedia)
        } catch {
            restorePlaybackState(from: snapshot)
            throw error
        }
    }
    
    private func updateStreams(of mediaId: Int) async throws {
        streams = try await rezkaAPI.stream(mediaId: mediaId, translationId: historyMedia.translation, season: historyMedia.season, episode: historyMedia.episode)
        selectedPlaybackStream = nil
        historyMedia.quality = resolvedQuality(for: streams)
        historyMedia.updatedAt = Date()
        
        try await persistHistory()
    }

    private func resolvedQuality(for streams: StreamMedia?) -> Media.Quality {
        guard let streams else {
            return .unknown
        }

        let preferredQuality = settings.quality
        if preferredQuality != .unknown,
           let availableQualities = streams.qualities,
           availableQualities.contains(preferredQuality) {
            return preferredQuality
        }

        return streams.bestQualityId
    }

    private func preloadInitialPlayback(translationId: Int, mediaId: Int) async throws {
        historyMedia.translation = translationId
        syncSeriesSelectionToAvailableData()
        try await updateStreams(of: mediaId)

        settings.translationId = translationId
        try? await settingsStorage.save(settings)
    }

    private func persistHistory() async throws {
        history.removeAll { $0.mediaId == historyMedia.mediaId }
        syncHistoryMetadata(with: detailedMedia)
        history.append(historyMedia)
        history.sort { $0.updatedAt > $1.updatedAt }
        do {
            try await historyStorage.save(history)
        } catch {
            print("History cloud save failed: \(error.localizedDescription)")
        }
        ContinueWatchingHistorySync.write(history: history)
    }

    private func shouldPersistPlaybackProgress(didFinish: Bool, force: Bool) -> Bool {
        if didFinish || force {
            return true
        }

        let position = historyMedia.playbackPosition
        guard position >= immediatePlaybackProgressThreshold else {
            return false
        }

        guard let lastPlaybackProgressPersistenceDate else {
            return true
        }

        if Date().timeIntervalSince(lastPlaybackProgressPersistenceDate) >= playbackProgressPersistenceInterval {
            return true
        }

        if let lastPersistedPlaybackPosition,
           abs(position - lastPersistedPlaybackPosition) >= seekPlaybackProgressDelta {
            return true
        }

        return false
    }

    private func persistHistoryInBackground() {
        guard historyPersistenceTask == nil else {
            needsHistoryPersistenceAfterCurrent = true
            return
        }

        historyPersistenceTask = Task { [weak self] in
            guard let self else { return }

            repeat {
                self.needsHistoryPersistenceAfterCurrent = false
                try? await self.persistHistory()
            } while self.needsHistoryPersistenceAfterCurrent

            self.historyPersistenceTask = nil
        }
    }

    private func syncHistoryMetadata(with detailedMedia: DetailedMedia) {
        historyMedia.title = detailedMedia.title
        historyMedia.coverURL = detailedMedia.coverUrl
        historyMedia.mediaURL = media.url
        historyMedia.isSeries = media.isSeries
        historyMedia.seasonTitle = currentSeasonTitle == "-" ? "" : currentSeasonTitle
        historyMedia.episodeTitle = currentEpisodeTitle == "-" ? "" : currentEpisodeTitle
    }

    private func syncSeriesSelectionToAvailableData() {
        guard media.isSeries else { return }
        guard let seasons = seasonsInCurrentTranslation, seasons.isEmpty == false else {
            historyMedia.season = nil
            historyMedia.episode = nil
            return
        }

        let seasonIDs = Array(seasons.keys)
        let resolvedSeason = historyMedia.season.flatMap { seasonIDs.contains($0) ? $0 : nil } ?? seasonIDs[0]
        historyMedia.season = resolvedSeason

        let seasonEpisodes = season?.episodes[resolvedSeason] ?? []
        guard seasonEpisodes.isEmpty == false else {
            historyMedia.episode = nil
            return
        }

        let resolvedEpisode = historyMedia.episode.flatMap { episodeID in
            seasonEpisodes.contains(where: { $0.id == episodeID }) ? episodeID : nil
        } ?? seasonEpisodes[0].id
        historyMedia.episode = resolvedEpisode
    }

    private func formatPlaybackTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }

        return String(format: "%02d:%02d", minutes, secs)
    }

    func preparePlayback() async -> Bool {
        guard isPreparingPlayback == false else {
            return false
        }

        isPreparingPlayback = true
        playbackErrorMessage = nil
        defer { isPreparingPlayback = false }

        do {
            // Rezka stream URLs expire quickly, so fetch a fresh one on every play attempt.
            try await updateStreams(of: detailedMedia.mediaId)
            selectedPlaybackStream = await firstAvailablePlaybackStream()
            return selectedPlaybackStream?.isEmpty == false
        } catch {
            playbackErrorMessage = error.localizedDescription
            return false
        }
    }

    private func firstAvailablePlaybackStream() async -> String? {
        guard let streams else {
            return nil
        }

        let qualityURLs = streams.streams(historyMedia.quality)
        for streamURL in qualityURLs {
            guard await isPlaybackStreamAvailable(streamURL) else {
                continue
            }
            return streamURL
        }

        return qualityURLs.first
    }

    private nonisolated func isPlaybackStreamAvailable(_ stream: String) async -> Bool {
        guard let url = URL(string: stream) else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue(ApiConstants.userAgent, forHTTPHeaderField: ApiConstants.userAgentKey)
        request.setValue("\(ConstantsApi.server)/", forHTTPHeaderField: "Referer")
        request.setValue(ConstantsApi.server, forHTTPHeaderField: "Origin")
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")

        do {
            let (_, response) = try await RezkaURLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            return (200...399).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    func presentPlaybackError(_ error: Error) {
        isFetching = false
        playbackErrorMessage = error.localizedDescription

        if phase.value == nil {
            phase = .failure(error)
        }
    }

    func clearPlaybackError() {
        playbackErrorMessage = nil
    }

    func refreshPlaybackState() {
        objectWillChange.send()
    }

    private func playbackStateSnapshot() -> PlaybackStateSnapshot {
        PlaybackStateSnapshot(
            translation: historyMedia.translation,
            season: historyMedia.season,
            episode: historyMedia.episode,
            quality: historyMedia.quality,
            streams: streams,
            selectedPlaybackStream: selectedPlaybackStream,
            phase: phase
        )
    }

    private func restorePlaybackState(from snapshot: PlaybackStateSnapshot) {
        historyMedia.translation = snapshot.translation
        historyMedia.season = snapshot.season
        historyMedia.episode = snapshot.episode
        historyMedia.quality = snapshot.quality
        streams = snapshot.streams
        selectedPlaybackStream = snapshot.selectedPlaybackStream
        phase = snapshot.phase
    }
}
