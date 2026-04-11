import Foundation

enum PendingImportKind: String, Codable {
    case localFile
    case resolvedRemoteMedia
    case remoteFetchJob
    case failedURL
}

struct PendingImport: Codable, Identifiable, Equatable {
    let id: UUID
    var createdAt: Date
    var sourceType: MediaSourceType
    var originalSource: String
    var kind: PendingImportKind
    var sharedFilePath: String?
    var mimeType: String?
    var fetchJobID: String?
    var remoteMediaURL: String?
    var suggestedFilename: String?
    var errorMessage: String?
}
