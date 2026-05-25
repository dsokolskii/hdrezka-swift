import SwiftUI

struct DetailedMediaItemView: View {
    private static let wideCoverSize = CGSize(width: 300, height: 450)
    private static let heroLeadingPanelWidth: CGFloat = 480
    private static let factsPanelTargetWidth: CGFloat = 1400
    private static let factsPanelPadding: CGFloat = 34
    private static let descriptionCollapsedLineLimit = 5
    private static let playbackStatusIconSize: CGFloat = 24
    private static let playbackLoaderSize: CGFloat = 16
    private static let playbackLoaderScale: CGFloat = 0.48

    private enum DetailScrollAnchor: Hashable {
        case top
    }

    private enum HeroControl: Hashable {
        case bookmark
        case translation
        case season
        case episode
        case play
        case resume
        case quality

        var keepsHeroPinned: Bool {
            switch self {
            case .bookmark, .translation, .season, .episode, .play:
                true
            case .resume, .quality:
                false
            }
        }
    }

    private enum PlaybackStartAction: Equatable {
        case play
        case resume
    }

    private let selectionIcon = "🟢"
    
    @StateObject private var viewModel: DetailedMediaItemViewModel
    
    @StateObject private var bookmarkViewModel: MediaBookmarksViewModel
    
    @State private var isTranslationMenuPresented = false
    @State private var isSeasonsMenuPresented = false
    @State private var skipSeasonsMenuPresented = false
    @State private var isEpisodesMenuPresented = false
    @State private var skipEpisodesMenuPresented = false
    @State private var isQualityMenuPresented = false
    @State private var isPlayerPresented = false
    @State private var playerStartTime: Double = 0
    @State private var didAttemptAutoPlayback = false
    @State private var preparingPlaybackAction: PlaybackStartAction?
    @FocusState private var focusedHeroControl: HeroControl?

    private let autoResumePlaybackPosition: Double?
    private let onMoveLeftToProfileMenu: () -> Void

    init(
        viewModel: DetailedMediaItemViewModel,
        bookmarkViewModel: MediaBookmarksViewModel,
        autoResumePlaybackPosition: Double? = nil,
        onMoveLeftToProfileMenu: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _bookmarkViewModel = StateObject(wrappedValue: bookmarkViewModel)
        self.autoResumePlaybackPosition = autoResumePlaybackPosition
        self.onMoveLeftToProfileMenu = onMoveLeftToProfileMenu
    }
    
    var body: some View {
        ZStack {
            ScreenBackground()

            detailView
                .task {
                    refreshTask()
                }
        }
        .overlay(overlayView)
        .alert(
            "Не удалось загрузить видео",
            isPresented: Binding(
                get: { viewModel.playbackErrorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        viewModel.clearPlaybackError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.clearPlaybackError()
            }
        } message: {
            Text(viewModel.playbackErrorMessage ?? "Попробуйте еще раз.")
        }
    }
    
    private var detailView: some View {
        GeometryReader { proxy in
            let availableWidth = max(0, proxy.size.width - (AppTheme.pagePadding * 2))

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        heroHeader(contentWidth: availableWidth)
                            .id(DetailScrollAnchor.top)

                        mainContent(availableWidth: availableWidth)
                            .padding(.horizontal, AppTheme.pagePadding)
                            .padding(.top, 34)
                            .padding(.bottom, 44)

                        scrollEndAnchor(availableWidth: availableWidth)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .ignoresSafeArea(edges: .top)
                .onChange(of: focusedHeroControl) { _, focusedControl in
                    guard focusedControl?.keepsHeroPinned == true else { return }
                    keepHeroPinned(using: scrollProxy)
                }
            }
        }
        .scrollIndicators(.hidden)
        .fullScreenCover(isPresented: $isPlayerPresented, onDismiss: {
            viewModel.refreshPlaybackState()
        }, content: {
            PlaybackPlayerView(
                viewModel: viewModel,
                isPresented: $isPlayerPresented,
                playerStartTime: $playerStartTime
            )
            .edgesIgnoringSafeArea(.all)
            .transition(.move(edge: .bottom))
        })
    }

