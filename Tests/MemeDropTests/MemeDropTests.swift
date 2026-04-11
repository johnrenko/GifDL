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
}
