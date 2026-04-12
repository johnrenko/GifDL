import AVKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum DetailMetrics {
    static let previewCornerRadius: CGFloat = 16
    static let primaryActionMinHeight: CGFloat = 46
    static let secondaryActionMinHeight: CGFloat = 44
}

struct MediaDetailView: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: ImportedMedia
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingShareSheet = false
    @State private var shareFeedbackMessage: String?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let layout = DetailLayout(width: geometry.size.width)

                ScrollView {
                    Group {
                        if layout.usesSplitLayout {
                            HStack(alignment: .top, spacing: layout.contentSpacing) {
                                preview(height: layout.previewHeight)
                                    .frame(maxWidth: .infinity)

                                detailPanel(layout: layout)
                                    .frame(width: layout.panelWidth, alignment: .leading)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                                preview(height: layout.previewHeight)
                                detailPanel(layout: layout)
                            }
                        }
                    }
                    .frame(maxWidth: layout.contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if item.resolvedLocalFileURL != nil {
                            Button("Share") {
                                isShowingShareSheet = true
                            }
                            Button("Copy Media") {
                                if let url = item.resolvedLocalFileURL {
                                    copyMediaToPasteboard(from: url)
                                }
                            }
                        }
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $isShowingShareSheet) {
                if let url = item.resolvedLocalFileURL {
                    ActivityViewController(activityItems: [url]) { completed in
                        guard completed else { return }
                        showShareFeedback("Shared and ready for the next send")
                    }
                }
            }
        }
    }

    private func detailPanel(layout: DetailLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.displayTitle)
                    .font(layout.usesSplitLayout ? .title3.weight(.bold) : .title2.weight(.bold))

                HStack(spacing: 8) {
                    DetailStatusBadge(status: item.status)
                    Text(item.sourceLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let feedback = shareFeedbackMessage {
                    Label(feedback, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if let url = item.resolvedLocalFileURL {
                Button {
                    isShowingShareSheet = true
                } label: {
                    Label("Share Now", systemImage: "paperplane.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(primaryActionForeground)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DetailMetrics.primaryActionMinHeight)
                }
                .buttonStyle(.borderedProminent)
                .tint(primaryActionBackground)
                .accessibilityHint("Opens the system share sheet")

                Button {
                    copyMediaToPasteboard(from: url)
                } label: {
                    Label("Copy Media", systemImage: "doc.on.doc")
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DetailMetrics.secondaryActionMinHeight)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .accessibilityHint("Copies the actual media to the clipboard")
            }

            VStack(alignment: .leading, spacing: 8) {
                if let metadataSummary = item.metadataSummary {
                    LabeledContent("Media", value: metadataSummary)
                        .font(.subheadline)
                }
                if let errorMessage = item.errorMessage, item.status == .failed {
                    LabeledContent("Error", value: errorMessage)
                        .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder
    private func preview(height: CGFloat) -> some View {
        if item.mediaKind == .video, let url = item.resolvedLocalFileURL {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: DetailMetrics.previewCornerRadius, style: .continuous))
        } else {
            AnimatedMediaView(item: item)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: DetailMetrics.previewCornerRadius, style: .continuous))
        }
    }

    private func showShareFeedback(_ message: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
            shareFeedbackMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    shareFeedbackMessage = nil
                }
            }
        }
    }

    private func copyMediaToPasteboard(from url: URL) {
        if item.mediaKind == .image,
           item.mimeType.lowercased().contains("gif"),
           let data = try? Data(contentsOf: url) {
            UIPasteboard.general.setData(data, forPasteboardType: UTType.gif.identifier)
            showShareFeedback("Copied GIF to clipboard")
            return
        }

        if item.mediaKind == .image,
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            UIPasteboard.general.image = image
            showShareFeedback("Copied image to clipboard")
            return
        }

        if let provider = NSItemProvider(contentsOf: url) {
            UIPasteboard.general.itemProviders = [provider]
            showShareFeedback("Copied media to clipboard")
            return
        }

        showShareFeedback("Unable to copy this media")
    }

    private var primaryActionBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color(.label)
    }

    private var primaryActionForeground: Color {
        colorScheme == .dark ? .black : Color(.systemBackground)
    }
}

private struct DetailStatusBadge: View {
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

private struct DetailLayout {
    let width: CGFloat

    var usesSplitLayout: Bool { width >= 900 }
    var horizontalPadding: CGFloat { usesSplitLayout ? 24 : 20 }
    var contentSpacing: CGFloat { usesSplitLayout ? 20 : 16 }
    var panelWidth: CGFloat { min(max(width * 0.3, 280), 360) }
    var contentMaxWidth: CGFloat? { usesSplitLayout ? 1180 : nil }

    var previewHeight: CGFloat {
        if usesSplitLayout {
            return 480
        }
        return width < 430 ? 320 : 360
    }
}
