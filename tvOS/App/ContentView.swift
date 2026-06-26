import SwiftUI
import TVServices

private enum AppFocusTarget: Hashable {
    case profileButton
    case search
    case home
    case bookmarks
    case settings
}

private enum ActiveTopLevelScreen {
    case home
    case catalog
    case search
    case bookmarks
    case settings
}

struct ContentView: View {
    private static let profileButtonOffset = CGSize(width: -20, height: -12)
    private static let profileMenuPadding: CGFloat = 18
    private static let profileMenuHeaderPadding: CGFloat = 10
    private static let profileMenuHeaderSpacing: CGFloat = 14
    private static let profileMenuContentSpacing: CGFloat = 36
    private static let profileMenuAvatarSlotSize: CGFloat = 56
    private static let profileMenuAvatarImageSize: CGFloat = 40
    private static var profileMenuOffset: CGSize {
        let headerAvatarOrigin = profileMenuPadding + profileMenuHeaderPadding

        return CGSize(width: -headerAvatarOrigin, height: -headerAvatarOrigin)
    }

    private struct TopShelfContinueRequest: Identifiable {
        let id = UUID()
        let media: Media
        let playbackPosition: Double
    }

    private enum PrimaryTab: Hashable, Identifiable {
        case home
        case category(CategoryList)

        var id: String {
            switch self {
            case .home:
                "home"
            case .category(let category):
                "category-\(category.type.rawValue)-\(category.id.uuidString)"
            }
        }

        var title: String {
            switch self {
            case .home:
                "Главная"
            case .category(let category):
                category.name
            }
        }
    }

    @Environment(AppContainer.self) private var container
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(AuthorizationViewModel.self) private var authorizationViewModel
    @State private var viewModel: ContentViewModel

    @State var selectedCategory: CategoryList?
    @State private var pendingTopShelfRequest: TopShelfContinueRequest?
    @State private var presentedTopShelfRequest: TopShelfContinueRequest?
    @State private var isProfileMenuPresented = false
    @State private var isSearchPresented = false
    @State private var isBookmarksPresented = false
    @State private var isSettingsPresented = false
    @State private var navigationRootID = UUID()
    @State private var selectedPrimaryTab: PrimaryTab = .home
    @State private var homeFocusRequest = 0
    @State private var catalogFocusRequest = 0
    @State private var searchFocusRequest = 0
    @State private var bookmarksFocusRequest = 0
    @State private var settingsFocusRequest = 0
    @FocusState private var focusedProfileMenuItem: AppFocusTarget?

