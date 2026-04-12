import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let configuration = AppConfiguration.default
    private lazy var diagnostics = DiagnosticsLogger(configuration: configuration)
    private var didStartImport = false
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let checkmarkView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .systemBackground

        let stack = UIStackView(arrangedSubviews: [activityIndicator, checkmarkView, statusLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator.startAnimating()
        checkmarkView.tintColor = .systemGreen
        checkmarkView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 42, weight: .bold)
        checkmarkView.isHidden = true

        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = "Saving to MemeDrop..."

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])

        self.view = view
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startImportIfNeeded()
    }

    private func startImportIfNeeded() {
        guard !didStartImport else { return }
        didStartImport = true

        Task {
            do {
                try await handleInputItems()
                await MainActor.run {
                    activityIndicator.stopAnimating()
                    checkmarkView.isHidden = false
                    statusLabel.text = "Saved to MemeDrop. Open the app to share it fast."
                }
                try? await Task.sleep(for: .milliseconds(500))
                extensionContext?.completeRequest(returningItems: [])
            } catch {
                diagnostics.log("extension: direct import failed error=\(error.localizedDescription)")
                await MainActor.run {
                    activityIndicator.stopAnimating()
                    statusLabel.text = error.localizedDescription
                }
                extensionContext?.cancelRequest(withError: error)
            }
        }
    }

    private func handleInputItems() async throws {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            diagnostics.log("extension: no input items")
            return
        }
        diagnostics.log("extension: received \(items.count) item(s)")

        let fileManager = FileManager.default
        let sharedStore = try SharedImportStore(configuration: configuration, fileManager: fileManager)
        let fetchService = FetchService(baseURL: configuration.fetchServiceBaseURL, session: .shared)

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.gif.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    diagnostics.log("extension: handling media provider \(provider.registeredTypeIdentifiers)")
                    try await handleFile(provider: provider, sharedStore: sharedStore)
                    continue
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    diagnostics.log("extension: handling URL provider \(provider.registeredTypeIdentifiers)")
                    try await handleURL(provider: provider, sharedStore: sharedStore, fetchService: fetchService)
                }
            }
        }
    }

    private func handleFile(provider: NSItemProvider, sharedStore: SharedImportStore) async throws {
        let inboxURL = try sharedStore.sharedInboxURL()
        let candidateTypes = orderedCandidateTypes(for: provider)

        var storedFile: SharedMediaFile?
        var lastError: Error?

        for candidateType in candidateTypes {
            diagnostics.log("extension: handleFile preferredType=\(candidateType)")
            do {
                storedFile = try await provider.persistSharedMedia(preferredType: candidateType, inboxURL: inboxURL)
                break
            } catch {
                lastError = error
                diagnostics.log("extension: persistSharedMedia failed type=\(candidateType) error=\(error.localizedDescription)")
            }
        }

        guard let storedFile else {
            throw lastError ?? NSError(domain: "ShareExtension", code: -7, userInfo: [NSLocalizedDescriptionKey: "Unable to read the shared media item."])
        }

        let pending = PendingImport(
            id: UUID(),
            createdAt: Date(),
            sourceType: .file,
            originalSource: storedFile.originalSource,
            kind: .localFile,
            sharedFilePath: persistedFileSystemPath(for: storedFile.destinationURL),
            mimeType: storedFile.mimeType,
            fetchJobID: nil,
            remoteMediaURL: nil,
            suggestedFilename: storedFile.suggestedFilename,
            errorMessage: nil
        )
        do {
            try sharedStore.append(pending)
        } catch {
            diagnostics.log("extension: append failed error=\(error.localizedDescription)")
            throw error
        }
        diagnostics.log("extension: appended local file \(storedFile.suggestedFilename)")
    }

    private func orderedCandidateTypes(for provider: NSItemProvider) -> [String] {
        var candidates: [String] = []

        func append(_ identifier: String) {
            if provider.hasItemConformingToTypeIdentifier(identifier), !candidates.contains(identifier) {
                candidates.append(identifier)
            }
        }

        for identifier in provider.registeredTypeIdentifiers {
            guard let type = UTType(identifier),
                  type.conforms(to: .image) || type.conforms(to: .movie) || type.conforms(to: .gif) || type.conforms(to: .fileURL) else {
                continue
            }
            append(identifier)
        }

        append(UTType.movie.identifier)
        append(UTType.gif.identifier)
        append(UTType.image.identifier)
        append(UTType.fileURL.identifier)

        if candidates.isEmpty {
            candidates.append(UTType.fileURL.identifier)
        }

        return candidates
    }

    private func handleURL(provider: NSItemProvider, sharedStore: SharedImportStore, fetchService: FetchService) async throws {
        let sourceURL = try await provider.loadURL()
        let response: FetchResolutionResponse
        do {
            response = try await fetchService.submit(url: sourceURL)
        } catch {
            let failed = PendingImport(
                id: UUID(),
                createdAt: Date(),
                sourceType: .url,
                originalSource: sourceURL.absoluteString,
                kind: .failedURL,
                sharedFilePath: nil,
                mimeType: nil,
                fetchJobID: nil,
                remoteMediaURL: nil,
                suggestedFilename: nil,
                errorMessage: error.localizedDescription
            )
            try sharedStore.append(failed)
            diagnostics.log("extension: URL submit failed \(sourceURL.absoluteString) error=\(error.localizedDescription)")
            return
        }

        let kind: PendingImportKind
        switch response.status {
        case "ready":
            kind = .resolvedRemoteMedia
        case "pending":
            kind = .remoteFetchJob
        default:
            kind = .failedURL
        }

        let pending = PendingImport(
            id: UUID(),
            createdAt: Date(),
            sourceType: .url,
            originalSource: sourceURL.absoluteString,
            kind: kind,
            sharedFilePath: nil,
            mimeType: response.mimeType,
            fetchJobID: response.jobID,
            remoteMediaURL: response.mediaURL,
            suggestedFilename: response.filename,
            errorMessage: response.errorMessage
        )
        try sharedStore.append(pending)
        diagnostics.log("extension: appended URL import status=\(response.status) source=\(sourceURL.absoluteString)")
    }
}

