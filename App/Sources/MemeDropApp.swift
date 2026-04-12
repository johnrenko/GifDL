import SwiftUI

@main
struct MemeDropApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = LibraryViewModel.live()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                LibraryView(viewModel: viewModel)
            }
            .task {
                await viewModel.refresh()
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1.5))
                    await viewModel.refresh(suppressLogging: true)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task {
                    await viewModel.refresh()
                }
            }
        }
    }
}
