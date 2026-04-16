import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum StorageError: LocalizedError {
    case appGroupUnavailable
    case missingFile

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "The App Group container is unavailable. Check the configured entitlements."
        case .missingFile:
            return "The shared media file no longer exists."
        }
    }
}

func normalizedFileSystemPath(_ rawPath: String) -> String {
    let normalized = rawPath.removingPercentEncoding ?? rawPath
    return normalized.replacingOccurrences(of: "file://", with: "")
}

func persistedFileSystemPath(for url: URL) -> String {
    url.path(percentEncoded: false)
}

struct SharedPaths {
    let appGroupID: String
    let fileManager: FileManager

    func sharedContainerURL() throws -> URL {
        guard let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            throw StorageError.appGroupUnavailable
        }
        return url
    }

    func sharedInboxURL() throws -> URL {
        let url = try sharedContainerURL().appending(path: "Inbox", directoryHint: .isDirectory)
        try ensureDirectory(url)
        return url
    }

    func appLibraryURL() throws -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appending(path: "MemeDropLibrary", directoryHint: .isDirectory)
        try ensureDirectory(url)
        return url
    }

    func sharedImportsIndexURL() throws -> URL {
        try sharedContainerURL().appending(path: "pending-imports.json")
    }

    func appLibraryIndexURL() throws -> URL {
        try appLibraryURL().appending(path: "library-index.json")
    }

    private func ensureDirectory(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path()) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

final class SharedImportStore {
    private let paths: SharedPaths
    private let fileManager: FileManager
    private let storageURL: URL?
    private let unavailableError: Error?

    init(configuration: AppConfiguration, fileManager: FileManager) throws {
        self.paths = SharedPaths(appGroupID: configuration.appGroupID, fileManager: fileManager)
        self.fileManager = fileManager
        self.storageURL = try paths.sharedImportsIndexURL()
        self.unavailableError = nil
    }

    private init(paths: SharedPaths, fileManager: FileManager, storageURL: URL?, unavailableError: Error?) {
        self.paths = paths
        self.fileManager = fileManager
        self.storageURL = storageURL
        self.unavailableError = unavailableError
    }

    static func unavailable(configuration: AppConfiguration, fileManager: FileManager, error: Error) -> SharedImportStore {
        SharedImportStore(
            paths: SharedPaths(appGroupID: configuration.appGroupID, fileManager: fileManager),
            fileManager: fileManager,
            storageURL: nil,
            unavailableError: error
        )
    }

    func append(_ pendingImport: PendingImport) throws {
        try throwIfUnavailable()
        var imports = loadAll()
        imports.append(pendingImport)
        try save(imports)
    }

    func loadAll() -> [PendingImport] {
        if unavailableError != nil {
            return []
        }
        guard let storageURL else { return [] }
        guard let data = try? Data(contentsOf: storageURL) else {
            return []
        }
        return (try? JSONDecoder.pretty.decode([PendingImport].self, from: data)) ?? []
    }

    func consumeAll() throws -> [PendingImport] {
        try throwIfUnavailable()
        let imports = loadAll()
        try save([])
        return imports
    }

    func sharedInboxURL() throws -> URL {
        try throwIfUnavailable()
        return try paths.sharedInboxURL()
    }

    private func save(_ imports: [PendingImport]) throws {
        try throwIfUnavailable()
        guard let storageURL else { return }
        let data = try JSONEncoder.pretty.encode(imports)
        try data.write(to: storageURL, options: .atomic)
    }

    private func throwIfUnavailable() throws {
        if let unavailableError {
            throw unavailableError
        }
    }
}

final class LibraryStore {
    private let paths: SharedPaths
    private let fileManager: FileManager
    private let indexURL: URL?
    private let mediaDirectoryURL: URL?
    private var inMemoryItems: [ImportedMedia] = []

    init(configuration: AppConfiguration, fileManager: FileManager) throws {
        self.paths = SharedPaths(appGroupID: configuration.appGroupID, fileManager: fileManager)
        self.fileManager = fileManager
        self.indexURL = try? paths.appLibraryIndexURL()
        self.mediaDirectoryURL = try? paths.appLibraryURL().appending(path: "Media", directoryHint: .isDirectory)
        if let mediaDirectoryURL, !fileManager.fileExists(atPath: mediaDirectoryURL.path()) {
            try fileManager.createDirectory(at: mediaDirectoryURL, withIntermediateDirectories: true)
        }
    }

    static func inMemoryFallback() -> LibraryStore {
        try! LibraryStore(configuration: AppConfiguration.default, fileManager: .default)
    }

    func loadAll() -> [ImportedMedia] {
        let items: [ImportedMedia]
        if let indexURL, let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder.pretty.decode([ImportedMedia].self, from: data) {
            items = decoded
        } else {
            items = inMemoryItems
        }
        return items.sorted(by: { $0.createdAt > $1.createdAt })
    }

