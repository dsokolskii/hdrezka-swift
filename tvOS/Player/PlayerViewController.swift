import AVKit
import SwiftUI

typealias Representable = UIViewControllerRepresentable
typealias ViewControllerType = AVPlayerViewController

struct PlayerViewController: Representable {
    typealias NSViewControllerType = ViewControllerType

    struct TransportControlTranslation: Identifiable {
        let id: Int
        let title: String
        let isSelected: Bool
    }

    struct TransportControlQuality: Identifiable {
        let id: String
        let title: String
        let isSelected: Bool
    }

    struct TransportControls {
        let mediaTitle: String?
        let mediaSubtitle: String?
        let translations: [TransportControlTranslation]
        let qualities: [TransportControlQuality]
        let canGoToPreviousEpisode: Bool
        let canGoToNextEpisode: Bool
        let onSelectTranslation: ((Int) -> Void)?
        let onSelectQuality: ((String) -> Void)?
        let onPreviousEpisode: (() -> Void)?
        let onNextEpisode: (() -> Void)?
    }

    final class Coordinator: NSObject {
        private var statusObservation: NSKeyValueObservation?
        private var errorObservation: NSKeyValueObservation?
        private var timeControlObservation: NSKeyValueObservation?
        private var itemErrorLogObserver: NSObjectProtocol?
        private var itemFailedObserver: NSObjectProtocol?
        private var didPlayToEndObserver: NSObjectProtocol?
        private var timeObserver: Any?
        private weak var player: AVPlayer?
        private var progressCallback: ((Double, Double) -> Void)?
        private var failureCallback: ((String) -> Void)?
        private var didReportFailure = false

        static let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("player-debug.log")

        static func log(_ message: String) {
            let line = "[\(Date())] \(message)\n"
            print(line, terminator: "")

            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logURL.path) == false {
                    FileManager.default.createFile(atPath: logURL.path, contents: data)
                } else if let handle = try? FileHandle(forWritingTo: logURL) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    _ = try? handle.write(contentsOf: data)
                }
            }
        }

        func attach(
            to player: AVPlayer,
            onProgress: ((Double, Double) -> Void)?,
            onFinish: (() -> Void)?,
            onFailure: ((String) -> Void)?
        ) {
            detach()
            guard let item = player.currentItem else { return }
            self.player = player
            self.progressCallback = onProgress
            self.failureCallback = onFailure
            self.didReportFailure = false

            statusObservation = item.observe(\.status, options: [.initial, .new]) { item, _ in
                Self.log("PLAYER item.status=\(item.status.rawValue) error=\(item.error?.localizedDescription ?? "nil")")
                if item.status == .failed {
                    self.reportFailure(item.error?.localizedDescription ?? "Не удалось воспроизвести видео.")
                }
            }

            errorObservation = item.observe(\.error, options: [.new]) { item, _ in
                if let error = item.error {
                    Self.log("PLAYER item.error=\(error.localizedDescription)")
                    self.reportFailure(error.localizedDescription)
                }
            }

            timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { player, _ in
                Self.log("PLAYER timeControlStatus=\(player.timeControlStatus.rawValue) reason=\(player.reasonForWaitingToPlay?.rawValue ?? "nil")")
            }

            itemErrorLogObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemNewErrorLogEntry,
                object: item,
                queue: .main
            ) { _ in
                let events = item.errorLog()?.events ?? []
                Self.log("PLAYER errorLog.events=\(events.count)")
                for event in events {
                    Self.log("PLAYER errorLog status=\(event.errorStatusCode) domain=\(event.errorDomain) comment=\(event.errorComment ?? "nil") uri=\(event.uri ?? "nil") server=\(event.serverAddress ?? "nil")")
                }
            }

            itemFailedObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
                Self.log("PLAYER failedToPlayToEnd=\(error?.localizedDescription ?? "nil")")
                self.reportFailure(error?.localizedDescription ?? "Не удалось воспроизвести видео.")
            }

            didPlayToEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                onFinish?()
            }

            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] _ in
                guard let self else { return }
                self.reportProgress()
            }
        }

        func detach() {
            if let itemErrorLogObserver {
                NotificationCenter.default.removeObserver(itemErrorLogObserver)
            }
            if let itemFailedObserver {
                NotificationCenter.default.removeObserver(itemFailedObserver)
            }
            if let didPlayToEndObserver {
                NotificationCenter.default.removeObserver(didPlayToEndObserver)
            }
            if let timeObserver, let player {
                player.removeTimeObserver(timeObserver)
            }

            statusObservation = nil
            errorObservation = nil
            timeControlObservation = nil
            itemErrorLogObserver = nil
            itemFailedObserver = nil
            didPlayToEndObserver = nil
            timeObserver = nil
            failureCallback = nil
            didReportFailure = false
        }

        private func reportProgress() {
            guard let player else { return }
            let position = player.currentTime().seconds
            let duration = player.currentItem?.duration.seconds ?? .zero
            guard position.isFinite, duration.isFinite else { return }
            progressCallback?(position, duration)
        }

        deinit {
            detach()
            reportProgress()
        }

        private func reportFailure(_ message: String) {
            guard didReportFailure == false else { return }
            didReportFailure = true
            DispatchQueue.main.async { [failureCallback] in
                failureCallback?(message)
            }
        }
    }
    
    let videoURL: URL?
    let initialTime: Double
    let onProgress: ((Double, Double) -> Void)?
    let onFinish: (() -> Void)?
    let onFailure: ((String) -> Void)?
    let transportControls: TransportControls?

    init(
        videoURL: URL?,
        initialTime: Double = 0,
        onProgress: ((Double, Double) -> Void)? = nil,
        onFinish: (() -> Void)? = nil,
        onFailure: ((String) -> Void)? = nil,
        transportControls: TransportControls? = nil
    ) {
        self.videoURL = videoURL
        self.initialTime = initialTime
        self.onProgress = onProgress
        self.onFinish = onFinish
        self.onFailure = onFailure
        self.transportControls = transportControls
    }
    
    private func makePlayerItem(for playbackURL: URL) -> AVPlayerItem {
        var options: [String: Any] = [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ]
        let cookies = HTTPCookieStorage.shared.cookies(for: playbackURL) ?? []
        options[AVURLAssetHTTPCookiesKey] = cookies

        let asset = AVURLAsset(url: playbackURL, options: options)
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = TimeInterval(180)
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        applyMetadata(to: playerItem)
        return playerItem
    }

    private func makePlayer() -> AVPlayer {
        guard let playbackURL else {
            return AVPlayer()
        }

        let player = AVPlayer(playerItem: makePlayerItem(for: playbackURL))
        player.automaticallyWaitsToMinimizeStalling = true
        return player
    }

    private var playbackURL: URL? {
        guard let videoURL else {
            return nil
        }

#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["REZKA_SIMULATOR_PROXY"] == "1" {
            return simulatorProxyURL(for: videoURL)
        }
