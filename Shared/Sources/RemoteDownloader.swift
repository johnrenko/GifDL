import Foundation

protocol RemoteDownloading {
    func download(from url: URL) async throws -> URL
}

struct RemoteDownloader: RemoteDownloading {
    func download(from url: URL) async throws -> URL {
        let request = FetchServiceRequestFactory.downloadRequest(url: url)
        let (tempURL, _) = try await URLSession.shared.download(for: request)
        return tempURL
    }
}
