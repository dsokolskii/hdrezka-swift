#if os(tvOS)
import SwiftUI
import UIKit

typealias PlatformImage = UIImage

func platformImageView(_ image: PlatformImage) -> Image {
    Image(uiImage: image)
}

func platformImage(from data: Data) -> PlatformImage? {
    guard let image = UIImage(data: data) else {
        return nil
    }

    return image.preparingForDisplay() ?? image
}

func platformImage(from cgImage: CGImage, scale: CGFloat) -> PlatformImage {
    UIImage(cgImage: cgImage, scale: scale, orientation: .up)
}

struct PosterImageView: UIViewRepresentable {
    let image: PlatformImage

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.backgroundColor = .clear
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.layer.drawsAsynchronously = true
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        if imageView.image !== image {
            imageView.image = image
        }
    }
}

extension PlatformImage {
    var cacheCost: Int {
        if let cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }

        return Int(size.width * size.height * scale * scale * 4)
    }
}
#endif
