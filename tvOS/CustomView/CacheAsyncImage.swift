import SwiftUI
import ImageIO

struct CacheAsyncImage<Content>: View where Content: View {
    private let url: URL
    private let request: URLRequest
    private let session: URLSession
    private let targetSize: CGSize?
    private let maxPixelSize: Int?
    private let scale: CGFloat
    private let cacheKey: CacheImageKey
    private let content: (CacheAsyncImagePhase) -> Content

    @State private var phase: CacheAsyncImagePhase
    @State private var loadTask: Task<Void, Never>?

    init(
        url: URL,
        scale: CGFloat = 1.0,
        targetSize: CGSize? = nil,
        maxPixelSize: Int? = nil,
        transaction: Transaction = Transaction(),
        session: URLSession = .shared,
        requestHeaders: [String: String] = [:],
        @ViewBuilder content: @escaping (CacheAsyncImagePhase) -> Content
    ) {
        self.url = url
        self.session = session
        self.targetSize = targetSize
        self.maxPixelSize = maxPixelSize
        self.scale = scale
        self.cacheKey = CacheImageKey(url: url, targetSize: targetSize, maxPixelSize: maxPixelSize, scale: scale, requestHeaders: requestHeaders)
        self.content = content

        var request = URLRequest(url: url)
        for (header, value) in requestHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }
        self.request = request
        _phase = State(initialValue: .empty)
    }

    var body: some View {
        content(phase)
            .onAppear(perform: loadIfNeeded)
            .onDisappear {
                loadTask?.cancel()
                loadTask = nil
            }
    }

    private func loadIfNeeded() {
        if case .success = phase {
            return
        }

        if let cachedImage = ImageCache[cacheKey] {
            phase = .success(cachedImage)
            return
        }

        if loadTask != nil {
            return
        }

        let request = request
        let session = session
        let targetSize = targetSize
        let maxPixelSize = maxPixelSize
        let scale = scale
        let cacheKey = cacheKey

        phase = .empty
        loadTask = Task {
            do {
                let uiImage = try await CacheImagePipeline.shared.image(
                    for: cacheKey,
                    request: request,
                    session: session,
                    targetSize: targetSize,
                    maxPixelSize: maxPixelSize,
                    scale: scale
                )
                try Task.checkCancellation()

                await MainActor.run {
                    phase = .success(uiImage)
                    loadTask = nil
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    phase = .failure(error)
                    loadTask = nil
                }
            }
        }
    }
}

enum CacheAsyncImagePhase {
    case empty
    case success(PlatformImage)
    case failure(Error)
}

private struct CacheImageKey: Hashable {
    let value: String

    init(url: URL, targetSize: CGSize?, maxPixelSize: Int?, scale: CGFloat, requestHeaders: [String: String]) {
        let effectiveMaxPixelSize: Int
        if let targetSize, targetSize.width > 0, targetSize.height > 0 {
            effectiveMaxPixelSize = maxPixelSize ?? Int(ceil(max(targetSize.width, targetSize.height) * max(scale, 1)))
        } else {
            effectiveMaxPixelSize = maxPixelSize ?? 0
        }

        let headers = requestHeaders
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: "|")

        value = "\(url.absoluteString)#\(effectiveMaxPixelSize)#\(headers)"
    }
}

private actor CacheImagePipeline {
    static let shared = CacheImagePipeline()

    private var inFlight: [CacheImageKey: Task<PlatformImage, Error>] = [:]

    func image(
        for cacheKey: CacheImageKey,
        request: URLRequest,
        session: URLSession,
        targetSize: CGSize?,
        maxPixelSize: Int?,
        scale: CGFloat
    ) async throws -> PlatformImage {
        if let cachedImage = ImageCache[cacheKey] {
            return cachedImage
        }

        if let task = inFlight[cacheKey] {
            return try await task.value
        }

        let task = Task.detached(priority: .utility) {
            try await CacheImageWorkLimiter.shared.withPermit {
                let (data, _) = try await session.data(for: request)
                try Task.checkCancellation()
                return try CacheImageDecoder.decodeImage(from: data, targetSize: targetSize, maxPixelSize: maxPixelSize, scale: scale)
            }
        }

        inFlight[cacheKey] = task

        do {
            let image = try await task.value
            ImageCache[cacheKey] = image
            inFlight[cacheKey] = nil
            return image
        } catch {
            inFlight[cacheKey] = nil
            throw error
        }
    }
}

private actor CacheImageWorkLimiter {
    static let shared = CacheImageWorkLimiter(limit: 3)

    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        availablePermits = limit
    }

    func withPermit<T>(_ operation: () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            availablePermits += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

private enum CacheImageDecoder {
    static func decodeImage(from data: Data, targetSize: CGSize?, maxPixelSize: Int?, scale: CGFloat) throws -> PlatformImage {
        guard
            maxPixelSize != nil || (targetSize?.width ?? 0) > 0 && (targetSize?.height ?? 0) > 0
        else {
            guard let image = platformImage(from: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            return image
        }

        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw URLError(.cannotDecodeContentData)
        }

        let effectiveMaxPixelSize = maxPixelSize ?? Int(ceil(max(targetSize?.width ?? 0, targetSize?.height ?? 0) * max(scale, 1)))
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: effectiveMaxPixelSize
        ] as CFDictionary

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw URLError(.cannotDecodeContentData)
        }

        return platformImage(from: image, scale: scale)
    }
}

extension CacheAsyncImagePhase {
    var view: some View {
        PosterSlot(phase: self)
    }
}

private struct PosterSlot: View {
    let phase: CacheAsyncImagePhase

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.18))

            switch phase {
            case .empty:
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundStyle(.white)

            case .success(let image):
                PosterImageView(image: image)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failure:
                EmptyView()

            @unknown default:
                EmptyView()
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}
fileprivate enum ImageCache {
    private static let cache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    static subscript(key: CacheImageKey) -> PlatformImage? {
        get { cache.object(forKey: key.value as NSString) }
        set {
            guard let newValue else {
                cache.removeObject(forKey: key.value as NSString)
                return
            }
            cache.setObject(newValue, forKey: key.value as NSString, cost: newValue.cacheCost)
        }
    }
}
