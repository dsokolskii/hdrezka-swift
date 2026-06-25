import SwiftUI
import ImageIO
import AVKit
import AVFoundation

struct WatchMediaDetailView: View {
    @Environment(AppContainer.self) private var container
    let media: Media

    @State private var detailedMedia: DetailedMedia?
    @State private var isLoading = false
    @State private var isUpdatingPlaybackOptions = false
    @State private var selectedTranslationID: Int?
    @State private var selectedSeasonID: Int?
    @State private var selectedEpisodeID: Int?
    @State private var selectedQuality: Media.Quality = .unknown
    @State private var streams: StreamMedia?
    @State private var playbackRequest: WatchPlaybackRequest?
    @State private var errorMessage: String?
    @State private var playbackErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                WatchPosterView(url: media.coverURL)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(detailedMedia?.title ?? media.title)
                        .font(.headline)

                    if let titleOriginal = detailedMedia?.titleOriginal,
                       titleOriginal.isEmpty == false,
                       titleOriginal != detailedMedia?.title {
                        Text(titleOriginal)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let seriesInfo = media.seriesInfo, seriesInfo.isEmpty == false {
                        Label(seriesInfo, systemImage: "play.square.stack")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let detailedMedia {
                    WatchPlaybackControls(
                        detailedMedia: detailedMedia,
                        selectedTranslationID: translationBinding,
                        selectedSeasonID: seasonBinding,
                        selectedEpisodeID: episodeBinding,
                        selectedQuality: $selectedQuality,
                        availableQualities: streams?.qualities ?? []
                    )

                    WatchInfoGrid(info: detailedMedia.info.map { ($0.key, $0.value) })

                    if detailedMedia.description.isEmpty == false {
                        Text(detailedMedia.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if media.descriptionShort.isEmpty == false {
                    Text(media.descriptionShort)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                Button {
                    Task {
                        await startPlayback()
                    }
                } label: {
                    Label(playButtonTitle, systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(detailedMedia == nil || isLoading || isUpdatingPlaybackOptions)

                if isUpdatingPlaybackOptions {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                if let playbackErrorMessage {
                    Text(playbackErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Повторить", action: loadDetails)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(media.title)
        .task(loadDetails)
        .sheet(item: $playbackRequest) { request in
            WatchPlaybackView(request: request)
        }
    }

    private func loadDetails() {
        guard detailedMedia == nil, isLoading == false else { return }

        Task {
            isLoading = true
            errorMessage = nil
            do {
                let loadedMedia = try await container.mediaRepository.fetchDetails(from: media, translation: nil)
                detailedMedia = loadedMedia
                syncDefaultSelection(for: loadedMedia)
                await refreshStreams()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private var translationBinding: Binding<Int> {
        Binding {
            selectedTranslationID ?? detailedMedia?.translations.keys.first ?? 0
        } set: { id in
            Task {
                await setTranslation(id)
            }
        }
    }

    private var seasonBinding: Binding<Int> {
        Binding {
            selectedSeasonID ?? seasons.first?.key ?? 0
        } set: { id in
            Task {
                await setSeason(id)
            }
        }
    }

    private var episodeBinding: Binding<Int> {
        Binding {
            selectedEpisodeID ?? episodes.first?.id ?? 0
        } set: { id in
            selectedEpisodeID = id
            Task {
                await refreshStreams()
            }
        }
    }

    private var selectedTranslation: Int? {
        selectedTranslationID ?? detailedMedia?.translations.keys.first
    }

    private var seasons: [(key: Int, value: String)] {
        guard let detailedMedia, let selectedTranslation else { return [] }
        return detailedMedia.seasons(in: selectedTranslation)?.map { ($0.key, $0.value) } ?? []
    }

    private var episodes: [Episode] {
        guard let detailedMedia, let selectedTranslation, let selectedSeasonID else { return [] }
        return detailedMedia.episodesIn(in: selectedSeasonID, translation: selectedTranslation) ?? []
    }

    private var playButtonTitle: String {
        isUpdatingPlaybackOptions ? "Готовим..." : "Смотреть"
    }

    private func syncDefaultSelection(for detailedMedia: DetailedMedia) {
        let translationID = selectedTranslationID ?? detailedMedia.translations.keys.first
        selectedTranslationID = translationID

        guard media.isSeries, let translationID else {
            selectedSeasonID = nil
            selectedEpisodeID = nil
            return
        }

        let availableSeasons = detailedMedia.seasons(in: translationID)
        let seasonID = selectedSeasonID.flatMap { availableSeasons?.keys.contains($0) == true ? $0 : nil }
            ?? availableSeasons?.keys.first
        selectedSeasonID = seasonID

        guard let seasonID else {
            selectedEpisodeID = nil
            return
        }

        let availableEpisodes = detailedMedia.episodesIn(in: seasonID, translation: translationID) ?? []
        selectedEpisodeID = selectedEpisodeID.flatMap { episodeID in
            availableEpisodes.contains { $0.id == episodeID } ? episodeID : nil
        } ?? availableEpisodes.first?.id
    }

    private func setTranslation(_ id: Int) async {
        guard let currentMedia = detailedMedia, selectedTranslationID != id else { return }

        selectedTranslationID = id
        streams = nil
        playbackErrorMessage = nil
        isUpdatingPlaybackOptions = true
        defer { isUpdatingPlaybackOptions = false }

        do {
            if media.isSeries {
                let updatedMedia = try await container.mediaRepository.fetchSeriesDetails(for: currentMedia, translation: id)
                detailedMedia = updatedMedia
                selectedSeasonID = nil
                selectedEpisodeID = nil
                syncDefaultSelection(for: updatedMedia)
            }

            await refreshStreams()
        } catch {
            playbackErrorMessage = error.localizedDescription
        }
    }

    private func setSeason(_ id: Int) async {
        selectedSeasonID = id
        selectedEpisodeID = episodes.first?.id
        await refreshStreams()
    }

    private func refreshStreams() async {
        guard let detailedMedia, let translationID = selectedTranslation else { return }

        playbackErrorMessage = nil
        isUpdatingPlaybackOptions = true
        defer { isUpdatingPlaybackOptions = false }

        do {
            streams = try await container.mediaRepository.stream(
                mediaId: detailedMedia.mediaId,
                translationId: translationID,
                season: media.isSeries ? selectedSeasonID : nil,
                episode: media.isSeries ? selectedEpisodeID : nil
            )

            if let qualities = streams?.qualities, qualities.contains(selectedQuality) == false {
                selectedQuality = streams?.bestQualityId ?? qualities.first ?? .unknown
            }
        } catch {
            playbackErrorMessage = error.localizedDescription
        }
    }

    private func startPlayback() async {
        if streams == nil {
            await refreshStreams()
        }

        guard let streamURLString = streams?.stream(selectedQuality) ?? streams?.bestQualityUrl.first,
              let streamURL = ConstantsApi.secureURL(from: streamURLString) else {
            playbackErrorMessage = "Поток недоступен"
            return
        }

        playbackRequest = WatchPlaybackRequest(title: detailedMedia?.title ?? media.title, url: streamURL)
    }
}

private struct WatchPlaybackControls: View {
    let detailedMedia: DetailedMedia
    @Binding var selectedTranslationID: Int
    @Binding var selectedSeasonID: Int
    @Binding var selectedEpisodeID: Int
    @Binding var selectedQuality: Media.Quality
    let availableQualities: [Media.Quality]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if detailedMedia.translations.isEmpty == false {
                WatchSelectionLink(
                    title: "Озвучка",
                    systemImage: "quote.bubble",
                    options: Array(detailedMedia.translations).map { id, title in
                        WatchSelectionOption(id: id, title: title)
                    },
                    selection: $selectedTranslationID
                )
            }

            if let seasons = detailedMedia.seasons(in: selectedTranslationID), seasons.isEmpty == false {
                WatchSelectionLink(
                    title: "Сезон",
                    systemImage: "rectangle.stack",
                    options: Array(seasons).map { id, title in
                        WatchSelectionOption(id: id, title: title)
                    },
                    selection: $selectedSeasonID
                )

                let episodes = detailedMedia.episodesIn(in: selectedSeasonID, translation: selectedTranslationID) ?? []
                if episodes.isEmpty == false {
                    WatchSelectionLink(
                        title: "Серия",
                        systemImage: "play.square",
                        options: episodes.map { episode in
                            WatchSelectionOption(id: episode.id, title: episode.title)
                        },
                        selection: $selectedEpisodeID
                    )
                }
            }

            if availableQualities.isEmpty == false {
                WatchSelectionLink(
                    title: "Качество",
                    systemImage: "rectangle.compress.vertical",
                    options: availableQualities.map { quality in
                        WatchSelectionOption(id: quality, title: quality.rawValue)
                    },
                    selection: $selectedQuality
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WatchSelectionOption<Value: Hashable>: Identifiable {
    let id: Value
    let title: String
}

private struct WatchSelectionLink<Value: Hashable>: View {
    let title: String
    let systemImage: String
    let options: [WatchSelectionOption<Value>]
    @Binding var selection: Value

    var body: some View {
        NavigationLink {
            List {
                ForEach(options) { option in
                    Button {
                        selection = option.id
                    } label: {
                        HStack {
                            Text(option.title)
                                .lineLimit(2)
                            Spacer()
                            if option.id == selection {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(selectedTitle)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var selectedTitle: String {
        options.first { $0.id == selection }?.title ?? "-"
    }
}

private struct WatchPlaybackRequest: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

private struct WatchPlaybackView: View {
    let request: WatchPlaybackRequest
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .navigationTitle(request.title)
            .onAppear {
                let player = AVPlayer(url: request.url)
                self.player = player
                player.play()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
    }
}

private struct WatchInfoGrid: View {
    let info: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(info.prefix(5), id: \.0) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.0)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(item.1)
                        .font(.caption)
                }
            }
        }
    }
}

struct WatchPosterView: View {
    let url: URL?
    @State private var image: CGImage?
    @State private var isLoading = false
    @State private var didFail = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.secondary.opacity(0.18))

            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
            } else if didFail {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url else { return }
        guard image == nil, isLoading == false else { return }

        isLoading = true
        didFail = false

        do {
            let secureURL = ConstantsApi.secureURL(from: url.absoluteString) ?? url
            var request = URLRequest(url: secureURL)
            for (header, value) in ApiConstants.imageHeaders {
                request.setValue(value, forHTTPHeaderField: header)
            }

            let (data, _) = try await RezkaURLSession.shared.data(for: request)
            guard
                let source = CGImageSourceCreateWithData(data as CFData, nil),
                let loadedImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                throw URLError(.cannotDecodeContentData)
            }

            image = loadedImage
        } catch {
            didFail = true
        }

        isLoading = false
    }
}
