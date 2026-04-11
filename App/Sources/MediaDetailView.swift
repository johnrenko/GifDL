import AVKit
import SwiftUI

struct MediaDetailView: View {
    let item: ImportedMedia
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Group {
                        if item.mediaKind == .video, let url = item.resolvedLocalFileURL {
                            VideoPlayer(player: AVPlayer(url: url))
                                .frame(height: 320)
                                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        } else {
                            AnimatedMediaView(item: item)
                                .frame(maxWidth: .infinity)
                                .frame(height: 320)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.displayTitle)
                            .font(.title2.weight(.bold))

                        LabeledContent("Status", value: item.status.label)
                        LabeledContent("Source", value: item.sourceLabel)
                        if let metadataSummary = item.metadataSummary {
                            LabeledContent("Media", value: metadataSummary)
                        }
                        if let errorMessage = item.errorMessage, item.status == .failed {
                            LabeledContent("Error", value: errorMessage)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if item.resolvedLocalFileURL != nil {
                        Button {
                            isShowingShareSheet = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .sheet(isPresented: $isShowingShareSheet) {
                if let url = item.resolvedLocalFileURL {
                    ActivityViewController(activityItems: [url])
                }
            }
        }
    }
}
