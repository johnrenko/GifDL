import Foundation

protocol RemoteDownloading {
    func download(from url: URL) async throws -> URL
}

struct RemoteDownloader: RemoteDownloading {
    func download(from url: URL) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        return tempURL
    }
}
