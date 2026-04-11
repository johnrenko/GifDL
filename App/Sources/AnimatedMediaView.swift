import ImageIO
import SwiftUI
import UIKit

struct AnimatedMediaView: UIViewRepresentable {
    let item: ImportedMedia

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        guard let url = item.resolvedLocalFileURL else {
            uiView.image = UIImage(systemName: "photo")
            return
        }

        uiView.image = MediaImageLoader.displayImage(for: item, url: url) ?? UIImage(systemName: "photo")
    }
}

enum MediaImageLoader {
    static func displayImage(for item: ImportedMedia, url: URL) -> UIImage? {
        if item.mimeType.lowercased().contains("gif"),
           let data = try? Data(contentsOf: url),
           let animated = UIImage.gifImage(data: data) {
            return animated
        }

        if let image = UIImage(contentsOfFile: url.path) {
            return image
        }

        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            return image
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    static func thumbnailImage(for item: ImportedMedia, url: URL) -> UIImage? {
        guard item.mediaKind == .image else { return nil }
        return displayImage(for: item, url: url)
    }
}

private extension UIImage {
    static func gifImage(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            return UIImage(data: data)
        }

        var images: [UIImage] = []
        var totalDuration: Double = 0

        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }
            let duration = UIImage.frameDuration(source: source, index: index)
            totalDuration += duration
            images.append(UIImage(cgImage: cgImage))
        }

        return UIImage.animatedImage(with: images, duration: totalDuration)
    }

    static func frameDuration(source: CGImageSource, index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }

        let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
        let duration = unclamped ?? clamped ?? 0.1
        return duration < 0.02 ? 0.1 : duration
    }
}
