import AVFoundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct MediaThumbnailView: View {
    let item: ImportedMedia
    @State private var thumbnailImage: UIImage?

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
        .task(id: item.id) {
            thumbnailImage = await loadThumbnailImage()
        }
    }

    private func loadThumbnailImage() async -> UIImage? {
        guard let fileURL = item.resolvedLocalFileURL else {
            return nil
        }

        switch item.mediaKind {
        case .video:
            return await videoThumbnail(url: fileURL)
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

    private func videoThumbnail(url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let cgImage = try? await generator.generateCGImage(at: .zero) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

private extension AVAssetImageGenerator {
    func generateCGImage(at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generateCGImageAsynchronously(for: time) { image, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "MediaThumbnailView",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Unable to generate a thumbnail image."]
                        )
                    )
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }
}
