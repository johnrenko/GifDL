import AVFoundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct MediaThumbnailView: View {
    let item: ImportedMedia

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.12))

            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.mediaKind == .video ? "video.fill" : "photo.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var thumbnailImage: UIImage? {
        guard let fileURL = item.resolvedLocalFileURL else {
            return nil
        }

        switch item.mediaKind {
        case .video:
            return videoThumbnail(url: fileURL)
        case .image:
            return imageThumbnail(url: fileURL)
        }
    }

    private func imageThumbnail(url: URL) -> UIImage? {
        if let image = MediaImageLoader.thumbnailImage(for: item, url: url) {
            return image
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private func videoThumbnail(url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