    init(viewModel: ContentViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if authorizationViewModel.isAuthenticated {
                authorizedContent
                    .id(authorizationViewModel.sessionID)
            } else {
                AuthorizationView()
            }
        }
        .preferredColorScheme(.dark)
        .onFirstAppear {
            Task {
                await ContinueWatchingHistorySync.refreshFromStoredHistory()
                TVTopShelfContentProvider.topShelfContentDidChange()
            }
        }
        .onOpenURL { url in
            guard let request = topShelfRequest(from: url) else { return }
            pendingTopShelfRequest = request
            presentPendingTopShelfMediaIfPossible()
        }
        .onChange(of: authorizationViewModel.isAuthenticated) { _, _ in
            presentPendingTopShelfMediaIfPossible()
        }
        .fullScreenCover(item: $presentedTopShelfRequest) { request in
            DetailedMediaItemView(
                viewModel: DetailedMediaItemViewModel(media: request.media),
                bookmarkViewModel: MediaBookmarksViewModel.shared,
                autoResumePlaybackPosition: request.playbackPosition
            )
        }
        .toolbar {
            if authorizationViewModel.isAuthenticated {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Logout", role: .destructive) {
                        authorizationViewModel.logout()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var authorizedContent: some View {
        ZStack {
            NavigationStack {
                ZStack {
                    TabView(selection: $selectedPrimaryTab) {
                        ForEach(primaryTabs) { tab in
                            switch tab {
                            case .home:
                                MediaHomeView(
                                    viewModel: MediaHomeViewModel(
                                        mediaRepository: container.mediaRepository
                                    ),
                                    onMoveLeftToProfileMenu: focusProfileMenuButton,
                                    focusRequest: homeFocusRequest
                                )
                                .tag(tab)
                                .tabItem {
                                    Text(tab.title)
                                }
                            case .category(let category):
                                MediaContentView(
                                    viewModel: container.makeMediaContentViewModel(
                                        category: category.type,
                                        filters: category.filters,
                                        genres: category.genres
                                    ),
                                    onMoveLeftToProfileMenu: focusProfileMenuButton,
                                    focusRequest: catalogFocusRequest
                                )
                                .tag(tab)
                                .tabItem {
                                    Text(tab.title)
                                }
                            }
                        }
                    }
                    .allowsHitTesting(isBlockingOverlayPresented == false)

                    overlayView
                }
                .onChange(of: horizontalSizeClass) { _, newValue in
                    print("debug ContentView onChange \(String(describing: horizontalSizeClass)) -> \(String(describing: newValue))")
                }
                .screenBackground()
                .onFirstAppear {
                    selectedCategory = tabCategories.first
                    refreshTask()
                    TVTopShelfContentProvider.topShelfContentDidChange()
                }
                .navigationDestination(isPresented: $isSearchPresented) {
                    MediaSearchView(
                        viewModel: container.makeSearchViewModel(),
                        onMoveLeftToProfileMenu: focusProfileMenuButton,
                        focusRequest: searchFocusRequest
                    )
                }
                .navigationDestination(isPresented: $isBookmarksPresented) {
                    MediaBookmarksView(
                        onMoveLeftToProfileMenu: focusProfileMenuButton,
                        focusRequest: bookmarksFocusRequest
                    )
                }
                .navigationDestination(isPresented: $isSettingsPresented) {
                    SettingsView(
                        onMoveLeftToProfileMenu: focusProfileMenuButton,
                        focusRequest: settingsFocusRequest,
                        onMirrorChanged: handleMirrorChanged
                    )
                }
            }
            .id(navigationRootID)

            profileFloatingControl
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if isProfileMenuPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture(perform: closeProfileMenu)
                    .onExitCommand(perform: closeProfileMenu)
            }
        }
        .onChange(of: isProfileMenuPresented) { _, isPresented in
            guard isPresented else { return }

            Task { @MainActor in
                focusedProfileMenuItem = .search
            }
        }
        .onChange(of: focusedProfileMenuItem) { _, newTarget in
            guard isProfileMenuPresented, newTarget == nil else { return }

            closeProfileMenu()
        }
    }

    private var profileFloatingControl: some View {
        ZStack(alignment: .topLeading) {
            if isProfileMenuPresented {
                profileMenuOverlay
                    .offset(Self.profileMenuOffset)
                    .transition(.scale(scale: 0.82, anchor: .topLeading).combined(with: .opacity))
            }

            profileMenuButton
                .zIndex(1)
        }
        .offset(Self.profileButtonOffset)
        .zIndex(2)
    }

    private var tabCategories: [CategoryList] {
        viewModel.categories.filter { $0.type != .search }
    }

    private var primaryTabs: [PrimaryTab] {
        [.home] + tabCategories.map(PrimaryTab.category)
    }

    @ViewBuilder
    private var overlayView: some View {
        switch viewModel.phase {
        case .fetching:
            progress
        case .fetchingNextPage:
            EmptyView()
        case .success(let navigation) where navigation.categories.isEmpty:
            EmptyPlaceholderView(text: "no categories", image: nil)
        case .failure(let error):
            RetryView(text: error.localizedDescription, retryAction: refreshTask)
        default: EmptyView()
        }
    }
    
    @ViewBuilder
    private var progress: some View {
        LoadingPanel()
    }

    private func refreshTask() {
        Task {
            await viewModel.load()
        }
    }

    private var profileMenuButton: some View {
        Button {
            if isProfileMenuPresented {
                closeProfileMenu()
            } else {
                openProfileMenu()
            }
        } label: {
            profileAvatar(size: Self.profileMenuAvatarImageSize)
                .frame(
                    width: Self.profileMenuAvatarSlotSize,
                    height: Self.profileMenuAvatarSlotSize
                )
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .frame(width: Self.profileMenuAvatarSlotSize, height: Self.profileMenuAvatarSlotSize)
        .disabled(isBlockingOverlayPresented)
        .focused($focusedProfileMenuItem, equals: .profileButton)
        .onMoveCommand { direction in
            guard isProfileMenuPresented == false, direction == .right else { return }
            moveFocusIntoActiveScreen()
        }
    }

    private var profileMenuOverlay: some View {
        VStack(alignment: .leading, spacing: Self.profileMenuContentSpacing) {
            HStack(spacing: Self.profileMenuHeaderSpacing) {
                Color.clear
                    .frame(
                        width: Self.profileMenuAvatarSlotSize,
                        height: Self.profileMenuAvatarSlotSize
                    )

                Text(profileDisplayName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            .padding(.horizontal, Self.profileMenuHeaderPadding)
            .padding(.top, Self.profileMenuHeaderPadding)

            VStack(alignment: .leading, spacing: 14) {
                profileMenuItem(title: "Поиск", systemImage: "magnifyingglass", focusTarget: .search) {
                    closeProfileMenu()
                    focusedProfileMenuItem = .profileButton
                    isBookmarksPresented = false
                    isSettingsPresented = false
                    isSearchPresented = true
                }

                profileMenuItem(title: "Главная", systemImage: "house.fill", focusTarget: .home) {
                    navigateHome()
                }

                profileMenuItem(title: "Закладки", systemImage: "bookmark", focusTarget: .bookmarks) {
                    closeProfileMenu()
                    focusedProfileMenuItem = .profileButton
                    isSearchPresented = false
                    isSettingsPresented = false
                    isBookmarksPresented = true
                }

                profileMenuItem(title: "Настройки", systemImage: "gearshape", focusTarget: .settings) {
                    navigateToSettings()
                }
            }
            .focusSection()
        }
        .padding(Self.profileMenuPadding)
        .frame(width: 360, alignment: .topLeading)
        .glassEffect(in: .rect(cornerRadius: 30))
    }

    private func profileMenuItem(
        title: String,
        systemImage: String,
        focusTarget: AppFocusTarget,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 24))
        .disabled(isEnabled == false)
        .focused($focusedProfileMenuItem, equals: focusTarget)
    }

    private var profileDisplayName: String {
        let normalizedName = viewModel.userProfile?.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if normalizedName.isEmpty || normalizedName == "Профиль" {
            return authorizationViewModel.fallbackProfileName
        }

        return normalizedName
    }

    @ViewBuilder
    private func profileAvatar(size: CGFloat) -> some View {
        if let avatarURL = viewModel.userProfile?.avatarURL {
            CacheAsyncImage(
                url: avatarURL,
                targetSize: CGSize(width: size * 2, height: size * 2),
                requestHeaders: [ApiConstants.userAgentKey: ApiConstants.userAgent]
            ) { phase in
                switch phase {
                case .success(let image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                default:
                    fallbackProfileAvatar(size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            fallbackProfileAvatar(size: size)
        }
    }

    private func fallbackProfileAvatar(size: CGFloat) -> some View {
        Image(systemName: "person.fill")
            .font(.system(size: size * 0.62, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
    }

    private func openProfileMenu() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isProfileMenuPresented = true
        }
    }

    private func closeProfileMenu() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            isProfileMenuPresented = false
        }
    }

    private func focusProfileMenuButton() {
        guard isBlockingOverlayPresented == false else { return }

        Task { @MainActor in
            focusedProfileMenuItem = .profileButton
        }
    }

    private func navigateToSettings() {
        closeProfileMenu()
        focusedProfileMenuItem = .profileButton
        isSearchPresented = false
        isBookmarksPresented = false
        isSettingsPresented = true
    }

    private func navigateHome() {
        closeProfileMenu()
        focusedProfileMenuItem = .profileButton
        isSearchPresented = false
        isBookmarksPresented = false
        isSettingsPresented = false
        navigationRootID = UUID()
        selectedPrimaryTab = .home
    }

    private func handleMirrorChanged() {
        navigationRootID = UUID()
        refreshTask()
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    private var isBlockingOverlayPresented: Bool {
        switch viewModel.phase {
        case .fetching:
            true
        case .success(let navigation):
            navigation.categories.isEmpty
        case .failure:
            true
        case .fetchingNextPage:
            false
        }
    }

    private var activeTopLevelScreen: ActiveTopLevelScreen {
        if isSettingsPresented {
            return .settings
        }

        if isBookmarksPresented {
            return .bookmarks
        }

        if isSearchPresented {
            return .search
        }

        switch selectedPrimaryTab {
        case .home:
            return .home
        case .category:
            return .catalog
        }
    }

    private func moveFocusIntoActiveScreen() {
        switch activeTopLevelScreen {
        case .home:
            homeFocusRequest += 1
        case .catalog:
            catalogFocusRequest += 1
        case .search:
            searchFocusRequest += 1
        case .bookmarks:
            bookmarksFocusRequest += 1
        case .settings:
            settingsFocusRequest += 1
        }
    }

    private func presentPendingTopShelfMediaIfPossible() {
        guard authorizationViewModel.isAuthenticated else { return }
        guard let request = pendingTopShelfRequest else { return }
        pendingTopShelfRequest = nil
        presentedTopShelfRequest = request
    }

    private func topShelfRequest(from url: URL) -> TopShelfContinueRequest? {
        guard url.scheme == "rezkaplayer", url.host == "continue" else {
            return nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let mediaURL = query["media_url"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard mediaURL.isEmpty == false else { return nil }
        let playbackPosition = Double(query["playback_position"] ?? "") ?? 0

        let title = query["title"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (query["title"] ?? "")
            : "Продолжить просмотр"
        let coverURL = query["cover_url"] ?? ""
        let isSeries = query["is_series"] == "1"
        let seasonTitle = query["season_title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let episodeTitle = query["episode_title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let seriesInfo: String? = {
            guard isSeries else { return nil }
            if seasonTitle.isEmpty && episodeTitle.isEmpty {
                return "Сериал"
            }
            return [seasonTitle, episodeTitle].filter { $0.isEmpty == false }.joined(separator: " • ")
        }()

        return TopShelfContinueRequest(
            media: Media(
                title: title,
                url: mediaURL,
                descriptionShort: "",
                description: nil,
                coverUrl: coverURL,
                seriesInfo: seriesInfo,
                category: isSeries ? .series : .films,
                quality: .unknown
            ),
            playbackPosition: max(0, playbackPosition)
        )
    }
}

extension View {
    @ViewBuilder
    func onMoveLeftToProfileMenu(_ isEnabled: Bool, perform action: @escaping () -> Void) -> some View {
        if isEnabled {
            onMoveCommand { direction in
                guard direction == .left else { return }

                action()
            }
        } else {
            self
        }
    }
}

private struct AuthorizationView: View {
    @Environment(AuthorizationViewModel.self) private var authorizationViewModel

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            ScreenBackground()

            VStack(spacing: 26) {
                VStack(spacing: 10) {
                    Image(systemName: "tv.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(24)
                        .glassEffect(in: .rect(cornerRadius: 28))

                    Text(ConstantsApi.host)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Авторизация требуется для доступа к каталогу")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    TextField(
                        "",
                        text: $email,
                        prompt: Text("Email").foregroundStyle(.white.opacity(0.58))
                    )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textContentType(.username)

                    SecureField(
                        "",
                        text: $password,
                        prompt: Text("Пароль").foregroundStyle(.white.opacity(0.58))
                    )
                        .textContentType(.password)

                    if let errorMessage = authorizationViewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task {
                            await authorizationViewModel.login(email: email, password: password)
                            if authorizationViewModel.isAuthenticated {
                                password = ""
                            }
                        }
                    } label: {
                        HStack {
                            if authorizationViewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text(authorizationViewModel.isLoading ? "Входим..." : "Войти")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(authorizationViewModel.isLoading)
                }
                .padding(24)
                .glassEffect(in: .rect(cornerRadius: 28))
                .frame(maxWidth: 420)
            }
            .padding(24)
        }
    }
}

private struct SettingsView: View {
    private enum FocusTarget: Hashable {
        case editMirror
        case reset
        case logout
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthorizationViewModel.self) private var authorizationViewModel

    let onMoveLeftToProfileMenu: () -> Void
    let focusRequest: Int
    let onMirrorChanged: () -> Void

    @State private var mirror = ConstantsApi.host
    @State private var mirrorDraft = ConstantsApi.host
    @State private var isMirrorEditorPresented = false
    @State private var statusMessage: String?
    @FocusState private var focusedTarget: FocusTarget?

    var body: some View {
        ZStack {
            ScreenBackground()

            VStack(alignment: .leading, spacing: 28) {
                settingsCard

                Button(role: .destructive) {
                    authorizationViewModel.logout()
                    dismiss()
                } label: {
                    Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(minWidth: 280)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .focused($focusedTarget, equals: .logout)
                .onMoveLeftToProfileMenu(true, perform: onMoveLeftToProfileMenu)
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 54)
        }
        .navigationTitle("Настройки")
        .onAppear {
            Task { @MainActor in
                focusedTarget = .editMirror
            }
        }
        .onChange(of: focusRequest) { _, _ in
            focusedTarget = .editMirror
        }
        .alert("Зеркало", isPresented: $isMirrorEditorPresented) {
            TextField("Домен зеркала", text: $mirrorDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)

            Button("Сохранить") {
                saveMirrorDraft()
                focusedTarget = .editMirror
            }

            Button("Отмена", role: .cancel) {
                mirrorDraft = mirror
                focusedTarget = .editMirror
            }
        } message: {
            Text("Введите домен зеркала HDRezka.")
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Зеркало")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 10) {
                Text("Текущее зеркало")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.58))

                Text(mirror)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            HStack(alignment: .center, spacing: 18) {
                Button {
                    mirrorDraft = mirror
                    isMirrorEditorPresented = true
                } label: {
                    Label("Изменить зеркало", systemImage: "pencil")
                        .frame(minWidth: 320, alignment: .leading)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .focused($focusedTarget, equals: .editMirror)
                .onMoveLeftToProfileMenu(true, perform: onMoveLeftToProfileMenu)

                Button {
                    resetMirror()
                } label: {
                    Label("Сбросить", systemImage: "arrow.counterclockwise")
                        .frame(minWidth: 240, alignment: .leading)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .focused($focusedTarget, equals: .reset)
            }
            .focusSection()

            Text("По умолчанию: \(ConstantsApi.defaultHost)")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.64))

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .frame(width: 1040, alignment: .leading)
        .padding(28)
        .glassEffect(in: .rect(cornerRadius: 28))
    }

    private func saveMirror() {
        guard let normalizedHost = ConstantsApi.normalizedHost(from: mirror) else {
            statusMessage = "Введите корректный домен зеркала"
            return
        }

        let previousHost = ConstantsApi.host
        ConstantsApi.setHost(normalizedHost)
        mirror = normalizedHost

        if previousHost != normalizedHost {
            statusMessage = "Зеркало сохранено"
            onMirrorChanged()
        } else {
            statusMessage = "Это зеркало уже используется"
        }
    }

    private func saveMirrorDraft() {
        mirror = mirrorDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        saveMirror()
    }

    private func resetMirror() {
        let previousHost = ConstantsApi.host
        ConstantsApi.resetHost()
        mirror = ConstantsApi.defaultHost

        if previousHost != ConstantsApi.defaultHost {
            statusMessage = "Зеркало сброшено"
            onMirrorChanged()
        } else {
            statusMessage = "Используется зеркало по умолчанию"
        }
    }
}

enum AppTheme {
    static let backgroundTop = Color(red: 0.12, green: 0.13, blue: 0.16)
    static let backgroundBottom = Color(red: 0.015, green: 0.017, blue: 0.022)
    static let panel = Color.white.opacity(0.075)
    static let panelStrong = Color.white.opacity(0.12)
    static let pill = Color.white.opacity(0.11)
    static let pillActive = Color.white.opacity(0.88)
    static let buttonSecondary = Color(red: 0.22, green: 0.23, blue: 0.25)
    static let buttonSecondaryActive = Color.white.opacity(0.9)
    static let hairline = Color.white.opacity(0.16)
    static let hairlineStrong = Color.white.opacity(0.28)
    static let mutedText = Color.white.opacity(0.68)
    static let accent = Color(red: 0.02, green: 0.45, blue: 1.0)

    static var pagePadding: CGFloat {
        72
    }

    static var pageBodyTrailingReserve: CGFloat {
        pagePadding
    }

    static func pageBodyWidth(for availableWidth: CGFloat) -> CGFloat {
        max(0, availableWidth - pageBodyTrailingReserve)
    }

    static var gridSpacing: CGFloat {
        42
    }

    static var cardCorner: CGFloat {
        28
    }
}

struct ScreenBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [AppTheme.accent.opacity(0.34), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 620
            )

            RadialGradient(
                colors: [Color(red: 0.86, green: 0.18, blue: 0.06).opacity(0.22), .clear],
                center: .bottomLeading,
                startRadius: 60,
                endRadius: 560
            )
        }
        .ignoresSafeArea()
    }
}

struct SectionHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)

            if let subtitle, subtitle.isEmpty == false {
                Text(subtitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleSize: CGFloat {
        54
    }
}

struct LoadingPanel: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .tint(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .glassEffect(in: .rect(cornerRadius: 22))
    }
}

struct AppPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(panelPadding)
            .glassEffect(in: .rect(cornerRadius: 30))
    }

    private var panelPadding: CGFloat {
        34
    }
}

extension View {
    func screenBackground() -> some View {
        background(ScreenBackground())
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let container = AppContainer.live
        ContentView(viewModel: container.makeContentViewModel())
            .environment(container)
            .environment(AuthorizationViewModel(service: container.authorizationService))
    }
}
