import XCTest

final class MemeDropTests: XCTestCase {
    func testImportedMediaFromPendingImportStartsPending() throws {
        let store = try LibraryStore(configuration: .default, fileManager: .default)
        let pending = PendingImport(
            id: UUID(),
            createdAt: Date(),
            sourceType: .url,
            originalSource: "https://example.com/post",
            kind: .remoteFetchJob,
            sharedFilePath: nil,
            mimeType: "video/mp4",
            fetchJobID: "job-1",
            remoteMediaURL: nil,
            suggestedFilename: "clip.mp4",
            errorMessage: nil
        )

        let media = store.importedMedia(from: pending)

        XCTAssertEqual(media.status, .pending)
        XCTAssertEqual(media.fetchJobID, "job-1")
        XCTAssertEqual(media.suggestedFilename, "clip.mp4")
    }

    func testMetadataSummaryIncludesDurationAndSize() {
        let media = ImportedMedia(
            id: UUID(),
            createdAt: Date(),
            sourceType: .file,
            originalSource: "clip.mp4",
            localFileURL: nil,
            thumbnailURL: nil,
            status: .ready,
            mimeType: "video/mp4",
            duration: 2.5,
            fileSize: 2_097_152,
            errorMessage: nil,
            fetchJobID: nil,
            remoteMediaURL: nil,
            suggestedFilename: "clip.mp4"
        )

        XCTAssertNotNil(media.metadataSummary)
        XCTAssertTrue(media.metadataSummary?.contains("2.5s") == true)
        XCTAssertTrue(media.metadataSummary?.contains("MB") == true)
    }