private struct SharedMediaFile {
    let destinationURL: URL
    let originalSource: String
    let suggestedFilename: String
    let mimeType: String?
}

private extension NSItemProvider {
    func loadFileRepresentation(forTypeIdentifier typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: NSError(domain: "ShareExtension", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing shared file URL."]))
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }

    func loadURL() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }
                continuation.resume(throwing: NSError(domain: "ShareExtension", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing shared URL value."]))
            }
        }
    }

    func loadItem(forTypeIdentifier typeIdentifier: String) async throws -> NSSecureCoding {
        try await withCheckedThrowingContinuation { continuation in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let item = item as? NSSecureCoding else {
                    continuation.resume(throwing: NSError(domain: "ShareExtension", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unsupported shared item payload."]))
                    return
                }
                continuation.resume(returning: item)
            }
        }
    }

    func persistSharedMedia(preferredType: String, inboxURL: URL) async throws -> SharedMediaFile {
        if preferredType != UTType.fileURL.identifier,
           let receivedURL = try? await loadFileRepresentation(forTypeIdentifier: preferredType) {
            let fileExtension = receivedURL.pathExtension.isEmpty ? fallbackFileExtension(for: preferredType) : receivedURL.pathExtension
            let filename = receivedURL.lastPathComponent.isEmpty ? "\(UUID().uuidString).\(fileExtension)" : receivedURL.lastPathComponent
            let destinationURL = inboxURL.appending(path: uniqueSharedFilename(filename, in: inboxURL))
            if FileManager.default.fileExists(atPath: destinationURL.path()) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: receivedURL, to: destinationURL)
            return SharedMediaFile(
                destinationURL: destinationURL,
                originalSource: receivedURL.lastPathComponent,
                suggestedFilename: destinationURL.lastPathComponent,
                mimeType: UTType(filenameExtension: destinationURL.pathExtension)?.preferredMIMEType ?? UTType(preferredType)?.preferredMIMEType
            )
        }

        let item = try await loadItem(forTypeIdentifier: preferredType)
        let result: SharedMediaFile

        switch item {
        case let url as URL:
            guard FileManager.default.fileExists(atPath: url.path()) else {
                throw NSError(domain: "ShareExtension", code: -6, userInfo: [NSLocalizedDescriptionKey: "The shared file URL does not exist anymore."])
            }
            let fileExtension = url.pathExtension.isEmpty ? fallbackFileExtension(for: preferredType) : url.pathExtension
            let filename = url.lastPathComponent.isEmpty ? "\(UUID().uuidString).\(fileExtension)" : url.lastPathComponent
            let destinationURL = inboxURL.appending(path: uniqueSharedFilename(filename, in: inboxURL))
            try FileManager.default.copyItem(at: url, to: destinationURL)
            result = SharedMediaFile(
                destinationURL: destinationURL,
                originalSource: url.lastPathComponent,
                suggestedFilename: destinationURL.lastPathComponent,
                mimeType: UTType(filenameExtension: destinationURL.pathExtension)?.preferredMIMEType ?? UTType(preferredType)?.preferredMIMEType
            )
        case let data as Data:
            let fileExtension = fallbackFileExtension(for: preferredType)
            let filename = uniqueSharedFilename("\(UUID().uuidString).\(fileExtension)", in: inboxURL)
            let destinationURL = inboxURL.appending(path: filename)
            try data.write(to: destinationURL, options: .atomic)
            result = SharedMediaFile(
                destinationURL: destinationURL,
                originalSource: filename,
                suggestedFilename: filename,
                mimeType: UTType(filenameExtension: fileExtension)?.preferredMIMEType ?? UTType(preferredType)?.preferredMIMEType
            )
        case let image as UIImage:
            let imageData = image.pngData() ?? image.jpegData(compressionQuality: 0.95)
            guard let imageData else {
                throw NSError(domain: "ShareExtension", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unable to encode the shared image."])
            }
            let fileExtension = image.pngData() != nil ? "png" : "jpg"
            let filename = uniqueSharedFilename("\(UUID().uuidString).\(fileExtension)", in: inboxURL)
            let destinationURL = inboxURL.appending(path: filename)
            try imageData.write(to: destinationURL, options: .atomic)
            result = SharedMediaFile(
                destinationURL: destinationURL,
                originalSource: filename,
                suggestedFilename: filename,
                mimeType: UTType(filenameExtension: fileExtension)?.preferredMIMEType
            )
        default:
            throw NSError(domain: "ShareExtension", code: -5, userInfo: [NSLocalizedDescriptionKey: "Unsupported shared media type."])
        }

        return result
    }

    private func fallbackFileExtension(for typeIdentifier: String) -> String {
        guard let type = UTType(typeIdentifier) else {
            return "bin"
        }
        if type.conforms(to: .gif) {
            return "gif"
        }
        if type.conforms(to: .png) {
            return "png"
        }
        if type.conforms(to: .jpeg) {
            return "jpg"
        }
        if type.conforms(to: .image) {
            return "png"
        }
        if type.conforms(to: .movie) {
            return "mov"
        }
        return "bin"
    }

    private func uniqueSharedFilename(_ filename: String, in directory: URL) -> String {
        let fileManager = FileManager.default
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
}
