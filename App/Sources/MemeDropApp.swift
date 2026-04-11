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
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task {
                    await viewModel.refresh()
                }
            }
        }
    }
}
