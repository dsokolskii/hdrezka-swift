import SwiftUI

struct WatchRootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AuthorizationViewModel.self) private var authorizationViewModel
    @State private var viewModel: ContentViewModel

    init(viewModel: ContentViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if authorizationViewModel.isAuthenticated {
                WatchHomeView(viewModel: viewModel)
                    .id(authorizationViewModel.sessionID)
            } else {
                WatchAuthorizationView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct WatchHomeView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AuthorizationViewModel.self) private var authorizationViewModel
    let viewModel: ContentViewModel

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    WatchSearchView(viewModel: container.makeSearchViewModel())
                } label: {
                    Label("Поиск", systemImage: "magnifyingglass")
                }

                Section("Каталог") {
                    switch viewModel.phase {
                    case .fetching:
                        ProgressView()

                    case .failure(let error):
                        WatchRetryView(text: error.localizedDescription) {
                            refreshTask()
                        }

                    default:
                        ForEach(viewModel.categories.filter { $0.type != .search }) { category in
                            NavigationLink {
                                WatchMediaListView(
                                    title: category.name,
                                    viewModel: container.makeMediaContentViewModel(
                                        category: category.type,
                                        filters: category.filters,
                                        genres: category.genres
                                    )
                                )
                            } label: {
                                Label(category.name, systemImage: systemImage(for: category.type))
                            }
                        }
                    }
                }

                Section {
                    Button("Выйти", role: .destructive) {
                        authorizationViewModel.logout()
                    }
                }
            }
            .navigationTitle(ConstantsApi.host)
            .task(refreshTask)
            .refreshable {
                await viewModel.load()
            }
        }
    }

    private func refreshTask() {
        Task {
            await viewModel.load()
        }
    }

    private func systemImage(for category: Category) -> String {
        switch category {
        case .films:
            "film"
        case .series:
            "play.square.stack"
        case .cartoons:
            "face.smiling"
        case .animation:
            "paintbrush.pointed"
        case .new:
            "sparkles"
        default:
            "play.rectangle"
        }
    }
}

private struct WatchAuthorizationView: View {
    @Environment(AuthorizationViewModel.self) private var authorizationViewModel
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(ConstantsApi.host) {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                }

                if let errorMessage = authorizationViewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    Task {
                        await authorizationViewModel.login(email: email, password: password)
                        if authorizationViewModel.isAuthenticated {
                            password = ""
                        }
                    }
                } label: {
                    if authorizationViewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("Войти")
                    }
                }
                .disabled(authorizationViewModel.isLoading)
            }
            .navigationTitle("Rezka")
        }
    }
}

private struct WatchRetryView: View {
    let text: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Повторить", action: action)
        }
    }
}
