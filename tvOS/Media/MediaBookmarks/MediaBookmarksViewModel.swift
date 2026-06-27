import SwiftUI

struct BookmarkFolder: Equatable, Identifiable {
    let id: String
    let name: String
    let count: Int
    let url: URL?
    var medias: [Media]
}

struct BookmarkLibrary: Equatable {
    var folders: [BookmarkFolder]
    var medias: [Media]
}

@MainActor
final class MediaBookmarksViewModel: ObservableObject {
    @Published private(set) var phase = DataFetchPhase<BookmarkLibrary>.fetching
    @Published private(set) var folders: [BookmarkFolder] = []
    @Published private(set) var bookmarks: [Media] = []
    @Published private(set) var actionErrorMessage: String?
    @Published private(set) var isUpdating = false
    @Published private(set) var isLoadingBookmarks = false
    @Published private(set) var bookmarkFolderIDsByMediaURL: [String: Set<String>] = [:]
    @Published private(set) var selectedFolderID: String?

    private var bookmarkedURLs = Set<String>()
    private let api = RezkaBookmarksApi()

    static let shared = MediaBookmarksViewModel()

    private init() {
        Task {
            await load()
        }
    }

    func load(folderID: String? = nil) async {
        let hasLoadedFolders = folders.isEmpty == false

        if let folderID,
           hasLoadedFolders,
           let folder = folders.first(where: { $0.id == folderID }) {
            await loadBookmarks(in: folder)
            return
        }

        if hasLoadedFolders {
            isLoadingBookmarks = true
        } else {
            phase = .fetching
        }

        do {
            let library = try await api.fetchBookmarks(folderID: folderID)
            bookmarks = library.medias

            if folderID == nil || hasLoadedFolders == false {
                folders = library.folders
                rebuildIndex()
            }

            phase = .success(library)
        } catch {
            if hasLoadedFolders {
                actionErrorMessage = error.localizedDescription
            } else {
                phase = .failure(error)
            }
        }

        isLoadingBookmarks = false
    }

    func selectInitialFolderIfNeeded() {
        if let selectedFolderID,
           folders.contains(where: { $0.id == selectedFolderID }) {
            return
        }

        selectedFolderID = folders.first?.id
    }

    func selectFolder(id: String?) {
        selectedFolderID = id
    }

    private func loadBookmarks(in folder: BookmarkFolder) async {
        isLoadingBookmarks = true
        actionErrorMessage = nil

        do {
            bookmarks = try await api.fetchBookmarks(in: folder)
            updateMedias(bookmarks, in: folder.id)
            phase = .success(BookmarkLibrary(folders: folders, medias: bookmarks))
        } catch {
            actionErrorMessage = error.localizedDescription
        }

        isLoadingBookmarks = false
    }

    func isBookmarked(for media: Media) -> Bool {
        bookmarkedURLs.contains(media.url)
    }

    func isBookmarked(_ media: Media, in folder: BookmarkFolder) -> Bool {
        folderIDs(containing: media).contains(folder.id)
    }

    func folderIDs(containing media: Media) -> Set<String> {
        var folderIDs = bookmarkFolderIDsByMediaURL[media.url] ?? []

        folders
            .filter { folder in
                folder.medias.contains { $0.url == media.url }
            }
            .map(\.id)
            .forEach { folderIDs.insert($0) }

        return folderIDs
    }

    func bookMarkIcon(for media: Media) -> String {
        isBookmarked(for: media) ? "bookmark.fill" : "bookmark"
    }

    func medias(in folderID: String?) -> [Media] {
        guard let folderID else {
            return bookmarks
        }

        return folders.first(where: { $0.id == folderID })?.medias ?? []
    }

    func count(in folderID: String?) -> Int {
        guard let folderID else {
            return bookmarks.count
        }

        return folders.first(where: { $0.id == folderID })?.count ?? 0
    }

    func prepareFolderLoad() {
        isLoadingBookmarks = true
        actionErrorMessage = nil
    }

    func createFolder(named rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { return }

        await update {
            try await api.createFolder(named: name)
            try await refreshAfterMutation()
        }
    }

    func addBookmark(mediaID: Int, to folderID: String) async {
        await update {
            try await api.addBookmark(mediaID: mediaID, folderID: folderID)
            try await refreshAfterMutation()
        }
    }

    func addBookmark(media: Media, mediaID: Int, to folderID: String) async {
        await update {
            try await api.addBookmark(mediaID: mediaID, folderID: folderID)
            setMembership(for: media.url, folderID: folderID, isContained: true)
            updateMedia(media, in: folderID, isContained: true)
            updateBookmarkCount(in: folderID, delta: 1)
            await refreshAfterMutationIfPossible()
        }
    }

