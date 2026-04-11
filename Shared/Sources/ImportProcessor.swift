import Foundation

protocol ImportProcessing {
    func consumeSharedImports() async throws
    func resumeIncompleteImports() async throws
    func retry(itemID: UUID) async throws
}

final class ImportProcessor: ImportProcessing {
    private let store: LibraryStore
    private let sharedImportStore: SharedImportStore
    private let fetchService: FetchServicing
    private let downloader: RemoteDownloading
    private let fileManager: FileManager
    private let diagnostics: DiagnosticsLogger

    init(
        store: LibraryStore,
        sharedImportStore: SharedImportStore,
        fetchService: FetchServicing,
        downloader: RemoteDownloading,
        fileManager: FileManager,
        diagnostics: DiagnosticsLogger
    ) {
        self.store = store
        self.sharedImportStore = sharedImportStore
        self.fetchService = fetchService
        self.downloader = downloader
        self.fileManager = fileManager
        self.diagnostics = diagnostics
    }

    func consumeSharedImports() async throws {
        let imports = try sharedImportStore.consumeAll()
        diagnostics.log("app: consumed \(imports.count) shared import(s)")
        for pending in imports {
            try await process(pending)
        }
    }

    func resumeIncompleteImports() async throws {
        let pendingItems = store.loadAll().filter { item in
            item.status == .pending || item.status == .downloading
        }
        for item in pendingItems {
            try await continueProcessing(item)
        }
    }

    func retry(itemID: UUID) async throws {
        guard var item = store.item(id: itemID) else { return }
        item.status = .pending
        item.errorMessage = nil
        try store.upsert(item)
        try await continueProcessing(item)
    }

    private func process(_ pending: PendingImport) async throws {
        switch pending.kind {
        case .localFile:
            try importLocalFile(pending)
        case .resolvedRemoteMedia, .remoteFetchJob, .failedURL:
            let item = store.importedMedia(from: pending)
            try store.upsert(item)
            try await continueProcessing(item)
        }
    }

    private func importLocalFile(_ pending: PendingImport) throws {
        guard let sourcePath = pending.sharedFilePath else {
            diagnostics.log("app: missing shared file path for pending import \(pending.id)")
            return
        }
        let descriptor = try store.moveSharedFileIntoLibrary(sourcePath: sourcePath, suggestedFilename: pending.suggestedFilename)
        var item = store.importedMedia(from: pending)
        item.localFileURL = persistedFileSystemPath(for: descriptor.url)
        item.mimeType = descriptor.mimeType
        item.fileSize = descriptor.fileSize
        item.duration = descriptor.duration
        item.status = .ready
        try store.upsert(item)
        diagnostics.log("app: imported local file \(descriptor.url.lastPathComponent)")
    }

    private func continueProcessing(_ item: ImportedMedia) async throws {
        if let remoteMediaURL = item.remoteMediaURL {
            diagnostics.log("app: continuing remote media download for \(item.id)")
            try await downloadRemoteMedia(item: item, remoteMediaURL: remoteMediaURL)
            return
        }

        if let fetchJobID = item.fetchJobID {
            diagnostics.log("app: polling fetch job \(fetchJobID)")
            try await resolveJob(item: item, fetchJobID: fetchJobID)
            return
        }

        if item.sourceType == .url,
           let sourceURL = URL(string: item.originalSource),
           item.remoteMediaURL == nil,
           item.fetchJobID == nil {
            let response = try await fetchService.submit(url: sourceURL)
            try await handleResolution(item: item, response: response)
            return
        }

        if item.status == .failed {
            try store.upsert(item)
            diagnostics.log("app: retained failed item \(item.id)")
        }
    }

    private func resolveJob(item: ImportedMedia, fetchJobID: String) async throws {
        var mutableItem = item
        mutableItem.status = .downloading
        try store.upsert(mutableItem)

        for _ in 0..<8 {
            let response = try await fetchService.poll(jobID: fetchJobID)
            if response.status == "pending" {
                try await Task.sleep(for: .seconds(1))
                continue
            }
            try await handleResolution(item: mutableItem, response: response)
            return
        }

        mutableItem.status = .failed
        mutableItem.errorMessage = "The remote fetch job timed out."
        try store.upsert(mutableItem)
    }

    private func handleResolution(item: ImportedMedia, response: FetchResolutionResponse) async throws {
        var mutableItem = item
        mutableItem.mimeType = response.mimeType ?? mutableItem.mimeType
        mutableItem.suggestedFilename = response.filename ?? mutableItem.suggestedFilename

        switch response.status {
        case "ready":
            guard let mediaURL = response.mediaURL else {
                throw FetchServiceError.missingMediaURL
            }
            try await downloadRemoteMedia(item: mutableItem, remoteMediaURL: mediaURL)
        case "pending":
            mutableItem.status = .downloading
            mutableItem.fetchJobID = response.jobID
            try store.upsert(mutableItem)
            if let jobID = response.jobID {
                try await resolveJob(item: mutableItem, fetchJobID: jobID)
            }
        default:
            mutableItem.status = .failed
            mutableItem.errorMessage = response.errorMessage ?? "Unsupported URL."
            try store.upsert(mutableItem)
            diagnostics.log("app: resolution failed for \(item.id) error=\(mutableItem.errorMessage ?? "unknown")")
        }
    }

    private func downloadRemoteMedia(item: ImportedMedia, remoteMediaURL: String) async throws {
        guard let remoteURL = URL(string: remoteMediaURL) else {
            var failed = item
            failed.status = .failed
            failed.errorMessage = "The fetch service returned an invalid media URL."
            try store.upsert(failed)
            return
        }

        var mutableItem = item
        mutableItem.status = .downloading
        mutableItem.remoteMediaURL = remoteMediaURL
        try store.upsert(mutableItem)

        do {
            let tempURL = try await downloader.download(from: remoteURL)
            let descriptor = try store.writeDownloadedFile(tempURL: tempURL, suggestedFilename: item.suggestedFilename ?? remoteURL.lastPathComponent)
            mutableItem.localFileURL = persistedFileSystemPath(for: descriptor.url)
            mutableItem.mimeType = descriptor.mimeType
            mutableItem.fileSize = descriptor.fileSize
            mutableItem.duration = descriptor.duration
            mutableItem.status = .ready
            mutableItem.fetchJobID = nil
            mutableItem.remoteMediaURL = remoteMediaURL
            mutableItem.errorMessage = nil
            try store.upsert(mutableItem)
            diagnostics.log("app: downloaded remote media \(descriptor.url.lastPathComponent)")
        } catch {
            mutableItem.status = .failed
            mutableItem.errorMessage = error.localizedDescription
            try store.upsert(mutableItem)
            diagnostics.log("app: download failed for \(item.id) error=\(error.localizedDescription)")
        }
    }
}
