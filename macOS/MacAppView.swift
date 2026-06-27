#if os(macOS)
import SwiftUI

struct PlatformAppView: View {
    private enum SidebarDestination: Hashable {
        case home
        case search
        case continueWatching
        case bookmarks
        case settings
        case category(Category)
    }

    @Environment(AppContainer.self) private var container
    @Environment(AuthorizationViewModel.self) private var authorizationViewModel

    @State private var viewModel: ContentViewModel
    @State private var selectedSidebarDestination: SidebarDestination?

    init(viewModel: ContentViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if authorizationViewModel.isAuthenticated {
                authorizedContent
                    .id(authorizationViewModel.sessionID)
            } else {
                MacAuthorizationView()
            }
        }
        .preferredColorScheme(.dark)
        .onFirstAppear {
            Task {
                await ContinueWatchingHistorySync.refreshFromStoredHistory()
            }
        }
    }

    private var authorizedContent: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack {
                ZStack {
                    detailContent
                    overlayView
                }
                .screenBackground()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onFirstAppear {
            syncSidebarSelection()
            refreshTask()
        }
        .onChange(of: viewModel.categories) { _, _ in
            syncSidebarSelection()
        }
    }

    private var sidebar: some View {
        List(selection: $selectedSidebarDestination) {
            Section("Медиатека") {
                Label("Главная", systemImage: "house.fill")
                    .tag(SidebarDestination.home)

                Label("Поиск", systemImage: "magnifyingglass")
                    .tag(SidebarDestination.search)

                Label("Продолжить просмотр", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .tag(SidebarDestination.continueWatching)

                Label("Закладки", systemImage: "bookmark.fill")
                    .tag(SidebarDestination.bookmarks)
            }

            Section("Категории") {
                ForEach(tabCategories, id: \.type) { category in
                    Label(category.name, systemImage: category.type.sidebarSystemImage)
                        .tag(SidebarDestination.category(category.type))
                }
            }

            Section("Система") {
                Label("Настройки", systemImage: "slider.horizontal.3")
                    .tag(SidebarDestination.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 248, ideal: 276)
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
        .safeAreaInset(edge: .bottom) {
            profileFooter
        }
    }

    private var profileFooter: some View {
        Menu {
            Button {
                selectedSidebarDestination = .settings
            } label: {
                Label("Настройки", systemImage: "slider.horizontal.3")
            }

            Button(role: .destructive) {
                authorizationViewModel.logout()
            } label: {
                Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            HStack(spacing: 12) {
                ProfileAvatarView(userProfile: viewModel.userProfile, size: 34)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profileDisplayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(ConstantsApi.host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSidebarDestination {
        case .home:
            MacHomeView(viewModel: container.makeMediaHomeViewModel())
                .id(SidebarDestination.home)
        case .search:
            MacMediaSearchView(viewModel: container.makeSearchViewModel())
                .id(SidebarDestination.search)
        case .continueWatching:
            MacContinueWatchingView()
                .id(SidebarDestination.continueWatching)
        case .bookmarks:
            MediaBookmarksView()
                .id(SidebarDestination.bookmarks)
        case .settings:
            MacSettingsView(onMirrorChanged: handleMirrorChanged)
                .id(SidebarDestination.settings)
        case .category(let type):
            if let category = tabCategories.first(where: { $0.type == type }) {
                MacMediaContentView(
                    viewModel: container.makeMediaContentViewModel(
                        category: category.type,
                        filters: category.filters,
                        genres: category.genres
                    ),
                    pageTitle: category.name
                )
                .id(type)
            } else {
                EmptyPlaceholderView(text: "Категория недоступна", image: Image(systemName: "square.stack"))
            }
        case nil:
            EmptyPlaceholderView(text: "Каталог загружается", image: Image(systemName: "sparkles.tv"))
        }
    }

    private var tabCategories: [CategoryList] {
        viewModel.categories.filter { $0.type != .search && $0.type != .general }
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

    private var profileDisplayName: String {
        let normalizedName = viewModel.userProfile?.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if normalizedName.isEmpty || normalizedName == "Профиль" {
            return authorizationViewModel.fallbackProfileName
        }

        return normalizedName
    }

    private func syncSidebarSelection() {
        let validCategoryTypes = Set(tabCategories.map(\.type))

        switch selectedSidebarDestination {
        case .category(let type) where validCategoryTypes.contains(type):
            return
        case .home, .search, .continueWatching, .bookmarks, .settings:
            return
        default:
            selectedSidebarDestination = .home
        }
    }

    private func refreshTask() {
        Task {
            await viewModel.load()
        }
    }

    private func handleMirrorChanged() {
        selectedSidebarDestination = .home
        refreshTask()
    }
}

private struct MacAuthorizationView: View {
    @Environment(AuthorizationViewModel.self) private var authorizationViewModel

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            ScreenBackground()

            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "tv.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(ConstantsApi.host)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Авторизация нужна, чтобы открыть каталог и продолжить просмотр на Mac.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 16) {
                    TextField("Email", text: $email)
                        .autocorrectionDisabled()
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    SecureField("Пароль", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    if let errorMessage = authorizationViewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.9))
                    }

                    Button(action: login) {
                        HStack {
                            if authorizationViewModel.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            Text(authorizationViewModel.isLoading ? "Входим..." : "Войти")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(authorizationViewModel.isLoading)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .frame(maxWidth: 420)
            }
            .padding(32)
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

private struct MacSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthorizationViewModel.self) private var authorizationViewModel

    let onMirrorChanged: () -> Void

    @State private var mirror = ConstantsApi.host
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeader(
                    eyebrow: "Система",
                    title: "Настройки",
                    subtitle: "Нативная панель для зеркала и быстрой смены аккаунта."
                )

                GroupBox("Зеркало") {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField(ConstantsApi.defaultHost, text: $mirror)
                            .autocorrectionDisabled()
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        HStack(spacing: 12) {
                            Button("Сохранить", action: saveMirror)
                                .buttonStyle(.borderedProminent)

                            Button("Сбросить", action: resetMirror)
                                .buttonStyle(.bordered)
                        }

                        Text("По умолчанию: \(ConstantsApi.defaultHost)")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Аккаунт") {
                    Button(role: .destructive) {
                        authorizationViewModel.logout()
                        dismiss()
                    } label: {
                        Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 32)
        }
        .screenBackground()
        .navigationTitle("Настройки")
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
