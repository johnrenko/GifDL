import Foundation
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var items: [ImportedMedia] = []
    @Published var selectedItem: ImportedMedia?
    @Published var errorMessage: String?
    @Published var pendingImportCount = 0
    @Published var recentDiagnostics: [String] = []

    private let store: LibraryStore
    private let sharedImportStore: SharedImportStore
    private let importProcessor: ImportProcessing
    private let diagnostics: DiagnosticsLogger

    init(store: LibraryStore, sharedImportStore: SharedImportStore, importProcessor: ImportProcessing, diagnostics: DiagnosticsLogger) {
        self.store = store
        self.sharedImportStore = sharedImportStore
        self.importProcessor = importProcessor
        self.diagnostics = diagnostics
        self.items = store.loadAll()
        applyDiagnosticsSnapshot()
    }

    static func live() -> LibraryViewModel {
        let configuration = AppConfiguration.default
        let fileManager = FileManager.default
        let readyStore = (try? LibraryStore(configuration: configuration, fileManager: fileManager)) ?? LibraryStore.inMemoryFallback()
        let readyShared: SharedImportStore
        let startupError: String?
        do {
            readyShared = try SharedImportStore(configuration: configuration, fileManager: fileManager)
            startupError = nil
        } catch {
            readyShared = SharedImportStore.unavailable(configuration: configuration, fileManager: fileManager, error: error)
            startupError = error.localizedDescription
        }
        let processor = ImportProcessor(
            store: readyStore,
            sharedImportStore: readyShared,
            fetchService: FetchService(baseURL: configuration.fetchServiceBaseURL, session: .shared),
            downloader: RemoteDownloader(),
            fileManager: fileManager,
            diagnostics: DiagnosticsLogger(configuration: configuration, fileManager: fileManager)
        )
        let diagnostics = DiagnosticsLogger(configuration: configuration, fileManager: fileManager)
        let viewModel = LibraryViewModel(store: readyStore, sharedImportStore: readyShared, importProcessor: processor, diagnostics: diagnostics)
        viewModel.errorMessage = startupError
        return viewModel
    }

    func refresh() async {
        do {
            diagnostics.log("app: refresh started")
            try await importProcessor.consumeSharedImports()
            try await importProcessor.resumeIncompleteImports()
            items = store.loadAll()
            applyDiagnosticsSnapshot()
        } catch {
            errorMessage = error.localizedDescription
            diagnostics.log("app: refresh failed error=\(error.localizedDescription)")
            applyDiagnosticsSnapshot()
        }
    }

    func delete(_ item: ImportedMedia) {
        do {
            try store.delete(itemID: item.id)
            items = store.loadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retry(_ item: ImportedMedia) async {
        do {
            try await importProcessor.retry(itemID: item.id)
            items = store.loadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyDiagnosticsSnapshot() {
        let snapshot = diagnostics.loadSnapshot()
        pendingImportCount = snapshot.pendingImportCount
        recentDiagnostics = snapshot.recentLogLines
    }
}
