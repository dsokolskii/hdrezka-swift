import Foundation
import CryptoKit
import TVServices

enum ContinueWatchingEligibility {
    private static let minimalPlaybackPositionForContinue = 20.0
    private static let completionTolerance = 20.0

    static func resumePosition(position: Double, duration: Double) -> Double? {
        let safePosition = max(0, position)
        let safeDuration = max(0, duration)

        guard safeDuration > 0 else { return nil }
        guard safePosition > minimalPlaybackPositionForContinue else { return nil }
        guard safePosition < max(safeDuration - completionTolerance, minimalPlaybackPositionForContinue) else { return nil }
        return safePosition
    }
}

enum ContinueWatchingHistorySync {
    private static let maxRecentContinueItems = 6
    private static let progressEqualityTolerance = 1.0
    private static let historyStore = CloudKitDataStore<[DetailedHistoryMedia]>(
        recordType: "HistoryMedia",
        recordName: "history"
    )

    static func write(history: [DetailedHistoryMedia]) {
        let mappedItems = Array(history
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(50)
            .compactMap(mapItem)
        )
        let finalItems = reconcileWithExisting(mappedItems)

        let payload = ContinueWatchingPayload(
            generatedAt: Date(),
            items: attachExistingLocalCovers(to: finalItems)
        )

        ContinueWatchingStore.save(payload)
        TVTopShelfContentProvider.topShelfContentDidChange()

        Task.detached(priority: .utility) {
            await prefetchMissingCoversAndRewritePayload(items: payload.items)
        }
    }

    private static func mapItem(from history: DetailedHistoryMedia) -> ContinueWatchingPayload.Item? {
        let title = history.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let mediaURL = ConstantsApi.secureURLString(from: history.mediaURL)
        guard title.isEmpty == false, mediaURL.isEmpty == false else {
            return nil
        }

        let safePosition = max(0, history.playbackPosition)
        let safeDuration = max(0, history.playbackDuration)
        guard let resumePosition = ContinueWatchingEligibility.resumePosition(position: safePosition, duration: safeDuration) else {
            return nil
        }
        let progress = min(max(resumePosition / safeDuration, 0), 1)
        let subtitleParts = [history.seasonTitle, history.episodeTitle, playbackTimeString(seconds: resumePosition)]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        let subtitle = subtitleParts.joined(separator: " • ")

        return ContinueWatchingPayload.Item(
            mediaId: history.mediaId,
            title: title,
            subtitle: subtitle,
            coverURL: ConstantsApi.secureURLString(from: history.coverURL),
            localCoverPath: nil,
            mediaURL: mediaURL,
            playbackPosition: resumePosition,
            playbackDuration: safeDuration,
            progress: progress,
            isSeries: history.isSeries,
            seasonTitle: history.seasonTitle,
            episodeTitle: history.episodeTitle,
            updatedAt: history.updatedAt
        )
    }