    @ViewBuilder
    private func heroHeader(contentWidth: CGFloat) -> some View {
        heroOverlayContent(availableWidth: contentWidth)
            .frame(width: contentWidth, alignment: .leading)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, AppTheme.pagePadding)
    }

    private func heroOverlayContent(availableWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            heroLeadingPanel
            Spacer(minLength: factsPanelPosterSpacing)
            heroFactsPanel(width: factsPanelWidth(for: availableWidth))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var heroLeadingPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            posterView
            heroControlsPanel
        }
        .frame(
            width: Self.heroLeadingPanelWidth,
            alignment: .topLeading
        )
        .frame(
            maxWidth: Self.heroLeadingPanelWidth,
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private var posterView: some View {
        if let coverUrl = viewModel.coverUrl {
            CacheAsyncImage(
                url: coverUrl,
                session: RezkaURLSession.shared,
                requestHeaders: ApiConstants.imageHeaders
            ) { phase in
                phase.view
            }
            .frame(width: Self.wideCoverSize.width, height: Self.wideCoverSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
        } else {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.clear)
                .frame(width: Self.wideCoverSize.width, height: Self.wideCoverSize.height)
                .glassEffect(in: .rect(cornerRadius: 32))
                .overlay {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 58, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.36))
                }
        }
    }

    private var heroControlsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
