import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum MediaSourceType: String, Codable {
    case file
    case url
}

enum ImportStatus: String, Codable {
    case pending
    case downloading
    case ready
    case failed

    var label: String {
        switch self {
        case .pending: "Pending"
        case .downloading: "Downloading"
        case .ready: "Ready"
        case .failed: "Failed"
        }
    }
}

enum MediaKind: String, Codable {
    case image
    case video
}

struct ImportedMedia: Codable, Identifiable, Equatable {
    let id: UUID
    var createdAt: Date
    var sourceType: MediaSourceType
    var originalSource: String
    var localFileURL: String?
    var thumbnailURL: String?
    var status: ImportStatus
    var mimeType: String
    var duration: Double?
    var fileSize: Int64?
    var errorMessage: String?
    var fetchJobID: String?
    var remoteMediaURL: String?
    var suggestedFilename: String?

    var resolvedLocalFileURL: URL? {
        guard let localFileURL else { return nil }
        return URL(fileURLWithPath: normalizedFileSystemPath(localFileURL))
    }

    var displayTitle: String {
        if let localFileURL {
            return URL(fileURLWithPath: localFileURL).lastPathComponent
        }
        if let suggestedFilename, !suggestedFilename.isEmpty {
            return suggestedFilename
        }
        return "Imported Meme"
    }

    var sourceLabel: String {
        guard let url = URL(string: originalSource), let host = url.host(percentEncoded: false) else {
            return sourceType == .file ? "Shared media file" : originalSource
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    var mediaKind: MediaKind {
        if mimeType.lowercased().contains("video") {
            return .video
        }

        if let fileURL = resolvedLocalFileURL,
           let type = UTType(filenameExtension: fileURL.pathExtension),
           type.conforms(to: .movie) {
            return .video
        }
        return .image
    }

    var metadataSummary: String? {
        var parts: [String] = []
        if let duration {
            parts.append(String(format: "%.1fs", duration))
        }
        if let fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}

extension ImportStatus {
    var color: Color {
        switch self {
        case .pending: .blue
        case .downloading: .orange
        case .ready: .green
        case .failed: .red
        }
    }
}