    private static func reconcileWithExisting(_ mappedItems: [ContinueWatchingPayload.Item]) -> [ContinueWatchingPayload.Item] {
        let existingItems = ContinueWatchingStore.load()?.items ?? []
        let existingByMediaId = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.mediaId, $0) })

        let reconciled = mappedItems.map { item -> ContinueWatchingPayload.Item in
            guard let existing = existingByMediaId[item.mediaId] else {
                return item
            }

            // Keep the original "launch time" when playback progress did not materially change.
            let samePosition = abs(existing.playbackPosition - item.playbackPosition) < progressEqualityTolerance
            let sameDuration = abs(existing.playbackDuration - item.playbackDuration) < progressEqualityTolerance
            guard samePosition && sameDuration else {
                return item
            }

            return ContinueWatchingPayload.Item(
                mediaId: item.mediaId,
                title: item.title,
                subtitle: item.subtitle,
                coverURL: item.coverURL,
                localCoverPath: existing.localCoverPath ?? item.localCoverPath,
                mediaURL: item.mediaURL,
                playbackPosition: item.playbackPosition,
                playbackDuration: item.playbackDuration,
                progress: item.progress,
                isSeries: item.isSeries,
                seasonTitle: item.seasonTitle,
                episodeTitle: item.episodeTitle,
                updatedAt: existing.updatedAt
            )
        }

        return Array(reconciled
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maxRecentContinueItems)
        )
    }

    private static func playbackTimeString(seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }

        return String(format: "%02d:%02d", minutes, secs)
    }

    private static func attachExistingLocalCovers(to items: [ContinueWatchingPayload.Item]) -> [ContinueWatchingPayload.Item] {
        items.map { item in
            guard let localURL = localCoverURLForRemoteURLString(item.coverURL),
                  FileManager.default.fileExists(atPath: localURL.path) else {
                return item
            }
            return ContinueWatchingPayload.Item(
                mediaId: item.mediaId,
                title: item.title,
                subtitle: item.subtitle,
                coverURL: item.coverURL,
                localCoverPath: localURL.path,
                mediaURL: item.mediaURL,
                playbackPosition: item.playbackPosition,
                playbackDuration: item.playbackDuration,
                progress: item.progress,
                isSeries: item.isSeries,
                seasonTitle: item.seasonTitle,
                episodeTitle: item.episodeTitle,
                updatedAt: item.updatedAt
            )
        }
    }

    private static func prefetchMissingCoversAndRewritePayload(items: [ContinueWatchingPayload.Item]) async {
        var updatedItems: [ContinueWatchingPayload.Item] = []
        updatedItems.reserveCapacity(items.count)
        var hasChanges = false

        for item in items {
            if let existingPath = item.localCoverPath,
               FileManager.default.fileExists(atPath: existingPath) {
                updatedItems.append(item)
                continue
            }

            let secureCoverURL = ConstantsApi.secureURLString(from: item.coverURL)
            guard let remoteURL = URL(string: secureCoverURL),
                  let destinationURL = localCoverURLForRemoteURLString(secureCoverURL) else {
                updatedItems.append(item)
                continue
            }

            do {
                let directoryURL = ContinueWatchingStore.localCoversDirectoryURL()
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

                if FileManager.default.fileExists(atPath: destinationURL.path) == false {
                    let (data, response) = try await URLSession.shared.data(from: remoteURL)
                    if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) == false {
                        updatedItems.append(item)
                        continue
                    }
                    try data.write(to: destinationURL, options: .atomic)
                }

                hasChanges = true
                updatedItems.append(
                    ContinueWatchingPayload.Item(
                        mediaId: item.mediaId,
                        title: item.title,
                        subtitle: item.subtitle,
                        coverURL: secureCoverURL,
                        localCoverPath: destinationURL.path,
                        mediaURL: item.mediaURL,
                        playbackPosition: item.playbackPosition,
                        playbackDuration: item.playbackDuration,
                        progress: item.progress,
                        isSeries: item.isSeries,
                        seasonTitle: item.seasonTitle,
                        episodeTitle: item.episodeTitle,
                        updatedAt: item.updatedAt
                    )
                )
            } catch {
                updatedItems.append(item)
            }
        }

        guard hasChanges else { return }

        ContinueWatchingStore.save(
            ContinueWatchingPayload(
                generatedAt: Date(),
                items: updatedItems
            )
        )

        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    static func refreshFromStoredHistory() async {
        guard let history = try? await historyStore.load(), history.isEmpty == false else {
            return
        }

        write(history: history)
    }

    private static func localCoverURLForRemoteURLString(_ string: String) -> URL? {
        let trimmed = ConstantsApi.secureURLString(from: string)
        guard trimmed.isEmpty == false else { return nil }

        let digest = SHA256.hash(data: Data(trimmed.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        let ext = URL(string: trimmed)?.pathExtension.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let safeExt = (ext?.isEmpty == false) ? ext! : "jpg"
        return ContinueWatchingStore.localCoversDirectoryURL().appendingPathComponent("\(hash).\(safeExt)", isDirectory: false)
    }
}