    func removeBookmark(mediaID: Int, from folderID: String?) async {
        await update {
            try await api.removeBookmark(mediaID: mediaID, folderID: folderID)
            try await refreshAfterMutation()
        }
    }

    func removeBookmark(media: Media, mediaID: Int, from folderID: String) async {
        await update {
            try await api.removeBookmark(mediaID: mediaID, folderID: folderID)
            setMembership(for: media.url, folderID: folderID, isContained: false)
            updateMedia(media, in: folderID, isContained: false)
            updateBookmarkCount(in: folderID, delta: -1)
            await refreshAfterMutationIfPossible()
        }
    }

    func refreshContainingFolders(for media: Media) async {
        actionErrorMessage = nil

        if folders.isEmpty {
            await load()
        }

        var containingFolderIDs = Set<String>()
        var lastError: Error?

        for folder in folders {
            do {
                let medias = try await api.fetchBookmarks(in: folder)
                updateMedias(medias, in: folder.id)

                if medias.contains(where: { $0.url == media.url }) {
                    containingFolderIDs.insert(folder.id)
                }
            } catch {
                lastError = error
            }
        }

        var membership = bookmarkFolderIDsByMediaURL
        membership[media.url] = containingFolderIDs
        bookmarkFolderIDsByMediaURL = membership
        rebuildIndex()

        if let lastError, containingFolderIDs.isEmpty {
            actionErrorMessage = lastError.localizedDescription
        }
    }

    func clearActionError() {
        actionErrorMessage = nil
    }

    private func update(_ action: () async throws -> Void) async {
        isUpdating = true
        actionErrorMessage = nil

        do {
            try await action()
        } catch {
            actionErrorMessage = error.localizedDescription
        }

        isUpdating = false
    }

    private func refreshAfterMutation() async throws {
        let library = try await api.fetchBookmarks()
        updateFoldersPreservingLoadedMedias(library.folders)
        bookmarks = library.medias
        rebuildIndex()
        phase = .success(library)
    }

    private func refreshAfterMutationIfPossible() async {
        do {
            try await refreshAfterMutation()
        } catch {
            phase = .success(BookmarkLibrary(folders: folders, medias: bookmarks))
        }
    }

    private func rebuildIndex() {
        var urls = Set(bookmarks.map(\.url))

        folders
            .flatMap(\.medias)
            .map(\.url)
            .forEach { urls.insert($0) }

        bookmarkFolderIDsByMediaURL
            .filter { $0.value.isEmpty == false }
            .map(\.key)
            .forEach { urls.insert($0) }

        bookmarkedURLs = urls
    }

    private func setMembership(for mediaURL: String, folderID: String, isContained: Bool) {
        var membership = bookmarkFolderIDsByMediaURL
        var folderIDs = membership[mediaURL] ?? []

        if isContained {
            folderIDs.insert(folderID)
        } else {
            folderIDs.remove(folderID)
        }

        membership[mediaURL] = folderIDs
        bookmarkFolderIDsByMediaURL = membership
        rebuildIndex()
    }

    private func updateFoldersPreservingLoadedMedias(_ newFolders: [BookmarkFolder]) {
        let loadedMediasByFolderID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.medias) })

        folders = newFolders.map { folder in
            BookmarkFolder(
                id: folder.id,
                name: folder.name,
                count: folder.count,
                url: folder.url,
                medias: loadedMediasByFolderID[folder.id] ?? folder.medias
            )
        }
    }

    private func updateBookmarkCount(in folderID: String, delta: Int) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }

        let folder = folders[index]
        folders[index] = BookmarkFolder(
            id: folder.id,
            name: folder.name,
            count: max(0, folder.count + delta),
            url: folder.url,
            medias: folder.medias
        )
    }

    private func updateMedia(_ media: Media, in folderID: String, isContained: Bool) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }

        var medias = folders[index].medias

        if isContained {
            if medias.contains(where: { $0.url == media.url }) == false {
                medias.insert(media, at: 0)
            }
        } else {
            medias.removeAll { $0.url == media.url }
        }

        folders[index] = BookmarkFolder(
            id: folders[index].id,
            name: folders[index].name,
            count: folders[index].count,
            url: folders[index].url,
            medias: medias
        )

        if selectedFolderID == folderID {
            bookmarks = medias
        }

        rebuildIndex()
        phase = .success(BookmarkLibrary(folders: folders, medias: bookmarks))
    }

    private func updateMedias(_ medias: [Media], in folderID: String) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }

        folders[index] = BookmarkFolder(
            id: folders[index].id,
            name: folders[index].name,
            count: folders[index].count,
            url: folders[index].url,
            medias: medias
        )
    }
}
