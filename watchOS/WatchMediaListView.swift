import SwiftUI

struct WatchMediaListView: View {
    let title: String
    @State private var viewModel: MediaContentViewModel

    init(title: String, viewModel: MediaContentViewModel) {
        self.title = title
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            if viewModel.filters.isEmpty == false || viewModel.genres.isEmpty == false {
                WatchMediaControlsView(viewModel: viewModel)
            }

            WatchMediaRows(
                medias: viewModel.newMedias.filter { $0.category != .loadMore },
                canLoadMore: viewModel.newMedias.contains { $0.category == .loadMore },
                loadMore: loadMoreTask
            )

            switch viewModel.phase {
            case .fetching:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case .success(let medias) where medias.filter({ $0.category != .loadMore }).isEmpty:
                Text("Ничего не найдено")
                    .foregroundStyle(.secondary)
            case .failure(let error):
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Повторить", action: refreshTask)
                }
            default:
                EmptyView()
            }
        }
        .navigationTitle(title)
        .task(refreshTask)
        .refreshable {
            await viewModel.loadMedias()
        }
    }

    private func refreshTask() {
        Task {
            await viewModel.loadMedias()
        }
    }

    private func loadMoreTask() {
        Task {
            await viewModel.loadMore()
        }
    }
}

private struct WatchMediaControlsView: View {
    let viewModel: MediaContentViewModel

    var body: some View {
        Section {
            if viewModel.filters.isEmpty == false {
                Picker("Сортировка", selection: filterSelection) {
                    ForEach(viewModel.filters) { filter in
                        Text(filter.name)
                            .tag(filter.id as UUID?)
                    }
                }
            }

            if viewModel.genres.isEmpty == false {
                Picker("Жанр", selection: genreSelection) {
                    Text("Все")
                        .tag(nil as UUID?)
                    ForEach(viewModel.genres) { genre in
                        Text(genre.name)
                            .tag(genre.id as UUID?)
                    }
                }
            }
        }
    }

    private var filterSelection: Binding<UUID?> {
        Binding {
            viewModel.selectedFilter?.id
        } set: { id in
            guard let filter = viewModel.filters.first(where: { $0.id == id }) else { return }
            Task {
                await viewModel.setFilter(filter)
            }
        }
    }

    private var genreSelection: Binding<UUID?> {
        Binding {
            viewModel.selectedGenre?.id
        } set: { id in
            let genre = viewModel.genres.first { $0.id == id }
            Task {
                await viewModel.setGenre(genre)
            }
        }
    }
}

struct WatchSearchView: View {
    @State private var query = ""
    @State private var viewModel: MediaSearchContentViewModel
    @State private var searchTask: Task<Void, Never>?

    init(viewModel: MediaSearchContentViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            Section {
                TextField("Фильм или сериал", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(search)
            }

            WatchMediaRows(
                medias: normalizedQuery.isEmpty ? [] : viewModel.newMedias,
                canLoadMore: normalizedQuery.isEmpty ? false : viewModel.canLoadMore,
                loadMore: loadMoreTask
            )

            if normalizedQuery.isEmpty {
                Text("Введите название")
                    .foregroundStyle(.secondary)
            } else {
                switch viewModel.phase {
                case .fetching:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                case .success(let medias) where medias.isEmpty:
                    Text("Ничего не найдено")
                        .foregroundStyle(.secondary)
                case .failure(let error):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error.localizedDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Повторить", action: search)
                    }
                default:
                    EmptyView()
                }
            }
        }
        .navigationTitle("Поиск")
        .searchable(text: $query, prompt: "Фильм или сериал")
        .onChange(of: query) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard Task.isCancelled == false else { return }
                await viewModel.updateSearch(text: newValue)
                guard newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
                await viewModel.submitSearch()
            }
        }
        .refreshable {
            guard normalizedQuery.isEmpty == false else { return }
            await viewModel.submitSearch()
        }
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func search() {
        Task {
            await viewModel.updateSearch(text: query)
            guard normalizedQuery.isEmpty == false else { return }
            await viewModel.submitSearch()
        }
    }

    private func loadMoreTask() {
        Task {
            await viewModel.loadMore()
        }
    }
}

private struct WatchMediaRows: View {
    let medias: [Media]
    let canLoadMore: Bool
    let loadMore: () -> Void

    var body: some View {
        ForEach(medias) { media in
            NavigationLink {
                WatchMediaDetailView(media: media)
            } label: {
                WatchMediaRow(media: media)
            }
        }

        if canLoadMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .onAppear(perform: loadMore)
        }
    }
}

private struct WatchMediaRow: View {
    let media: Media

    var body: some View {
        HStack(spacing: 10) {
            WatchPosterView(url: media.coverURL)
                .frame(width: 44, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(media.title)
                    .font(.headline)
                    .lineLimit(2)

                if let seriesInfo = media.seriesInfo, seriesInfo.isEmpty == false {
                    Text(seriesInfo)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if media.descriptionShort.isEmpty == false {
                    Text(media.descriptionShort)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
