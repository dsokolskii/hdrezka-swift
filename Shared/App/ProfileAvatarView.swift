import SwiftUI

struct ProfileAvatarView: View {
    let userProfile: RezkaUserProfile?
    let size: CGFloat

    var body: some View {
        if let avatarURL = userProfile?.avatarURL {
            CacheAsyncImage(
                url: avatarURL,
                targetSize: CGSize(width: size * 2, height: size * 2),
                requestHeaders: [ApiConstants.userAgentKey: ApiConstants.userAgent]
            ) { phase in
                switch phase {
                case .success(let image):
                    platformImageView(image)
                        .resizable()
                        .scaledToFill()
                default:
                    fallbackProfileAvatar
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            fallbackProfileAvatar
        }
    }

    private var fallbackProfileAvatar: some View {
        Image(systemName: "person.fill")
            .font(.system(size: size * 0.62, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
    }
}
