import AVKit
import SwiftUI

struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel

    var body: some View {
        List {
            if viewModel.items.isEmpty {
                Section("Diagnostics") {
                    LabeledContent("Pending imports", value: "\(viewModel.pendingImportCount)")
                    if viewModel.recentDiagnostics.isEmpty {
                        Text("No shared diagnostics yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(viewModel.recentDiagnostics.enumerated()), id: \.offset) { entry in
                            Text(entry.element)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "No Memes Yet",
                    systemImage: "square.and.arrow.down.on.square",
                    description: Text("Share a GIF, short video, or supported post URL into MemeDrop to build your library.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.items) { item in
                    MediaRow(item: item, isRetrying: viewModel.isRetrying(item)) {
                        Task {
                            await viewModel.retry(item)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedItem = item
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.delete(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        if item.canRetry {
                            Button {
                                Task {
                                    await viewModel.retry(item)
                                }
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                            .tint(.orange)
                            .disabled(viewModel.isRetrying(item))
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("MemeDrop")
        .safeAreaInset(edge: .top) {
            if let message = viewModel.errorMessage, message.contains("App Group container is unavailable") {
                Text("App Group is unavailable. Check Signing & Capabilities for both the app and the share extension.")
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.18))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.refresh()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .sheet(item: $viewModel.selectedItem) { item in
            MediaDetailView(item: item) {
                viewModel.delete(item)
                viewModel.selectedItem = nil
            }
        }
        .alert("Import Error", isPresented: Binding(get: {
            viewModel.errorMessage != nil
        }, set: { newValue in
            if !newValue {
                viewModel.errorMessage = nil
            }
        })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

private struct MediaRow: View {
    let item: ImportedMedia
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            MediaThumbnailView(item: item)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                Text(item.sourceLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    StatusBadge(status: item.status)
                    if let summary = item.metadataSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if item.canRetry {
                    if let errorMessage = item.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Button(action: onRetry) {
                        if isRetrying {
                            Label("Retrying…", systemImage: "hourglass")
                                .font(.caption.weight(.semibold))
                        } else {
                            Label("Retry Import", systemImage: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(isRetrying)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}

private struct StatusBadge: View {
    let status: ImportStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.16), in: Capsule())
            .foregroundStyle(status.color)
    }
}