#endif
        return videoURL
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> NSViewControllerType {
        let controller = AVPlayerViewController()
        controller.modalPresentationStyle = .fullScreen
        if let playbackURL {
            Coordinator.log("PLAYER open url=\(playbackURL.absoluteString)")
            Coordinator.log("PLAYER host=\(playbackURL.host ?? "nil") scheme=\(playbackURL.scheme ?? "nil") path=\(playbackURL.path)")
            Coordinator.log("PLAYER debug file=\(Coordinator.logURL.path)")
        }
        controller.player = makePlayer()
        if let player = controller.player {
            configureTransportControls(for: controller, player: player)
            context.coordinator.attach(to: player, onProgress: onProgress, onFinish: onFinish, onFailure: onFailure)
            startPlayback(player: player, at: initialTime)
        }
        return controller
    }

    func updateUIViewController(_ playerController: NSViewControllerType, context: Context) {
        updatePlayback(in: playerController, context: context)
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.detach()
        uiViewController.player?.pause()
        uiViewController.player?.replaceCurrentItem(with: nil)
        uiViewController.player = nil
    }

    private func updatePlayback(in controller: AVPlayerViewController, context: Context) {
        guard let player = controller.player else { return }
        guard let playbackURL else {
            player.pause()
            player.replaceCurrentItem(with: nil)
            return
        }

        configureTransportControls(for: controller, player: player)

        if currentAssetURL(of: player) == playbackURL {
            if let currentItem = player.currentItem {
                applyMetadata(to: currentItem)
            }
            return
        }

        let item = makePlayerItem(for: playbackURL)
        player.pause()
        player.replaceCurrentItem(with: item)
        context.coordinator.attach(to: player, onProgress: onProgress, onFinish: onFinish, onFailure: onFailure)
        startPlayback(player: player, at: initialTime)
    }

    private func currentAssetURL(of player: AVPlayer) -> URL? {
        guard let asset = player.currentItem?.asset as? AVURLAsset else { return nil }
        return asset.url
    }

    private func startPlayback(player: AVPlayer, at time: Double) {
        if time > 0, time.isFinite {
            player.seek(
                to: CMTime(seconds: time, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { _ in
                player.play()
            }
        } else {
            player.play()
        }
    }

    private func seekAction(title: String, seconds: Double, player: AVPlayer) -> UIAction {
        UIAction(title: title) { _ in
            let current = player.currentTime().seconds
            guard current.isFinite else { return }

            let duration = player.currentItem?.duration.seconds ?? .zero
            var target = current + seconds
            target = max(0, target)

            if duration.isFinite, duration > 0 {
                target = min(target, duration)
            }

            player.seek(
                to: CMTime(seconds: target, preferredTimescale: 600),
                toleranceBefore: .positiveInfinity,
                toleranceAfter: .positiveInfinity
            )
        }
    }

    private func configureTransportControls(for controller: AVPlayerViewController, player: AVPlayer) {
        controller.transportBarIncludesTitleView = true
        if let title = transportControls?.mediaTitle {
            if let subtitle = transportControls?.mediaSubtitle, subtitle.isEmpty == false {
                controller.title = "\(title) • \(subtitle)"
            } else {
                controller.title = title
            }
        } else {
            controller.title = nil
        }

        var items: [UIMenuElement] = []

        if let transportControls {
            if transportControls.translations.isEmpty == false {
                let actions: [UIAction] = transportControls.translations.map { translation in
                    UIAction(
                        title: translation.title,
                        state: translation.isSelected ? .on : .off
                    ) { _ in
                        transportControls.onSelectTranslation?(translation.id)
                    }
                }

                items.append(
                    UIMenu(
                        title: "Озвучка",
                        image: UIImage(systemName: "music.mic"),
                        children: actions
                    )
                )
            }

            if transportControls.qualities.isEmpty == false {
                let actions: [UIAction] = transportControls.qualities.map { quality in
                    UIAction(
                        title: quality.title,
                        state: quality.isSelected ? .on : .off
                    ) { _ in
                        transportControls.onSelectQuality?(quality.id)
                    }
                }

                items.append(
                    UIMenu(
                        title: "Качество",
                        image: UIImage(systemName: "rectangle.compress.vertical"),
                        children: actions
                    )
                )
            }

            if transportControls.canGoToPreviousEpisode {
                items.append(
                    UIAction(title: "Предыдущая серия", image: UIImage(systemName: "backward.fill")) { _ in
                        transportControls.onPreviousEpisode?()
                    }
                )
            }

            if transportControls.canGoToNextEpisode {
                items.append(
                    UIAction(title: "Следующая серия", image: UIImage(systemName: "forward.fill")) { _ in
                        transportControls.onNextEpisode?()
                    }
                )
            }
        }

        let seekActions: [UIAction] = [
            seekAction(title: "-15 мин", seconds: -900, player: player),
            seekAction(title: "+15 мин", seconds: 900, player: player),
            seekAction(title: "-30 мин", seconds: -1800, player: player),
            seekAction(title: "+30 мин", seconds: 1800, player: player)
        ]
        items.append(
            UIMenu(
                title: "Перемотка",
                image: UIImage(systemName: "goforward.10"),
                children: seekActions
            )
        )

        controller.transportBarCustomMenuItems = items
    }

    private func applyMetadata(to item: AVPlayerItem) {
        guard let transportControls else {
            item.externalMetadata = []
            return
        }

        var metadata: [AVMetadataItem] = []
        if let title = transportControls.mediaTitle, title.isEmpty == false {
            metadata.append(metadataItem(identifier: .commonIdentifierTitle, value: title))
        }
        if let subtitle = transportControls.mediaSubtitle, subtitle.isEmpty == false {
            metadata.append(metadataItem(identifier: .iTunesMetadataTrackSubTitle, value: subtitle))
        }
        item.externalMetadata = metadata
    }

    private func metadataItem(identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "ru-RU"
        return item.copy() as? AVMetadataItem ?? item
    }
    
    private func simulatorProxyURL(for url: URL) -> URL? {
        guard let scheme = url.scheme,
              let host = url.host else {
            return url
        }

        let sourceComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = 8642
        components.percentEncodedPath = "/\(scheme)/\(host)\(sourceComponents?.percentEncodedPath ?? url.path)"
        components.percentEncodedQuery = sourceComponents?.percentEncodedQuery
        return components.url
    }
}
