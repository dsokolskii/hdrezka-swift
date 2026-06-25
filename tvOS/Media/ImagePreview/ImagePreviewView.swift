import SwiftUI

struct ImagePreview : View {
    var url: URL
    
    var body: some View {
        CacheAsyncImage(
            url: url,
            session: RezkaURLSession.shared,
            requestHeaders: ApiConstants.imageHeaders
        ) { $0.view }
            .background(Color.clear)
            .cornerRadius(5)
            .shadow(radius: 5)
    }
}
