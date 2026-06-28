#if os(macOS)
import AppKit
import SwiftUI

struct PlatformAppView: View {
    private enum SidebarDestination: Hashable {
        case home
        case search
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
        HStack(spacing: 0) {
            sidebar

            Divider()
                .overlay(AppTheme.hairline.opacity(0.4))

            NavigationStack {
                ZStack {
                    detailContent
                    overlayView
                }
                .screenBackground()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 960, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .background(MacWindowConfigurator())
        .ignoresSafeArea(.container, edges: .top)
        .onFirstAppear {
            syncSidebarSelection()
            refreshTask()
        }
        .onChange(of: viewModel.categories) { _, _ in
            syncSidebarSelection()
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 22) {
                    sectionHeader("Медиатека")

                    VStack(spacing: 4) {
                        sidebarButton(.home, title: "Главная", systemImage: "house.fill")
                        sidebarButton(.search, title: "Поиск", systemImage: "magnifyingglass")
                        sidebarButton(.bookmarks, title: "Закладки", systemImage: "bookmark.fill")
                    }
                }

                VStack(alignment: .leading, spacing: 22) {
                    sectionHeader("Категории")

                    VStack(spacing: 4) {
                        ForEach(tabCategories, id: \.type) { category in
                            sidebarButton(
                                .category(category.type),
                                title: category.name,
                                systemImage: category.type.sidebarSystemImage
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 22) {
                    sectionHeader("Система")

                    VStack(spacing: 4) {
                        sidebarButton(.settings, title: "Настройки", systemImage: "slider.horizontal.3")
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 54)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(.ultraThinMaterial)
        .safeAreaInset(edge: .bottom) {
            profileFooter
        }
        .frame(width: 232)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.6)
            .foregroundStyle(.secondary)
            .padding(.leading, 12)
    }

    private func sidebarButton(
        _ destination: SidebarDestination,
        title: String,
        systemImage: String
    ) -> some View {
        let isSelected = selectedSidebarDestination == destination

        return Button {
            selectedSidebarDestination = destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                    .foregroundStyle(isSelected ? .white : .secondary)

                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.12))
                } else {
                    Color.clear
                }
            }
        }
        .buttonStyle(.plain)
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
                ProfileAvatarView(userProfile: viewModel.userProfile, size: 30)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profileDisplayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(ConstantsApi.host)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        case .home, .search, .bookmarks, .settings:
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
                    .tint(AppTheme.accent)
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

                mirrorPanel
                accountPanel
            }
            .frame(width: 620, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 34)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .screenBackground()
    }

    private var mirrorPanel: some View {
        SettingsPanel {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Зеркало")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Адрес активного зеркала HDRezka.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                TextField(ConstantsApi.defaultHost, text: $mirror)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(AppTheme.hairline.opacity(0.6), lineWidth: 1)
                    }

                HStack(spacing: 10) {
                    Button("Сохранить", action: saveMirror)
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)

                    Button("Сбросить", action: resetMirror)
                        .buttonStyle(.bordered)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Text("По умолчанию: \(ConstantsApi.defaultHost)")

                    if let statusMessage {
                        Text(statusMessage)
                            .fontWeight(.semibold)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    private var accountPanel: some View {
        SettingsPanel {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Аккаунт")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Смена профиля и выход из текущей сессии.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    authorizationViewModel.logout()
                    dismiss()
                } label: {
                    Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.bordered)
            }
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

private struct SettingsPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppTheme.hairline.opacity(0.45), lineWidth: 1)
            }
    }
}

private struct MacWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
    }
}
#endif
