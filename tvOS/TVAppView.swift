#if os(tvOS)
import SwiftUI

struct PlatformAppView: View {
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

    private enum ProfileMenuFocusTarget: Hashable {
        case profileButton
        case search
        case home
        case bookmarks
        case settings
    }

    @Environment(AppContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AuthorizationViewModel.self) private var authorizationViewModel

    @State private var viewModel: ContentViewModel
    @State private var selectedCategory: CategoryList?
    @State private var pendingTopShelfRequest: TopShelfContinueRequest?
    @State private var presentedTopShelfRequest: TopShelfContinueRequest?
    @State private var isProfileMenuPresented = false
    @State private var isSearchPresented = false
    @State private var isSettingsPresented = false
    @State private var navigationRootID = UUID()
    @FocusState private var focusedProfileMenuItem: ProfileMenuFocusTarget?

    init(viewModel: ContentViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if authorizationViewModel.isAuthenticated {
                authorizedContent
                    .id(authorizationViewModel.sessionID)
            } else {
                TVAuthorizationView()
            }
        }
        .preferredColorScheme(.dark)
        .onFirstAppear {
            Task {
                await ContinueWatchingHistorySync.refreshFromStoredHistory()
                notifyTopShelfContentChanged()
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

    private var authorizedContent: some View {
        ZStack {
            NavigationStack {
                ZStack {
                    TabView {
                        ForEach(tabCategories, id: \.type) { category in
                            MediaContentView(
                                viewModel: container.makeMediaContentViewModel(
                                    category: category.type,
                                    filters: category.filters,
                                    genres: category.genres
                                ),
                                onMoveLeftToProfileMenu: focusProfileMenuButton
                            )
                            .tabItem {
                                Text(category.name)
                            }
                        }
                    }
                    .allowsHitTesting(isBlockingOverlayPresented == false)

                    overlayView
                }
                .onChange(of: horizontalSizeClass) { _, _ in
                }
                .screenBackground()
                .onFirstAppear {
                    selectedCategory = tabCategories.first
                    refreshTask()
                    notifyTopShelfContentChanged()
                }
                .navigationDestination(isPresented: $isSearchPresented) {
                    MediaSearchView(
                        viewModel: container.makeSearchViewModel(),
                        onMoveLeftToProfileMenu: focusProfileMenuButton
                    )
                }
                .navigationDestination(isPresented: $isSettingsPresented) {
                    TVSettingsView(onMirrorChanged: handleMirrorChanged)
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

    private var tabCategories: [CategoryList] {
        viewModel.categories.filter { $0.type != .search }
    }

    @ViewBuilder
    private var overlayView: some View {
        switch viewModel.phase {
        case .fetching:
            LoadingPanel()
        case .fetchingNextPage:
            EmptyView()
        case .success(let navigation) where navigation.categories.isEmpty:
            EmptyPlaceholderView(text: "no categories", image: nil)
        case .failure(let error):
            RetryView(text: error.localizedDescription, retryAction: refreshTask)
        default:
            EmptyView()
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

    private var profileMenuButton: some View {
        Button {
            if isProfileMenuPresented {
                closeProfileMenu()
            } else {
                openProfileMenu()
            }
        } label: {
            ProfileAvatarView(
                userProfile: viewModel.userProfile,
                size: Self.profileMenuAvatarImageSize
            )
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
    }

    private var profileMenuOverlay: some View {
        VStack(alignment: .leading, spacing: Self.profileMenuContentSpacing) {
            HStack(spacing: Self.profileMenuHeaderSpacing) {
                Color.clear
                    .frame(width: Self.profileMenuAvatarSlotSize, height: Self.profileMenuAvatarSlotSize)

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
                    focusedProfileMenuItem = nil
                    isSettingsPresented = false
                    isSearchPresented = true
                }

                profileMenuItem(title: "Главная", systemImage: "house.fill", focusTarget: .home) {
                    navigateHome()
                }

                profileMenuItem(title: "Закладки", systemImage: "bookmark", focusTarget: .bookmarks, isEnabled: false) {
                }

                profileMenuItem(title: "Настройки", systemImage: "gearshape", focusTarget: .settings) {
                    closeProfileMenu()
                    focusedProfileMenuItem = nil
                    isSearchPresented = false
                    isSettingsPresented = true
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
        focusTarget: ProfileMenuFocusTarget,
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

    private func refreshTask() {
        Task {
            await viewModel.load()
        }
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
        focusedProfileMenuItem = .profileButton
    }

    private func navigateHome() {
        closeProfileMenu()
        isSearchPresented = false
        isSettingsPresented = false
        navigationRootID = UUID()
    }

    private func handleMirrorChanged() {
        navigationRootID = UUID()
        refreshTask()
        notifyTopShelfContentChanged()
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

private struct TVAuthorizationView: View {
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

                    Button(action: login) {
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

    private func login() {
        Task {
            await authorizationViewModel.login(email: email, password: password)
            if authorizationViewModel.isAuthenticated {
                password = ""
            }
        }
    }
}

private struct TVSettingsView: View {
    private enum FocusTarget: Hashable {
        case mirror
        case save
        case reset
        case logout
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthorizationViewModel.self) private var authorizationViewModel

    let onMirrorChanged: () -> Void

    @State private var mirror = ConstantsApi.host
    @State private var statusMessage: String?
    @FocusState private var focusedTarget: FocusTarget?

    var body: some View {
        ZStack {
            ScreenBackground()

            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Зеркало")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    HStack(spacing: 14) {
                        TextField(
                            "",
                            text: $mirror,
                            prompt: Text(ConstantsApi.defaultHost).foregroundStyle(.white.opacity(0.5))
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .focused($focusedTarget, equals: .mirror)

                        Button {
                            saveMirror()
                        } label: {
                            Label("Сохранить", systemImage: "checkmark")
                                .frame(minWidth: 190)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .focused($focusedTarget, equals: .save)

                        Button {
                            resetMirror()
                        } label: {
                            Label("Сбросить", systemImage: "arrow.counterclockwise")
                                .frame(minWidth: 170)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .focused($focusedTarget, equals: .reset)
                    }

                    Text("По умолчанию: \(ConstantsApi.defaultHost)")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.64))

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
                .padding(28)
                .glassEffect(in: .rect(cornerRadius: 28))

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
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 54)
        }
        .navigationTitle("Настройки")
        .onExitCommand {
            dismiss()
        }
        .onAppear {
            focusedTarget = .mirror
        }
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
#endif