    func upsert(_ item: ImportedMedia) throws {
        var items = loadAll()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        try save(items)
    }

    func item(id: UUID) -> ImportedMedia? {
        loadAll().first(where: { $0.id == id })
    }

    func delete(itemID: UUID) throws {
        var items = loadAll()
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        let item = items.remove(at: index)
        if let path = item.localFileURL {
            let normalizedPath = normalizedFileSystemPath(path)
            if fileManager.fileExists(atPath: normalizedPath) {
                try? fileManager.removeItem(at: URL(fileURLWithPath: normalizedPath))
            }
        }
        try save(items)
    }

    func deleteAllVideos() throws {
        let items = loadAll()
        let remainingItems = items.filter { $0.mediaKind != .video }

        for item in items where item.mediaKind == .video {
            guard let path = item.localFileURL else { continue }
            let normalizedPath = normalizedFileSystemPath(path)
            if fileManager.fileExists(atPath: normalizedPath) {
                try? fileManager.removeItem(at: URL(fileURLWithPath: normalizedPath))
            }
        }

        try save(remainingItems)
    }

    func reserveDestinationURL(suggestedFilename: String?) throws -> URL {
        let mediaDirectory = try paths.appLibraryURL().appending(path: "Media", directoryHint: .isDirectory)
        if !fileManager.fileExists(atPath: mediaDirectory.path()) {
            try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        }
        let filename = sanitizedFilename(suggestedFilename ?? "meme-\(UUID().uuidString).bin")
        let uniqueName = uniqueFilename(filename, in: mediaDirectory)
        return mediaDirectory.appending(path: uniqueName)
    }

    func importedMedia(from pending: PendingImport) -> ImportedMedia {
        ImportedMedia(
            id: pending.id,
            createdAt: pending.createdAt,
            sourceType: pending.sourceType,
            originalSource: pending.originalSource,
            localFileURL: nil,
            thumbnailURL: nil,
            status: pending.kind == .failedURL ? .failed : .pending,
            mimeType: pending.mimeType ?? "application/octet-stream",
            duration: nil,
            fileSize: nil,
            errorMessage: pending.errorMessage,
            fetchJobID: pending.fetchJobID,
            remoteMediaURL: pending.remoteMediaURL,
            suggestedFilename: pending.suggestedFilename
        )
    }

    func moveSharedFileIntoLibrary(sourcePath: String, suggestedFilename: String?) async throws -> ImportedMediaFileDescriptor {
        let sourceURL = URL(fileURLWithPath: normalizedFileSystemPath(sourcePath))
        guard fileManager.fileExists(atPath: sourceURL.path()) else {
            throw StorageError.missingFile
        }
        let destinationURL = try reserveDestinationURL(suggestedFilename: suggestedFilename ?? sourceURL.lastPathComponent)
        if fileManager.fileExists(atPath: destinationURL.path()) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        return try await ImportedMediaFileDescriptor(url: destinationURL)
    }

    func writeDownloadedFile(tempURL: URL, suggestedFilename: String?) async throws -> ImportedMediaFileDescriptor {
        let destinationURL = try reserveDestinationURL(suggestedFilename: suggestedFilename ?? tempURL.lastPathComponent)
        if fileManager.fileExists(atPath: destinationURL.path()) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: destinationURL)
        return try await ImportedMediaFileDescriptor(url: destinationURL)
    }

    private func save(_ items: [ImportedMedia]) throws {
        inMemoryItems = items
        guard let indexURL else { return }
        let data = try JSONEncoder.pretty.encode(items)
        try data.write(to: indexURL, options: .atomic)
    }

    private func uniqueFilename(_ filename: String, in directory: URL) -> String {
        let ext = URL(fileURLWithPath: filename).pathExtension
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        var candidate = filename
        var index = 1
        while fileManager.fileExists(atPath: directory.appending(path: candidate).path()) {
            let suffix = "-\(index)"
            candidate = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
            index += 1
        }
        return candidate
    }

    private func sanitizedFilename(_ filename: String) -> String {
        filename.replacingOccurrences(of: "/", with: "-")
    }
}

struct ImportedMediaFileDescriptor {
    let url: URL
    let mimeType: String
    let fileSize: Int64
    let duration: Double?

    init(url: URL) async throws {
        self.url = url
        let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        let type = values.contentType
        self.mimeType = type?.preferredMIMEType ?? "application/octet-stream"
        self.fileSize = Int64(values.fileSize ?? 0)
        if type?.conforms(to: .movie) == true {
            let duration = try await AVURLAsset(url: url).load(.duration)
            self.duration = duration.seconds
        } else {
            self.duration = nil
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var pretty: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
