import SwiftUI

struct MediaItemViewView: View {
    static let coverSize = CGSize(width: 260, height: 390)
    
    let media: Media
    let isBookmarked: Bool
    @Environment(\.isFocused) private var isFocused

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.cardCorner, style: .continuous)
    }
    
    var body: some View {
        ZStack {
            ZStack {
                Rectangle()
                    .fill(AppTheme.panel)

                if let url = media.coverURL {
                    CacheAsyncImage(
                        url: url,
                        targetSize: Self.coverSize,
                        session: RezkaURLSession.shared,
                        requestHeaders: ApiConstants.imageHeaders
                    ) { $0.view }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if isFocused {
                    LinearGradient(
                        colors: [.white.opacity(0.08), .clear, .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                LinearGradient(
                    colors: [.black.opacity(0.06), .clear, .black.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading) {
                    HStack {
                        if media.isSeries, let seriesInfo = media.seriesInfo {
                            Text(seriesInfo)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundStyle(.white)
                                .background(.black.opacity(0.3), in: Capsule())
                        }

                        Spacer()
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 8) {
                        Text(media.title)
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(4)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 2)

                        if media.descriptionShort.isEmpty == false {
                            Text(media.descriptionShort)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }

            cardShape
                .strokeBorder(
                    isFocused ? .white.opacity(0.92) : AppTheme.hairline.opacity(0.5),
                    lineWidth: isFocused ? 2.5 : 1
                )
        }
        .clipShape(cardShape)
        .shadow(color: .black.opacity(isFocused ? 0.28 : 0), radius: isFocused ? 12 : 0, y: isFocused ? 8 : 0)
        .scaleEffect(isFocused ? 1.035 : 1)
    }
}

struct MediaItemViewView_Previews: PreviewProvider {
    static var previews: some View {
        MediaContentView(viewModel: AppContainer.live.makeMediaContentViewModel())
    }
}
