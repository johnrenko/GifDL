import Foundation

struct DiagnosticsSnapshot {
    let pendingImportCount: Int
    let recentLogLines: [String]
}

final class DiagnosticsLogger {
    private let configuration: AppConfiguration
    private let fileManager: FileManager

    init(configuration: AppConfiguration, fileManager: FileManager = .default) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        guard let url = logFileURL() else { return }

        do {
            if !fileManager.fileExists(atPath: url.path()) {
                try Data().write(to: url, options: .atomic)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            return
        }
    }

    func loadSnapshot() -> DiagnosticsSnapshot {
        let pendingImportCount = (try? SharedImportStore(configuration: configuration, fileManager: fileManager).loadAll().count) ?? 0
        guard let url = logFileURL(),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return DiagnosticsSnapshot(pendingImportCount: pendingImportCount, recentLogLines: [])
        }
        let lines = text.split(separator: "\n").suffix(8).map(String.init)
        return DiagnosticsSnapshot(pendingImportCount: pendingImportCount, recentLogLines: lines)
    }

    private func logFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: configuration.appGroupID)?
            .appending(path: "diagnostics.log")
    }
}
