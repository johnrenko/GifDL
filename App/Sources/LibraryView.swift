import SwiftUI

private enum LibraryMetrics {
    static let cardCornerRadius: CGFloat = 18
    static let thumbnailCornerRadius: CGFloat = 14
    static let controlMinHeight: CGFloat = 44
}

struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel

    @State private var selectedFilter: LibraryFilter = .all
    @State private var shareItem: ImportedMedia?
    @State private var isShowingDeleteVideosConfirmation = false

    var body: some View {
        GeometryReader { geometry in
            let layout = LibraryLayout(width: geometry.size.width)

            ScrollView {
                VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                    if viewModel.pendingImportCount > 0 {
                        LibraryStatusStrip(
                            pendingImportCount: viewModel.pendingImportCount,
                            itemCount: viewModel.items.count,
                            layout: layout
                        )
                    }

                    FilterStrip(selectedFilter: $selectedFilter, layout: layout)

                    if filteredItems.isEmpty {
                        EmptyLibraryState(
                            selectedFilter: selectedFilter,
                            pendingImportCount: viewModel.pendingImportCount,
                            diagnostics: viewModel.recentDiagnostics,
                            layout: layout
                        )
                    } else {
                        LazyVStack(alignment: .leading, spacing: layout.sectionSpacing) {
                            ForEach(sectionedItems) { section in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(section.title)
                                            .font(.headline.weight(.semibold))
                                        Text("\(section.items.count)")
                                            .font(.caption.weight(.semibold))
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }

                                    LazyVGrid(columns: layout.columns, spacing: layout.gridSpacing) {
                                        ForEach(section.items) { item in
                                            MediaCard(
                                                item: item,
                                                isRetrying: viewModel.isRetrying(item),
                                                layout: layout.cardLayout,
                                                onOpen: {
                                                    viewModel.selectedItem = item
                                                },
                                                onRetry: {
                                                    Task {
                                                        await viewModel.retry(item)
                                                    }
                                                },
                                                onDelete: {
                                                    viewModel.delete(item)
                                                },
                                                onShare: {
                                                    shareItem = item
                                                }
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: layout.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("MemeDrop")
        .safeAreaInset(edge: .top) {
            if let message = viewModel.errorMessage, message.contains("App Group container is unavailable") {
                Text("App Group is unavailable. Check Signing & Capabilities for both the app and the share extension.")
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task {
                            await viewModel.refresh()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    if videoCount > 0 {
                        Button(role: .destructive) {
                            isShowingDeleteVideosConfirmation = true
                        } label: {
                            Label("Delete All Videos", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $viewModel.selectedItem) { item in
            MediaDetailView(item: item) {
                viewModel.delete(item)
                viewModel.selectedItem = nil
            }
        }
        .sheet(item: $shareItem) { item in
            if let url = item.resolvedLocalFileURL {
                ActivityViewController(activityItems: [url])
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
        .confirmationDialog(
            "Delete all videos?",
            isPresented: $isShowingDeleteVideosConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All Videos", role: .destructive) {
                viewModel.deleteAllVideos()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove \(videoCount) video\(videoCount == 1 ? "" : "s") from your library.")
        }
    }

    private var filteredItems: [ImportedMedia] {
        viewModel.items.filter(selectedFilter.matches)
    }

    private var videoCount: Int {
        viewModel.items.filter { $0.mediaKind == .video }.count
    }

    private var sectionedItems: [LibrarySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredItems) { item -> String in
            if item.status == .ready, item.isRecent {
                return "Ready Now"
            }
            if calendar.isDateInToday(item.createdAt) {
                return "Today"
            }
            if let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date()),
               item.createdAt >= oneWeekAgo {
                return "This Week"
            }
            return "Earlier"
        }

        let order = ["Ready Now", "Today", "This Week", "Earlier"]
        return order.compactMap { title in
            guard let items = grouped[title], !items.isEmpty else { return nil }
            return LibrarySection(title: title, items: items)
        }
    }
}

private struct LibraryStatusStrip: View {
    let pendingImportCount: Int
    let itemCount: Int
    let layout: LibraryLayout

    var body: some View {
        Group {
            if layout.isCompact {
                VStack(alignment: .leading, spacing: 10) {
                    statusText
                    countBlock(alignment: .leading)
                }
            } else {
                HStack(spacing: 12) {
                    statusText
                    Spacer(minLength: 12)
                    countBlock(alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var title: String { "Import queue active" }

    private var message: String {
        pendingImportCount == 1
            ? "1 item is processing into your library."
            : "\(pendingImportCount) items are processing into your library."
    }

    private var statusText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func countBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text("\(itemCount)")
                .font(.headline.weight(.bold))
                .monospacedDigit()
            Text("saved")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct EmptyLibraryState: View {
    let selectedFilter: LibraryFilter
    let pendingImportCount: Int
    let diagnostics: [String]
    let layout: LibraryLayout

    var body: some View {
        ContentUnavailableView(
            selectedFilter.emptyTitle,
            systemImage: selectedFilter.emptySymbol,
            description: Text(selectedFilter.emptyDescription(pendingImportCount: pendingImportCount))
        )
        .frame(maxWidth: layout.emptyStateMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .overlay(alignment: .bottomTrailing) {
            if !diagnostics.isEmpty {
                NavigationLink {
                    DiagnosticsView(lines: diagnostics)
                } label: {
                    Text("Diagnostics")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 4)
                .padding(.bottom, 4)
            }
        }
    }
}

private struct FilterStrip: View {
    @Binding var selectedFilter: LibraryFilter
    let layout: LibraryLayout

    var body: some View {
        Group {
            if layout.usesWrappedFilters {
                LazyVGrid(columns: layout.filterColumns, alignment: .leading, spacing: 8) {
                    filterButtons
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterButtons
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var filterButtons: some View {
        ForEach(LibraryFilter.allCases) { filter in
            Button {
                selectedFilter = filter
            } label: {
                Text(filter.label)
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: layout.usesWrappedFilters ? .infinity : nil)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(background(for: filter), in: Capsule())
                    .foregroundStyle(foreground(for: filter))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(filter == selectedFilter ? .isSelected : [])
        }
    }

    private func background(for filter: LibraryFilter) -> Color {
        filter == selectedFilter ? Color(.label) : Color(.secondarySystemBackground)
    }

    private func foreground(for filter: LibraryFilter) -> Color {
        filter == selectedFilter ? Color(.systemBackground) : .primary
    }
}

private struct MediaCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: ImportedMedia
    let isRetrying: Bool
    let layout: MediaCardLayout
    let onOpen: () -> Void
    let onRetry: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void

    var body: some View {
        Group {
            if layout == .row {
                rowBody
            } else {
                gridBody
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: LibraryMetrics.cardCornerRadius, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
    }

    private var rowBody: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 10) {
                header(lineLimit: 2)
                metadata
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: LibraryMetrics.cardCornerRadius, style: .continuous))
    }

    private var gridBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            thumbnail
                .frame(height: 172)
                .frame(maxWidth: .infinity)

            header(lineLimit: 1)
            metadata
            footer
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: LibraryMetrics.cardCornerRadius, style: .continuous))
    }

    private var thumbnail: some View {
        ZStack(alignment: .topLeading) {
            MediaThumbnailView(item: item)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 6) {
                StatusBadge(status: item.status)
                if item.isRecent {
                    NewBadge()
                }
                Spacer()
                if item.mediaKind == .video {
                    Image(systemName: "play.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.primary)
                        .padding(7)
                        .background(Color(.systemBackground), in: Circle())
                }
            }
            .padding(8)
        }
        .frame(
            width: layout == .row ? 104 : nil,
            height: layout == .row ? 104 : 172
        )
        .frame(maxWidth: layout == .grid ? .infinity : nil)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: LibraryMetrics.thumbnailCornerRadius, style: .continuous))
    }

    private func header(lineLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayTitle)
                .font(.headline)
                .lineLimit(lineLimit)

            Text(item.sourceLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let summary = item.metadataSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if item.status == .downloading || item.status == .pending {
                ProgressView()
                    .tint(.secondary)
            } else if item.canRetry, let errorMessage = item.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if item.resolvedLocalFileURL != nil {
                Button(action: onShare) {
                    Label("Share", systemImage: "paperplane.fill")
                        .foregroundStyle(primaryActionForeground)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: LibraryMetrics.controlMinHeight)
                }
                .buttonStyle(.borderedProminent)
                .tint(primaryActionBackground)
            } else if item.canRetry {
                Button(action: onRetry) {
                    if isRetrying {
                        Label("Retrying…", systemImage: "hourglass")
                    } else {
                        Label("Retry Import", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(secondaryActionBackground)
                .foregroundStyle(secondaryActionForeground)
                .disabled(isRetrying)
                .frame(minHeight: LibraryMetrics.controlMinHeight)
            }

            Menu {
                Button("Open", action: onOpen)
                if item.canRetry {
                    Button("Retry Import", action: onRetry)
                }
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(width: LibraryMetrics.controlMinHeight, height: LibraryMetrics.controlMinHeight)
                    .background(Color(.tertiarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More actions")
        }
    }

    private var primaryActionBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color(.label)
    }

    private var primaryActionForeground: Color {
        colorScheme == .dark ? .black : Color(.systemBackground)
    }

    private var secondaryActionBackground: Color {
        colorScheme == .dark ? Color(.tertiarySystemBackground) : Color(.secondarySystemBackground)
    }

    private var secondaryActionForeground: Color {
        .primary
    }
}

private struct StatusBadge: View {
    let status: ImportStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(status.color.opacity(0.16), in: Capsule())
            .foregroundStyle(status.color)
    }
}

private struct NewBadge: View {
    var body: some View {
        Text("NEW")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color(.tertiarySystemBackground), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

private struct LibrarySection: Identifiable {
    let title: String
    let items: [ImportedMedia]

    var id: String { title }
}

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case new
    case videos
    case ready
    case failed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .new: "New"
        case .videos: "Videos"
        case .ready: "Ready"
        case .failed: "Failed"
        }
    }

    func matches(_ item: ImportedMedia) -> Bool {
        switch self {
        case .all:
            return true
        case .new:
            return item.isRecent
        case .videos:
            return item.mediaKind == .video
        case .ready:
            return item.status == .ready
        case .failed:
            return item.status == .failed
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: "No Memes Yet"
        case .new: "Nothing New Yet"
        case .videos: "No Videos Yet"
        case .ready: "Nothing Ready Yet"
        case .failed: "No Failed Imports"
        }
    }

    var emptySymbol: String {
        switch self {
        case .all: "square.and.arrow.down.on.square"
        case .new: "sparkles"
        case .videos: "video.fill"
        case .ready: "paperplane.fill"
        case .failed: "checkmark.circle"
        }
    }

    func emptyDescription(pendingImportCount: Int) -> String {
        switch self {
        case .all:
            return pendingImportCount > 0
                ? "Your incoming items will appear here as soon as they finish importing."
                : "Share a GIF, short video, or supported post URL into MemeDrop."
        case .new:
            return "Fresh saves from the last day show up here for fast resend."
        case .videos:
            return "Videos you save into MemeDrop will show up here."
        case .ready:
            return "Ready-to-share memes will appear here as soon as imports finish."
        case .failed:
            return "Good. Failed imports will surface here when they need attention."
        }
    }
}

private struct DiagnosticsView: View {
    let lines: [String]

    var body: some View {
        List {
            ForEach(Array(lines.enumerated()), id: \.offset) { entry in
                Text(entry.element)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum MediaCardLayout {
    case row
    case grid
}

private struct LibraryLayout {
    let width: CGFloat

    var isCompact: Bool { width < 700 }
    var usesWrappedFilters: Bool { width >= 700 }

    var horizontalPadding: CGFloat {
        switch width {
        case ..<700: 16
        case ..<1100: 20
        default: 24
        }
    }

    var gridSpacing: CGFloat { 12 }
    var sectionSpacing: CGFloat { width < 700 ? 18 : 22 }
    var emptyStateMaxWidth: CGFloat { width < 700 ? .infinity : 460 }
    var contentMaxWidth: CGFloat? { width >= 1400 ? 1320 : nil }

    var cardLayout: MediaCardLayout {
        width < 900 ? .row : .grid
    }

    var columns: [GridItem] {
        switch width {
        case ..<900:
            return [GridItem(.flexible(), spacing: gridSpacing)]
        case ..<1400:
            return [
                GridItem(.flexible(minimum: 300), spacing: gridSpacing),
                GridItem(.flexible(minimum: 300), spacing: gridSpacing)
            ]
        default:
            return [
                GridItem(.flexible(minimum: 280), spacing: gridSpacing),
                GridItem(.flexible(minimum: 280), spacing: gridSpacing),
                GridItem(.flexible(minimum: 280), spacing: gridSpacing)
            ]
        }
    }

    var filterColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 110), spacing: 8, alignment: .leading)]
    }
}
