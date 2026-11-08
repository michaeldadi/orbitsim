import AppKit
import SwiftUI

struct CaptureShelfView: View {
    var model: TargetViewModel
    @State private var image: NSImage?
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Last Capture", systemImage: "camera.viewfinder")
                    .font(.headline)
                Spacer()
                Text("PNG")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let url = model.latestCaptureURL, let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 320)
                    .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .draggable(url)
                    .accessibilityLabel("Drag \(url.lastPathComponent) to another app")

                Text(url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(url.path)

                HStack {
                    Button("Copy Image") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        feedback = pasteboard.writeObjects([image])
                            ? "Copied image" : "Could not copy image"
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                if let feedback {
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("No screenshot yet", systemImage: "photo",
                                       description: Text("Save a screenshot from a selected target."))
                    .frame(width: 300, height: 340)
            }
        }
        .padding(18)
        .task(id: model.latestCaptureURL) {
            feedback = nil
            image = model.latestCaptureURL.flatMap { NSImage(contentsOf: $0) }
        }
    }
}
