import UIKit
import UniformTypeIdentifiers

enum MediaClipboard {
    static func copy(item: ImportedMedia, from url: URL) -> String {
        let pasteboard = UIPasteboard.general
        let fileData = try? Data(contentsOf: url)
        let preferredType = preferredMediaUTType(for: item, url: url)

        if let fileData, let preferredType {
            pasteboard.setData(fileData, forPasteboardType: preferredType.identifier)

            if preferredType.conforms(to: .gif) {
                return "Copied GIF to clipboard"
            } else if preferredType.conforms(to: .image) {
                return "Copied image to clipboard"
            } else if preferredType.conforms(to: .movie) || preferredType.conforms(to: .audiovisualContent) {
                return "Copied video to clipboard"
            } else {
                return "Copied media to clipboard"
            }
        }

        if item.mediaKind == .image,
           let fileData,
           let image = UIImage(data: fileData) {
            pasteboard.image = image
            return "Copied image to clipboard"
        }

        if let provider = NSItemProvider(contentsOf: url) {
            pasteboard.itemProviders = [provider]
            return "Copied media to clipboard"
        }

        return "Unable to copy this media"
    }

    private static func preferredMediaUTType(for item: ImportedMedia, url: URL) -> UTType? {
        if item.mimeType.isEmpty == false,
           let mimeType = UTType(mimeType: item.mimeType) {
            return mimeType
        }

        if let typeFromExtension = UTType(filenameExtension: url.pathExtension) {
            return typeFromExtension
        }

        return item.mediaKind == .video ? .mpeg4Movie : .image
    }
}