//                Button {
//                    bookmarkViewModel.toggleBookmark(for: viewModel.media)
//                } label: {
//                    Image(systemName: bookmarkViewModel.isBookmarked(for: viewModel.media) ? "bookmark.fill" : "bookmark")
//                }
//                .buttonStyle(.glass)
//                .buttonBorderShape(.circle)
//                .controlSize(.small)
//                .focused($focusedHeroControl, equals: .bookmark)
                
                Button {
                    startPlaybackFromBeginning()
                } label: {
                    playButtonLabel
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .tint(playButtonTint)
                .focused($focusedHeroControl, equals: .play)
                .onMoveLeftToProfileMenu(true, perform: onMoveLeftToProfileMenu)
                .disabled(viewModel.isPreparingPlayback)
                
                if viewModel.resumePlaybackPosition != nil {
                    Button {
                        continuePlayback()
                    } label: {
                        continuePlaybackLabel
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(continuePlaybackTint)
                    .focused($focusedHeroControl, equals: .resume)
                    .disabled(viewModel.isPreparingPlayback)
                }
            }
            
            if let title = viewModel.currentTranslationTitle {
                Button {
                    isTranslationMenuPresented.toggle()
                } label: {
                    Label(title, systemImage: "quote.bubble")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .focused($focusedHeroControl, equals: .translation)
                .onMoveLeftToProfileMenu(true, perform: onMoveLeftToProfileMenu)
                .alert("Озвучка", isPresented: $isTranslationMenuPresented) {
                    translationMenu
                    cancelButton
                }
            }
            
            if let seasons = viewModel.seasonsInCurrentTranslation, seasons.isEmpty == false {
                HStack(spacing: 12) {
                    Button {
                        if skipSeasonsMenuPresented == false {
                            isSeasonsMenuPresented.toggle()
                        }
                        skipSeasonsMenuPresented = false
                    } label: {
                        Label(viewModel.currentSeasonTitle, systemImage: "square.stack.3d.up")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .focused($focusedHeroControl, equals: .season)
                    .onMoveLeftToProfileMenu(true, perform: onMoveLeftToProfileMenu)
                    .alert("Сезоны", isPresented: $isSeasonsMenuPresented) {
                        seasonsMenu
                        cancelButton
                    }
                    .simultaneousGesture(LongPressGesture().onEnded { _ in
                        if let nextSeasonId = viewModel.nextSeasonId {
                            Task {
                                await selectSeason(id: nextSeasonId)
                            }
                            skipSeasonsMenuPresented = true
                        }
                    })

                    Button {
                        if skipEpisodesMenuPresented == false {
                            isEpisodesMenuPresented.toggle()
                        }
                        skipEpisodesMenuPresented = false
                    } label: {
                        Label(viewModel.currentEpisodeTitle, systemImage: "rectangle.stack")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .focused($focusedHeroControl, equals: .episode)
                    .alert("Эпизоды", isPresented: $isEpisodesMenuPresented) {
                        episodesMenu
                        cancelButton
                    }
                    .simultaneousGesture(LongPressGesture().onEnded { _ in
                        if let nextEpisode = viewModel.nextEpisodeId {
                            Task {
                                await selectEpisode(id: nextEpisode)
                            }
                            skipEpisodesMenuPresented = true
                        }
                    })
                }
            }
            
            if viewModel.streams?.qualities != nil {
                Button {
                    isQualityMenuPresented.toggle()
                } label: {
                    Label(viewModel.historyMedia.quality.rawValue, systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .focused($focusedHeroControl, equals: .quality)
                .onMoveLeftToProfileMenu(true, perform: onMoveLeftToProfileMenu)
                .alert("Качество", isPresented: $isQualityMenuPresented) {
                    qualitiesMenu
                    cancelButton
                }
            }
        }
        .frame(
            width: Self.heroLeadingPanelWidth,
            alignment: .leading
        )
    }

    private var playButtonLabel: some View {
        playbackStatusIcon(isLoading: preparingPlaybackAction == .play)
    }

    private var playButtonTint: Color {
        if focusedHeroControl == .play, preparingPlaybackAction == .play {
            return .black
        }

        return .blue
    }

    private func playbackStatusIcon(isLoading: Bool) -> some View {
        ZStack {
            Image(systemName: "play.fill")
                .opacity(isLoading ? 0 : 1)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(Self.playbackLoaderScale)
                    .frame(
                        width: Self.playbackLoaderSize,
                        height: Self.playbackLoaderSize
                    )
            }
        }
        .frame(
            width: Self.playbackStatusIconSize,
            height: Self.playbackStatusIconSize
        )
        .clipped()
    }

    private func mainContent(availableWidth: CGFloat) -> some View {
        let bodyWidth = AppTheme.pageBodyWidth(for: availableWidth)

        return VStack(alignment: .leading, spacing: 24) {
            SectionHeader(
                eyebrow: viewModel.media.isSeries ? "Сериал" : "Фильм",
                title: displayTitle,
                subtitle: displaySubtitle
            )

            if viewModel.description.isEmpty == false {
                ExpandableDescriptionText(
                    text: viewModel.description,
                    width: bodyWidth,
                    collapsedLineLimit: Self.descriptionCollapsedLineLimit
                )
                    .padding(.top, 8)
            }
        }
        .frame(
            width: bodyWidth,
            alignment: .leading
        )
    }

    private func scrollEndAnchor(availableWidth: CGFloat) -> some View {
        Color.clear
            .frame(width: availableWidth, height: 64)
            .padding(.horizontal, AppTheme.pagePadding)
            .focusable()
            .focusEffectDisabled()
    }

    @ViewBuilder
    private func heroFactsPanel(width: CGFloat) -> some View {
        if viewModel.info.isEmpty == false {
            AppPanel {
                VStack(alignment: .leading, spacing: 18) {
                    Text("О тайтле")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.74))

                    factsGrid(contentWidth: factsPanelContentWidth(for: width))
                }
                .frame(width: factsPanelContentWidth(for: width), alignment: .leading)
            }
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayTitle: String {
        viewModel.title.isEmpty ? viewModel.media.title : viewModel.title
    }

    private var displaySubtitle: String {
        if viewModel.originalTitle.isEmpty == false {
            return viewModel.originalTitle
        }

        return viewModel.media.descriptionShort.isEmpty ? "Выберите озвучку, сезон, эпизод и качество перед запуском." : viewModel.media.descriptionShort
    }

    private func factsGrid(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(viewModel.info.elements.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: factsColumnSpacing) {
                    Text(item.key)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                        .minimumScaleFactor(0.95)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: factsLabelWidth, alignment: .leading)
                        .layoutPriority(0)

                    Text(item.value)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineSpacing(2)
                        .minimumScaleFactor(0.9)
                        .frame(width: factsValueWidth(for: contentWidth), alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                }
            }
        }
    }

    private var factsLabelWidth: CGFloat {
        210
    }

    private var factsColumnSpacing: CGFloat {
        28
    }

    private var factsPanelPosterSpacing: CGFloat {
        72
    }

    private func factsPanelWidth(for availableWidth: CGFloat) -> CGFloat {
        let availableAfterLeadingPanel = availableWidth - Self.heroLeadingPanelWidth - factsPanelPosterSpacing
        return max(0, min(Self.factsPanelTargetWidth, availableAfterLeadingPanel))
    }

    private func factsPanelContentWidth(for panelWidth: CGFloat) -> CGFloat {
        max(0, panelWidth - (Self.factsPanelPadding * 2))
    }

    private func factsValueWidth(for contentWidth: CGFloat) -> CGFloat {
        max(0, contentWidth - factsLabelWidth - factsColumnSpacing)
    }

    private func keepHeroPinned(using scrollProxy: ScrollViewProxy) {
        scrollHeroToTop(using: scrollProxy)

        Task { @MainActor in
            await Task.yield()
            scrollHeroToTop(using: scrollProxy)
        }
    }

    private func scrollHeroToTop(using scrollProxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            scrollProxy.scrollTo(DetailScrollAnchor.top, anchor: .top)
        }
    }
    
    private func selectTranslation(id: Int) async {
        do {
            try await viewModel.setCurrentTranslation(id: id)
        } catch {
            viewModel.presentPlaybackError(error)
        }
    }
    
    private func selectSeason(id: Int) async {
        do {
            try await viewModel.setCurrentSeason(id: id)
        } catch {
            viewModel.presentPlaybackError(error)
        }
    }
    
    private func selectEpisode(id: Int) async {
        do {
            try await viewModel.setCurrentEpisode(id: id)
        } catch {
            viewModel.presentPlaybackError(error)
        }
    }
    
    private func selectQuality(id: Media.Quality) async {
      viewModel.setQuality(id)
    }
    
    @ViewBuilder
    private var translationMenu: some View {
        let items = viewModel.translations
        let currentTitle = viewModel.currentTranslationTitle
        
        ForEach(Array(zip(items.values.indices, items)), id: \.0) { _, translation in
            Button {
                Task {
                    await selectTranslation(id: translation.key)
                }
            } label: {
                if currentTitle == translation.value {
                    Text("\(selectionIcon)  \(translation.value)")
                } else {
                    Text(translation.value)
                }
            }
        }
    }
    
    @ViewBuilder
    private var seasonsMenu: some View {
        if let seasons = viewModel.seasonsInCurrentTranslation {
            let items = seasons.keys.compactMap({ Int($0) })
            let currentTitle = viewModel.currentSeasonTitle
            
            ForEach(items, id: \.self) { item in
                let name = seasons[item] ?? ""
                Button {
                    Task {
                        await selectSeason(id: item)
                    }
                } label: {
                    if currentTitle == name {
                        Text("\(selectionIcon)  \(name)")
                    } else {
                        Text(name)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var episodesMenu: some View {
        if let episodes = viewModel.episodes {
            let items = episodes.map({ $0.id })
            let currentTitle = viewModel.currentEpisodeTitle
            
            ForEach(items, id: \.self) { episodeId in
                Button {
                    Task {
                        await selectEpisode(id: episodeId)
                    }
                } label: {
                    if let episode = episodes.first(where: { $0.id == episodeId }) {
                        if currentTitle == episode.title {
                            Text("\(selectionIcon)  \(episode.title)")
                        } else {
                            Text(episode.title)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var qualitiesMenu: some View {
        if let qualities = viewModel.streams?.qualities {
            let items = qualities.map { $0.rawValue }
            let currentTitle = viewModel.historyMedia.quality.rawValue
            
            ForEach(items, id: \.self) { quality in
                Button {
                    Task {
                        await selectQuality(id: Media.Quality(rawValue: quality) ?? .unknown)
                    }
                } label: {
                    if currentTitle == quality {
                        Text("\(selectionIcon)  \(quality)")
                    } else {
                        Text(quality)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var overlayView: some View {
        switch viewModel.phase {
        case .fetching:
            LoadingPanel()
        case .failure(let error):
            RetryView(text: error.localizedDescription, retryAction: refreshTask)
            
        default: EmptyView()
        }
    }
    
    @ViewBuilder
    private var cancelButton: some View {
        Button(role: .cancel) {} label: {
            Text("Отмена")
        }.padding()
    }

    @ViewBuilder
    private var continuePlaybackLabel: some View {
        HStack(spacing: 8) {
            playbackStatusIcon(isLoading: preparingPlaybackAction == .resume)
            Text(viewModel.resumePlaybackCompactTitle)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
    }

    private var continuePlaybackTint: Color {
        if focusedHeroControl == .resume, preparingPlaybackAction == .resume {
            return .black
        }

        return .blue
    }
    
    private func refreshTask() {
        Task {
            await viewModel.loadDetailedMedia()
            startAutoResumePlaybackIfNeeded()
        }
    }

    private func startAutoResumePlaybackIfNeeded() {
        guard didAttemptAutoPlayback == false else { return }
        guard let requestedStartPosition = autoResumePlaybackPosition else { return }
        guard requestedStartPosition >= 0 else { return }
        guard viewModel.phase.value != nil else { return }

        didAttemptAutoPlayback = true

        Task {
            if await viewModel.preparePlayback() {
                let fallbackPosition = viewModel.resumePlaybackPosition ?? 0
                playerStartTime = requestedStartPosition > 0 ? requestedStartPosition : fallbackPosition
                isPlayerPresented = true
            }
        }
    }

    private func startPlaybackFromBeginning() {
        Task {
            preparingPlaybackAction = .play
            defer { preparingPlaybackAction = nil }

            if await viewModel.preparePlayback() {
                playerStartTime = 0
                viewModel.clearPlaybackProgress()
                isPlayerPresented = true
            }
        }
    }

    private func continuePlayback() {
        Task {
            preparingPlaybackAction = .resume
            defer { preparingPlaybackAction = nil }

            if await viewModel.preparePlayback() {
                playerStartTime = viewModel.resumePlaybackPosition ?? 0
                isPlayerPresented = true
            }
        }
    }
}

private struct ExpandableDescriptionText: View {
    let text: String
    let width: CGFloat
    let collapsedLineLimit: Int

    @FocusState private var isDescriptionFocused: Bool
    @State private var isExpanded = false
    @State private var fullTextHeight: CGFloat = 0
    @State private var collapsedTextHeight: CGFloat = 0

    private static let lineSpacing: CGFloat = 4
    private static let accordionPadding: CGFloat = 14
    private static let cornerRadius: CGFloat = 18

    var body: some View {
        Button {
            guard canToggleExpansion else { return }
            toggleExpansion()
        } label: {
            accordionContent
        }
        .buttonStyle(.glass)
        .focused($isDescriptionFocused)
        .frame(width: width, alignment: .leading)
        .overlay(alignment: .topLeading) {
            measurementViews
                .hidden()
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .onPreferenceChange(FullDescriptionHeightPreferenceKey.self) { height in
            fullTextHeight = height
        }
        .onPreferenceChange(CollapsedDescriptionHeightPreferenceKey.self) { height in
            collapsedTextHeight = height
        }
    }

    private var accordionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            descriptionText(lineLimit: currentLineLimit)

            if canToggleExpansion {
                HStack(spacing: 7) {
                    Text(isExpanded ? "Скрыть" : "Подробнее")
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .font(.caption.weight(.semibold))
                .padding(.top, 2)
            }
        }
        .padding(Self.accordionPadding)
        .frame(width: width, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    private var currentLineLimit: Int? {
        isExpanded ? nil : collapsedLineLimit
    }

    private var textWidth: CGFloat {
        return max(0, width - Self.accordionPadding * 2)
    }

    private var canToggleExpansion: Bool {
        if fullTextHeight > 0, collapsedTextHeight > 0 {
            return isExpanded || fullTextHeight > collapsedTextHeight + 1
        }

        return isExpanded || fullTextHeight > collapsedTextHeight + 1 || estimatedDescriptionExceedsLineLimit
    }

    private var estimatedDescriptionExceedsLineLimit: Bool {
        guard width > 0 else {
            return text.count > 320
        }

        let averageCharacterWidth: CGFloat = 24
        let estimatedCharactersPerLine = max(Int(width / averageCharacterWidth), 1)
        let estimatedCollapsedCapacity = estimatedCharactersPerLine * collapsedLineLimit
        return text.count > min(estimatedCollapsedCapacity, 320)
    }

    private func toggleExpansion() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
    }

    private func descriptionText(lineLimit: Int?) -> some View {
        Text(text)
            .font(.headline.weight(.medium))
            .foregroundStyle(descriptionForegroundColor)
            .multilineTextAlignment(.leading)
            .lineSpacing(Self.lineSpacing)
            .lineLimit(lineLimit)
            .frame(width: textWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var descriptionForegroundColor: Color {
        isDescriptionFocused ? .black.opacity(0.86) : .white.opacity(0.82)
    }

    private var measurementViews: some View {
        ZStack(alignment: .topLeading) {
            descriptionText(lineLimit: nil)
                .background(DescriptionHeightReader(key: FullDescriptionHeightPreferenceKey.self))

            descriptionText(lineLimit: collapsedLineLimit)
                .background(DescriptionHeightReader(key: CollapsedDescriptionHeightPreferenceKey.self))
        }
    }
}

private struct DescriptionHeightReader<Key: PreferenceKey>: View where Key.Value == CGFloat {
    let key: Key.Type

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: key, value: proxy.size.height)
        }
    }
}

private struct FullDescriptionHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CollapsedDescriptionHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct PlaybackPlayerView: View {
    @ObservedObject var viewModel: DetailedMediaItemViewModel
    @Binding var isPresented: Bool
    @Binding var playerStartTime: Double

    @State private var isSwitching = false
    @State private var isSwitchingEpisode = false
    @State private var currentPosition: Double = 0
    @State private var currentDuration: Double = 0
    @State private var didReceiveProgress = false

    var body: some View {
        ZStack {
            PlayerViewController(
                videoURL: URL(string: viewModel.stream),
                initialTime: playerStartTime,
                onProgress: { position, duration in
                    guard isSwitchingEpisode == false else { return }
                    didReceiveProgress = true
                    currentPosition = position
                    currentDuration = duration
                    viewModel.persistPlaybackProgress(position: position, duration: duration)
                },
                onFinish: {
                    currentPosition = 0
                    currentDuration = 0
                    viewModel.persistPlaybackProgress(position: 0, duration: 0, didFinish: true)
                    isPresented = false
                },
                onFailure: { message in
                    viewModel.presentPlaybackError(NSError(
                        domain: "PlayerViewController",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: message]
                    ))
                    isPresented = false
                },
                transportControls: transportControls
            )
        }
        .overlay {
            if isSwitching {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .padding(20)
                    .glassEffect(in: .rect(cornerRadius: 12))
            }
        }
        .onDisappear {
            guard didReceiveProgress else { return }
            viewModel.persistPlaybackProgress(position: currentPosition, duration: currentDuration, force: true)
        }
    }

    private var transportControls: PlayerViewController.TransportControls {
        let selectedTranslationId = viewModel.historyMedia.translation
        let translations = viewModel.translations.map { key, value in
            PlayerViewController.TransportControlTranslation(
                id: key,
                title: value,
                isSelected: key == selectedTranslationId
            )
        }
        let selectedQuality = viewModel.historyMedia.quality
        let qualities = (viewModel.streams?.qualities ?? []).map { quality in
            PlayerViewController.TransportControlQuality(
                id: quality.rawValue,
                title: quality.rawValue,
                isSelected: quality == selectedQuality
            )
        }

        return PlayerViewController.TransportControls(
            mediaTitle: viewModel.title,
            mediaSubtitle: viewModel.media.isSeries ? "\(viewModel.currentSeasonTitle) • \(viewModel.currentEpisodeTitle)" : nil,
            translations: translations,
            qualities: qualities,
            canGoToPreviousEpisode: viewModel.media.isSeries && viewModel.previousEpisodeId != nil,
            canGoToNextEpisode: viewModel.media.isSeries && viewModel.nextEpisodeId != nil,
            onSelectTranslation: { id in
                Task {
                    await switchTranslation(id)
                }
            },
            onSelectQuality: { qualityRawValue in
                Task {
                    await switchQuality(qualityRawValue)
                }
            },
            onPreviousEpisode: {
                Task {
                    await switchEpisode(viewModel.previousEpisodeId)
                }
            },
            onNextEpisode: {
                Task {
                    await switchEpisode(viewModel.nextEpisodeId)
                }
            }
        )
    }

    private func switchEpisode(_ id: Int?) async {
        guard let id else { return }
        isSwitching = true
        isSwitchingEpisode = true
        currentPosition = 0
        currentDuration = 0
        didReceiveProgress = false
        playerStartTime = 0
        defer {
            isSwitchingEpisode = false
            isSwitching = false
        }

        do {
            try await viewModel.setCurrentEpisode(id: id)
        } catch {
            viewModel.presentPlaybackError(error)
        }
    }

    private func switchTranslation(_ id: Int) async {
        isSwitching = true
        defer { isSwitching = false }

        let position = max(0, currentPosition)
        let duration = max(0, currentDuration)
        playerStartTime = position
        viewModel.persistPlaybackProgress(position: position, duration: duration, force: true)

        do {
            try await viewModel.setCurrentTranslation(id: id, resetPlaybackProgress: false)
        } catch {
            viewModel.presentPlaybackError(error)
        }
    }

    private func switchQuality(_ qualityRawValue: String) async {
        guard let quality = Media.Quality(rawValue: qualityRawValue) else { return }
        guard quality != viewModel.historyMedia.quality else { return }

        isSwitching = true
        defer { isSwitching = false }

        let position = max(0, currentPosition)
        let duration = max(0, currentDuration)
        playerStartTime = position
        viewModel.persistPlaybackProgress(position: position, duration: duration, force: true)
        viewModel.setQuality(quality)
    }
}

struct DetailedMediaItemView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DetailedMediaItemView(viewModel: DetailedMediaItemViewModel(media: Media.previewData[1]), bookmarkViewModel: MediaBookmarksViewModel.shared)
        }
    }
}
