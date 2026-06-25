import AVKit

import AVFoundation
import UniformTypeIdentifiers

final class HLSCachingLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let router: HLSURLRouter
    private let session: URLSession

    init(router: HLSURLRouter, cache: URLCache) {
        self.router = router
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = cache
        self.session = RezkaURLSession.make(configuration: config)
    }

    func resourceLoader(_ loader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard let fakeURL = request.request.url,
              let realURL = router.resolve(fakeURL) else {
            PlayerViewController.Coordinator.log("LOADER resolve failed fakeURL=\(request.request.url?.absoluteString ?? "nil")")
            request.finishLoading(with: NSError(domain: "HLSMapping", code: -1))
            return false
        }

        let urlRequest = makeRequest(for: realURL, loadingRequest: request)
        PlayerViewController.Coordinator.log("LOADER request url=\(realURL.absoluteString) range=\(urlRequest.value(forHTTPHeaderField: "Range") ?? "nil")")

        session.dataTask(with: urlRequest) { data, response, error in
            if let error = error {
                PlayerViewController.Coordinator.log("LOADER error=\(error.localizedDescription)")
                request.finishLoading(with: error)
                return
            }

            guard let data = data,
                  let response = response as? HTTPURLResponse,
                  let dataRequest = request.dataRequest else {
                PlayerViewController.Coordinator.log("LOADER invalid response data=\(data != nil) response=\(String(describing: response))")
                request.finishLoading(with: NSError(domain: "HLSData", code: -2))
                return
            }

            PlayerViewController.Coordinator.log("LOADER response status=\(response.statusCode) mime=\(response.mimeType ?? "nil") len=\(data.count)")

            if let contentInfo = request.contentInformationRequest {
                let mimeType = response.mimeType ?? "application/octet-stream"
                contentInfo.contentType = UTType(mimeType: mimeType)?.identifier
                contentInfo.contentLength = self.contentLength(from: response) ?? Int64(data.count)
                contentInfo.isByteRangeAccessSupported = self.isByteRangeAccessSupported(response: response)
            }

            dataRequest.respond(with: data)
            request.finishLoading()
        }.resume()

        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        PlayerViewController.Coordinator.log("LOADER cancelled")
        loadingRequest.finishLoading()
    }

    private func makeRequest(for url: URL, loadingRequest: AVAssetResourceLoadingRequest) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(ApiConstants.userAgent, forHTTPHeaderField: ApiConstants.userAgentKey)
        request.setValue(ConstantsApi.server, forHTTPHeaderField: "Referer")
        request.setValue(ConstantsApi.server, forHTTPHeaderField: "Origin")

        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)
        for (name, value) in cookieHeader {
            request.setValue(value, forHTTPHeaderField: name)
        }

        if let dataRequest = loadingRequest.dataRequest {
            let startOffset = dataRequest.currentOffset > 0 ? dataRequest.currentOffset : dataRequest.requestedOffset
            let endOffset = dataRequest.requestsAllDataToEndOfResource
                ? nil
                : startOffset + Int64(dataRequest.requestedLength) - 1

            if let endOffset {
                request.setValue("bytes=\(startOffset)-\(endOffset)", forHTTPHeaderField: "Range")
            } else {
                request.setValue("bytes=\(startOffset)-", forHTTPHeaderField: "Range")
            }
        }

        return request
    }

    private func contentLength(from response: HTTPURLResponse) -> Int64? {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
           let totalLength = contentRange.split(separator: "/").last,
           let value = Int64(totalLength) {
            return value
        }

        let expectedLength = response.expectedContentLength
        return expectedLength > 0 ? expectedLength : nil
    }

    private func isByteRangeAccessSupported(response: HTTPURLResponse) -> Bool {
        if let acceptRanges = response.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased(),
           acceptRanges.contains("bytes") {
            return true
        }

        return response.statusCode == 206 || response.value(forHTTPHeaderField: "Content-Range") != nil
    }
}

final class HLSURLRouter {
    private var mapping: [URL: URL] = [:]
    
    let cache: URLCache
    
    init(cache: URLCache) {
        self.cache = cache
    }

    /// Register a real URL and return a fake `caching://` URL for resource loading.
    func register(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.scheme = "caching"
        let fakeURL = components.url!
        mapping[fakeURL] = url
        return fakeURL
    }

    /// Resolve a fake `caching://` URL to the actual CDN URL.
    func resolve(_ fakeURL: URL) -> URL? {
        mapping[fakeURL]
    }
}