    func testFetchResolutionDecoding() throws {
        let data = """
        {
          "status": "ready",
          "mediaURL": "https://example.com/file.gif",
          "filename": "file.gif",
          "mimeType": "image/gif",
          "jobID": null,
          "errorMessage": null
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(FetchResolutionResponse.self, from: data)

        XCTAssertEqual(decoded.status, "ready")
        XCTAssertEqual(decoded.mediaURL, "https://example.com/file.gif")
        XCTAssertEqual(decoded.filename, "file.gif")
    }

    func testLibraryStoreRoundTripsItemsFromDisk() throws {
        let store = try LibraryStore(configuration: .default, fileManager: .default)
        let item = ImportedMedia(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_713_000_000),
            sourceType: .file,
            originalSource: "shared-file",
            localFileURL: "/tmp/example.jpg",
            thumbnailURL: nil,
            status: .ready,
            mimeType: "image/jpeg",
            duration: nil,
            fileSize: 128,
            errorMessage: nil,
            fetchJobID: nil,
            remoteMediaURL: nil,
            suggestedFilename: "example.jpg"
        )

        try store.upsert(item)

        let reloadedStore = try LibraryStore(configuration: .default, fileManager: .default)
        XCTAssertTrue(reloadedStore.loadAll().contains(where: { $0.id == item.id }))

        try reloadedStore.delete(itemID: item.id)
    }

    func testResolvedLocalFileURLNormalizesEncodedSpaces() {
        let item = ImportedMedia(
            id: UUID(),
            createdAt: Date(),
            sourceType: .file,
            originalSource: "shared-file",
            localFileURL: "/var/mobile/Containers/Data/Application/ABC/Library/Application%20Support/MemeDropLibrary/Media/test.JPG",
            thumbnailURL: nil,
            status: .ready,
            mimeType: "image/jpeg",
            duration: nil,
            fileSize: nil,
            errorMessage: nil,
            fetchJobID: nil,
            remoteMediaURL: nil,
            suggestedFilename: "test.JPG"
        )

        XCTAssertEqual(
            item.resolvedLocalFileURL?.path(percentEncoded: false),
            "/var/mobile/Containers/Data/Application/ABC/Library/Application Support/MemeDropLibrary/Media/test.JPG"
        )
    }

    func testRetryResubmitsOriginalURLAndClearsStaleCobaltState() async throws {
        let store = try LibraryStore(configuration: .default, fileManager: .default)
        let item = ImportedMedia(
            id: UUID(),
            createdAt: Date(),
            sourceType: .url,
            originalSource: "https://example.com/post/123",
            localFileURL: nil,
            thumbnailURL: nil,
            status: .failed,
            mimeType: "application/octet-stream",
            duration: nil,
            fileSize: nil,
            errorMessage: "Unable to reach cobalt",
            fetchJobID: "stale-job",
            remoteMediaURL: "https://cdn.example.com/stale.mp4",
            suggestedFilename: "clip.mp4"
        )
        try store.upsert(item)

        let fetchService = MockFetchService(
            submitHandler: { url in
                XCTAssertEqual(url.absoluteString, "https://example.com/post/123")
                return FetchResolutionResponse(
                    status: "failed",
                    mediaURL: nil,
                    filename: nil,
                    mimeType: nil,
                    jobID: nil,
                    errorMessage: "Still unavailable"
                )
            },
            pollHandler: { _ in
                XCTFail("Retry should submit the saved original URL instead of polling a stale job.")
                return FetchResolutionResponse(status: "failed", mediaURL: nil, filename: nil, mimeType: nil, jobID: nil, errorMessage: nil)
            }
        )
        let processor = ImportProcessor(
            store: store,
            sharedImportStore: SharedImportStore.unavailable(
                configuration: .default,
                fileManager: .default,
                error: NSError(domain: "Tests", code: 1)
            ),
            fetchService: fetchService,
            downloader: MockDownloader(),
            fileManager: .default,
            diagnostics: DiagnosticsLogger(configuration: .default, fileManager: .default)
        )

        try await processor.retry(itemID: item.id)

        let retried = try XCTUnwrap(store.item(id: item.id))
        XCTAssertEqual(fetchService.submittedURLs, ["https://example.com/post/123"])
        XCTAssertEqual(retried.status, .failed)
        XCTAssertEqual(retried.errorMessage, "Still unavailable")
        XCTAssertNil(retried.fetchJobID)
        XCTAssertNil(retried.remoteMediaURL)

        try store.delete(itemID: item.id)
    }

    func testConcurrentRetryOnlyProcessesItemOnce() async throws {
        let store = try LibraryStore(configuration: .default, fileManager: .default)
        let item = ImportedMedia(
            id: UUID(),
            createdAt: Date(),
            sourceType: .url,
            originalSource: "https://example.com/post/456",
            localFileURL: nil,
            thumbnailURL: nil,
            status: .failed,
            mimeType: "application/octet-stream",
            duration: nil,
            fileSize: nil,
            errorMessage: "Unable to reach cobalt",
            fetchJobID: nil,
            remoteMediaURL: nil,
            suggestedFilename: "clip.mp4"
        )
        try store.upsert(item)

        let fetchService = MockFetchService(
            submitHandler: { _ in
                try await Task.sleep(for: .milliseconds(150))
                return FetchResolutionResponse(
                    status: "failed",
                    mediaURL: nil,
                    filename: nil,
                    mimeType: nil,
                    jobID: nil,
                    errorMessage: "Still unavailable"
                )
            },
            pollHandler: { _ in
                XCTFail("Concurrent retry should not fall back to polling.")
                return FetchResolutionResponse(status: "failed", mediaURL: nil, filename: nil, mimeType: nil, jobID: nil, errorMessage: nil)
            }
        )
        let processor = ImportProcessor(
            store: store,
            sharedImportStore: SharedImportStore.unavailable(
                configuration: .default,
                fileManager: .default,
                error: NSError(domain: "Tests", code: 2)
            ),
            fetchService: fetchService,
            downloader: MockDownloader(),
            fileManager: .default,
            diagnostics: DiagnosticsLogger(configuration: .default, fileManager: .default)
        )

        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await processor.retry(itemID: item.id) }
            group.addTask { try? await processor.retry(itemID: item.id) }
        }

        XCTAssertEqual(fetchService.submittedURLs, ["https://example.com/post/456"])
        let retried = try XCTUnwrap(store.item(id: item.id))
        XCTAssertEqual(retried.status, .failed)
        XCTAssertEqual(retried.errorMessage, "Still unavailable")

        try store.delete(itemID: item.id)
    }
}

private final class MockFetchService: FetchServicing {
    private let submitHandler: (URL) async throws -> FetchResolutionResponse
    private let pollHandler: (String) async throws -> FetchResolutionResponse
    private let lock = NSLock()
    private var submittedURLStorage: [String] = []

    var submittedURLs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return submittedURLStorage
    }

    init(
        submitHandler: @escaping (URL) async throws -> FetchResolutionResponse,
        pollHandler: @escaping (String) async throws -> FetchResolutionResponse
    ) {
        self.submitHandler = submitHandler
        self.pollHandler = pollHandler
    }

    func submit(url: URL) async throws -> FetchResolutionResponse {
        lock.lock()
        submittedURLStorage.append(url.absoluteString)
        lock.unlock()
        return try await submitHandler(url)
    }

    func poll(jobID: String) async throws -> FetchResolutionResponse {
        try await pollHandler(jobID)
    }
}

private struct MockDownloader: RemoteDownloading {
    func download(from url: URL) async throws -> URL {
        XCTFail("Retrying a failed Cobalt resolution should not start a direct download before re-resolving the original link.")
        return url
    }
}
