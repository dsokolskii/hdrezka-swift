#if os(macOS)
import SwiftUI

/// macOS-обёртка над tvOS `MediaHomeView`: показывает полку «Продолжить просмотр»
/// и подборки по категориям (Фильмы, Сериалы, Аниме, Мультфильмы).
struct MacHomeView: View {
    @State private var viewModel: MediaHomeViewModel

    init(viewModel: MediaHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        MediaHomeView(viewModel: viewModel)
    }
}

/// Отдельный экран «Продолжить просмотр»: только элементы из локальной истории.
struct MacContinueWatchingView: View {
    @State private var items: [ContinueWatchingPayload.Item] = []
    @StateObject private var bookmarkViewModel = MediaBookmarksViewModel.shared

    /// Запрос на подтверждение удаления тайтла из подборки.
    @State private var pendingRemoval: ContinueWatchingPayload.Item?

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 210, maximum: 260), spacing: AppTheme.gridSpacing, alignment: .top)
    ]

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    Text("Продолжить просмотр")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    if items.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, alignment: .center, spacing: AppTheme.gridSpacing) {
                            ForEach(Array(items.enumerated()), id: \.element.mediaId) { _, item in
                                let media = media(from: item)

                                NavigationLink {
                                    DetailedMediaItemView(
                                        viewModel: DetailedMediaItemViewModel(media: media),
                                        bookmarkViewModel: bookmarkViewModel,
                                        autoResumePlaybackPosition: item.playbackPosition
                                    )
                                } label: {
                                    MediaItemViewView(media: media, isBookmarked: bookmarkViewModel.isBookmarked(for: media))
                                        .frame(width: MediaItemViewView.coverSize.width, height: MediaItemViewView.coverSize.height)
                                }
                                .buttonStyle(.borderless)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        pendingRemoval = item
                                    } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 48)
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 24)
            }
            .scrollIndicators(.hidden)
            .screenBackground()
        }
        .navigationTitle("Продолжить просмотр")
        .onFirstAppear { reload() }
        .onAppear { reload() }
        .confirmationDialog(
            pendingRemoval?.title ?? "",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if $0 == false { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить из подборки", role: .destructive) {
                if let removal = pendingRemoval {
                    ContinueWatchingHistorySync.removeFromShelf(mediaId: removal.mediaId)
                    reload()
                    pendingRemoval = nil
                }
            }
            Button("Отмена", role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            Text("Тайтл исчезнет из подборки «Продолжить просмотр» и Top Shelf. Вновь появится здесь при следующем просмотре.")
        }
    }

    private var emptyState: some View {
        AppPanel {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))

                Text("История пуста")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                Text("Начните смотреть фильм или сериал — здесь появятся последние позиции для быстрого продолжения.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    private func media(from item: ContinueWatchingPayload.Item) -> Media {
        Media(
            title: item.title,
            url: item.mediaURL,
            descriptionShort: item.subtitle,
            description: nil,
            coverUrl: item.coverURL,
            seriesInfo: item.isSeries ? (item.subtitle.isEmpty ? "Сериал" : item.subtitle) : nil,
            category: item.isSeries ? .series : .films,
            quality: .unknown
        )
    }

    private func reload() {
        items = (ContinueWatchingStore.load()?.items ?? [])
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
#endif
