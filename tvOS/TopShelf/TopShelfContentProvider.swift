import Foundation
import os
import TVServices

@objc(TopShelfContentProvider)
public final class TopShelfContentProvider: TVTopShelfContentProvider {
    private let logger = Logger(subsystem: "com.dsoft.rezka-player.topshelf", category: "TopShelf")
    private let maxTopShelfItems = 6

    public override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        logger.info("loadTopShelfContent(completionHandler) called")
        completionHandler(buildTopShelfContent())
    }

    private func makeSectionedItem(from item: ContinueWatchingPayload.Item) -> TVTopShelfSectionedItem? {
        let topShelfItem = TVTopShelfSectionedItem(identifier: "\(item.mediaId)-\(Int(item.updatedAt.timeIntervalSince1970))")
        topShelfItem.title = item.title
        topShelfItem.imageShape = .poster
        topShelfItem.playbackProgress = min(max(item.progress, 0), 1)
        logger.info("prepare item id=\(item.mediaId, privacy: .public) title=\(item.title, privacy: .public)")

        if let imageURL = imageURL(for: item) {
            topShelfItem.setImageURL(imageURL, for: [.screenScale1x, .screenScale2x])
            logger.info("set image url: \(imageURL.absoluteString, privacy: .public)")
        }

        guard let resolvedActionURL = actionURL(for: item) else {
            logger.error("action URL build failed for id=\(item.mediaId, privacy: .public)")
            return nil
        }

        let action = TVTopShelfAction(url: resolvedActionURL)
        topShelfItem.displayAction = action
        topShelfItem.playAction = action
        return topShelfItem
    }

    private func actionURL(for item: ContinueWatchingPayload.Item) -> URL? {
        var components = URLComponents()
        components.scheme = "rezkaplayer"
        components.host = "continue"
        components.queryItems = [
            URLQueryItem(name: "title", value: item.title),
            URLQueryItem(name: "media_url", value: item.mediaURL),
            URLQueryItem(name: "cover_url", value: item.coverURL),
            URLQueryItem(name: "is_series", value: item.isSeries ? "1" : "0"),
            URLQueryItem(name: "season_title", value: item.seasonTitle),
            URLQueryItem(name: "episode_title", value: item.episodeTitle),
            URLQueryItem(name: "playback_position", value: String(item.playbackPosition))
        ]
        return components.url
    }

    private func buildTopShelfContent() -> TVTopShelfContent? {
        let payload = ContinueWatchingStore.load()
        if payload == nil {
            logger.error("continue-watching payload not found")
            let outputPath = ContinueWatchingStore.outputURL().path
            let fileExists = FileManager.default.fileExists(atPath: outputPath)
            logger.error("continue-watching path: \(outputPath, privacy: .public), exists: \(fileExists, privacy: .public)")
        }
        logger.info("payload loaded, items: \(payload?.items.count ?? 0, privacy: .public)")

        let items = (payload?.items ?? [])
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maxTopShelfItems)
            .compactMap(makeSectionedItem(from:))
        let resolvedItems = Array(items)
        guard resolvedItems.isEmpty == false else {
            logger.error("resolved items are empty")
            return nil
        }

        let collection = TVTopShelfItemCollection(items: resolvedItems)
        collection.title = "Продолжить просмотр"

        let content = TVTopShelfSectionedContent(sections: [collection])
        logger.info("Top Shelf content prepared with \(resolvedItems.count, privacy: .public) items")
        return content
    }

    private func imageURL(for item: ContinueWatchingPayload.Item) -> URL? {
        if let localPath = item.localCoverPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           localPath.isEmpty == false,
           FileManager.default.fileExists(atPath: localPath) {
            return URL(fileURLWithPath: localPath, isDirectory: false)
        }

        return URL(string: item.coverURL)
    }
}
