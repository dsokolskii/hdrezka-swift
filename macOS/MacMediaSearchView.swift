#if os(macOS)
import SwiftUI

struct MacMediaSearchView: View {
    @State private var text = ""
    @State private var viewModel: MediaSearchContentViewModel
    @State private var searchTask: Task<Void, Never>?

    init(viewModel: MediaSearchContentViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    pageHeader

                    searchField

                    LazyVGrid(columns: columns, alignment: .center, spacing: AppTheme.gridSpacing) {
                        ForEach(viewModel.newMedias, id: \.id) { media in
                            let isBookmarked = bookmarkViewModel.isBookmarked(for: media)

                            NavigationLink {
                                DetailedMediaItemView(
                                    viewModel: DetailedMediaItemViewModel(media: media),
                                    bookmarkViewModel: bookmarkViewModel
                                )
                            } label: {
                                MediaItemViewView(media: media, isBookmarked: isBookmarked)
                                    .frame(width: MediaItemViewView.coverSize.width, height: MediaItemViewView.coverSize.height)
                            }
                            .buttonStyle(.borderless)
                        }

                        if viewModel.canLoadMore {
                            Color.clear
                                .frame(height: 1)
                                .onAppear(perform: loadMoreTask)
                        }
                    }
                    .padding(.bottom, 48)
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 24)
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            .allowsHitTesting(isBlockingOverlayPresented == false)
            .onChange(of: text) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard Task.isCancelled == false else { return }
                    await viewModel.updateSearch(text: newValue)
                    await viewModel.submitSearch()
                }
            }
            .onFirstAppear {
                Task {
                    await viewModel.submitSearch()
                }
            }

            overlayView
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Поиск")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Найдите фильм или сериал в каталоге")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Поиск по всему каталогу", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .autocorrectionDisabled()

            if text.isEmpty == false {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppTheme.hairline.opacity(0.5), lineWidth: 1)
        }
    }

    @StateObject private var bookmarkViewModel = MediaBookmarksViewModel.shared

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: MediaItemViewView.coverSize.width,
                    maximum: MediaItemViewView.coverSize.width
                ),
                spacing: AppTheme.gridSpacing,
                alignment: .top
            )
        ]
    }

    @ViewBuilder
    private var overlayView: some View {
        switch viewModel.phase {
        case .fetching:
            LoadingPanel()
        case .success(let medias) where medias.isEmpty:
            EmptyPlaceholderView(text: "No Medias", image: nil)
        case .failure(let error):
            RetryView(text: error.localizedDescription, retryAction: refreshTask)
        default:
            EmptyView()
        }
    }

    private func refreshTask() {
        Task {
            await viewModel.searchMedias()
        }
    }

    private func loadMoreTask() {
        Task {
            await viewModel.loadMore()
        }
    }

    private var isBlockingOverlayPresented: Bool {
        switch viewModel.phase {
        case .fetching:
            true
        case .success(let medias):
            medias.isEmpty
        case .failure:
            true
        case .fetchingNextPage:
            false
        }
    }
}
#endif
