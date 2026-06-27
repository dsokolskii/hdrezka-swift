#if os(macOS)
import SwiftUI
import AppKit

typealias PlatformImage = NSImage

func platformImageView(_ image: PlatformImage) -> Image {
    Image(nsImage: image)
}

func platformImage(from data: Data) -> PlatformImage? {
    NSImage(data: data)
}

func platformImage(from cgImage: CGImage, scale: CGFloat) -> PlatformImage {
    let size = NSSize(
        width: CGFloat(cgImage.width) / max(scale, 1),
        height: CGFloat(cgImage.height) / max(scale, 1)
    )
    return NSImage(cgImage: cgImage, size: size)
}

struct PosterImageView: NSViewRepresentable {
    let image: PlatformImage

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleAxesIndependently
        imageView.animates = false
        return imageView
    }

    func updateNSView(_ imageView: NSImageView, context: Context) {
        if imageView.image !== image {
            imageView.image = image
        }
    }
}

extension PlatformImage {
    var cacheCost: Int {
        if let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cgImage.bytesPerRow * cgImage.height
        }

        return Int(size.width * size.height * 4)
    }
}
#endif
