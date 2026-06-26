import SwiftUI

struct MediaBookmarksView: View {
    private enum FocusTarget: Hashable {
        case folder(String)
        case createFolder
        case media(String)
    }

    @StateObject private var viewModel = MediaBookmarksViewModel.shared
    @State private var isCreateFolderPresented = false
    @State private var newFolderName = ""
    @FocusState private var focusedTarget: FocusTarget?

    private let onMoveLeftToProfileMenu: () -> Void
    private let focusRequest: Int

    private let columns = Array(
        repeating: GridItem(.fixed(MediaItemViewView.coverSize.width), spacing: AppTheme.gridSpacing),
        count: 5
    )

    init(onMoveLeftToProfileMenu: @escaping () -> Void = {}, focusRequest: Int = 0) {
        self.onMoveLeftToProfileMenu = onMoveLeftToProfileMenu
        self.focusRequest = focusRequest
    }

    var body: some View {
        ZStack {
            ScreenBackground()

            bookmarksContent
        }
        .navigationTitle("Закладки")
        .onFirstAppear {
            Task {
                await loadInitialBookmarks()
            }
        }
        .alert("Новая папка", isPresented: $isCreateFolderPresented) {
            TextField("Название", text: $newFolderName)

            Button("Создать") {
                Task {
                    await createFolder()
                }
            }

            Button("Отмена", role: .cancel) {
                newFolderName = ""
            }
        } message: {
            Text("Раздел будет создан в аккаунте HDRezka.")
        }
        .alert(
            "Не удалось обновить закладки",
            isPresented: Binding(
                get: { viewModel.actionErrorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        viewModel.clearActionError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.clearActionError()
            }
        } message: {
            Text(viewModel.actionErrorMessage ?? "Попробуйте еще раз.")
        }
        .onChange(of: focusRequest) { _, _ in
            focusFirstBookmarkControl()
        }
    }

    @ViewBuilder
    private var bookmarksContent: some View {
        switch viewModel.phase {
        case .fetching:
            LoadingPanel()
        case .failure(let error):
            RetryView(text: error.localizedDescription) {
                Task {
                    await viewModel.load(folderID: viewModel.selectedFolderID)
                }
            }
        default:
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    folderToolbar

                    if selectedMedias.isEmpty, viewModel.isLoadingBookmarks == false {
                        emptyState
                    } else {
                        bookmarksGrid
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 34)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var folderToolbar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(Array(viewModel.folders.enumerated()), id: \.element.id) { index, folder in
                    folderButton(title: folder.name, count: viewModel.count(in: folder.id), folderID: folder.id)
                        .focused($focusedTarget, equals: .folder(folder.id))
                        .onMoveCommand { direction in
                            if direction == .up || (direction == .left && index == 0) {
                                onMoveLeftToProfileMenu()
                            }
                        }
                }

                Button {
                    newFolderName = ""
                    isCreateFolderPresented = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.callout.weight(.semibold))
                        .accessibilityLabel("Новая папка")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
                .focused($focusedTarget, equals: .createFolder)
                .onMoveCommand { direction in
                    if direction == .up || (direction == .left && viewModel.folders.isEmpty) {
                        onMoveLeftToProfileMenu()
                    }
                }
            }
            .focusSection()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .padding(.horizontal, -22)
        .padding(.vertical, -14)
        .scrollIndicators(.hidden)
    }

    private func folderButton(title: String, count: Int, folderID: String?) -> some View {
        Button {
            selectFolder(folderID)
        } label: {
            folderLabel(title: title, count: count, folderID: folderID)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }

    private func folderLabel(title: String, count: Int, folderID: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected(folderID) ? "folder.fill" : "folder")
            Text(title)
                .lineLimit(1)
            Text("\(count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .font(.callout.weight(.semibold))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var bookmarksGrid: some View {
        ZStack {
            LazyVGrid(columns: columns, alignment: .center, spacing: AppTheme.gridSpacing) {
                ForEach(Array(selectedMedias.enumerated()), id: \.element.id) { index, media in
                    NavigationLink {
                        DetailedMediaItemView(
                            viewModel: DetailedMediaItemViewModel(media: media),
                            bookmarkViewModel: viewModel,
                            onMoveLeftToProfileMenu: onMoveLeftToProfileMenu
                        )
                    } label: {
                        MediaItemViewView(media: media, isBookmarked: true)
                            .frame(width: MediaItemViewView.coverSize.width, height: MediaItemViewView.coverSize.height)
                    }
                    .buttonStyle(.borderless)
                    .focused($focusedTarget, equals: .media(media.id))
                    .onMoveLeftToProfileMenu(index.isMultiple(of: columns.count), perform: onMoveLeftToProfileMenu)
                }
            }

            if viewModel.isLoadingBookmarks {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .padding(22)
                    .glassEffect(in: .rect(cornerRadius: 22))
            }
        }
        .frame(maxWidth: .infinity, minHeight: MediaItemViewView.coverSize.height, alignment: .center)
        .focusSection()
    }

    private var emptyState: some View {
        AppPanel {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: viewModel.selectedFolderID == nil ? "bookmark" : "folder")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))

                Text(emptyTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                Text("Откройте фильм или сериал и добавьте его в нужную папку.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    private var selectedMedias: [Media] {
        guard let selectedFolderID = viewModel.selectedFolderID else {
            return []
        }

        return viewModel.medias(in: selectedFolderID)
    }

    private var emptyTitle: String {
        viewModel.selectedFolderID == nil ? "Закладок пока нет" : "В этой папке пусто"
    }

    private func isSelected(_ folderID: String?) -> Bool {
        viewModel.selectedFolderID == folderID
    }

    private func selectFolder(_ folderID: String?) {
        guard viewModel.selectedFolderID != folderID else {
            return
        }

        viewModel.prepareFolderLoad()
        viewModel.selectFolder(id: folderID)

        Task {
            await viewModel.load(folderID: folderID)
        }
    }

    private func createFolder() async {
        await viewModel.createFolder(named: newFolderName)
        newFolderName = ""
    }

    private func loadInitialBookmarks() async {
        if viewModel.folders.isEmpty {
            await viewModel.load()
        }

        viewModel.selectInitialFolderIfNeeded()

        if let selectedFolderID = viewModel.selectedFolderID {
            await viewModel.load(folderID: selectedFolderID)
        }
    }

    private func focusFirstBookmarkControl() {
        if let firstFolder = viewModel.folders.first {
            focusedTarget = .folder(firstFolder.id)
            return
        }

        if selectedMedias.isEmpty == false, let firstMedia = selectedMedias.first {
            focusedTarget = .media(firstMedia.id)
            return
        }

        focusedTarget = .createFolder
    }
}

struct MediaBookmarksView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MediaBookmarksView()
        }
    }
}
