import AppKit
import Observation
import OrbitSimCore
import ScreenCaptureKit
import SwiftUI

struct SideToolsView: View {
    @Environment(\.openWindow) private var openWindow
    var model: TargetViewModel
    @State private var follower = SideToolsFollower()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "iphone.gen3")
                    .foregroundStyle(.cyan)
                Text(model.selectedTarget?.name ?? "No target")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            Text(follower.status)
                .font(.caption)
                .foregroundStyle(follower.isFollowing ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            Button("Screenshot…", systemImage: "camera.viewfinder") {
                saveScreenshot()
            }
            .disabled(!follower.isFollowing || !model.canCaptureSelectedTarget || model.isBusy)
            Button("Live Preview", systemImage: "play.rectangle") {
                openWindow(id: "preview")
            }
            .disabled(model.selectedTarget == nil)
            Button("Open OrbitSim", systemImage: "macwindow") {
                openWindow(id: "main")
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 265, height: 235)
        .background(WindowAnchor { follower.window = $0 })
        .task(id: model.selectedTarget) {
            follower.start(for: model.selectedTarget)
        }
        .onDisappear { follower.stop() }
    }

    private func saveScreenshot() {
        guard let target = model.selectedTarget else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "OrbitSim_\(target.name.replacingOccurrences(of: " ", with: "_"))_\(Date.now.formatted(.iso8601.year().month().day())).png"
        guard panel.runModal() == .OK, let url = panel.url,
              model.selectedTargetID == target.id else { return }
        Task {
            if await model.screenshot(to: url) { openWindow(id: "capture") }
        }
    }
}

private struct WindowAnchor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow?) -> Void

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.onWindow = onWindow
        onWindow(view.window)
    }

    final class AnchorView: NSView {
        var onWindow: (@MainActor (NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}

@MainActor
@Observable
private final class SideToolsFollower {
    weak var window: NSWindow?
    var status = "Select a running target, then open it in Device Hub."
    var isFollowing = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var sourceWindowID: CGWindowID?

    func start(for target: DeviceTarget?) {
        stop()
        guard let target, target.state == .booted || target.state == .connected else {
            status = "Select a running target, then open it in Device Hub."
            return
        }
        status = "Looking for \(target.name) in Device Hub…"
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.position(beside: target)
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { break }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        sourceWindowID = nil
        isFollowing = false
    }

    private func position(beside target: DeviceTarget) async {
        guard let window else { return }
        do {
            let content = try await SCShareableContent.current
            guard !Task.isCancelled else { return }
            let matches = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == "com.apple.dt.Devices" &&
                ($0.title == target.name || $0.title?.hasPrefix("\(target.name) – ") == true) &&
                $0.frame.width > 0 && $0.frame.height > 0
            }
            let source: SCWindow?
            if let sourceWindowID {
                source = matches.first(where: { $0.windowID == sourceWindowID })
            } else if matches.count == 1 {
                source = matches[0]
                sourceWindowID = matches[0].windowID
            } else {
                source = nil
            }
            guard let source else {
                sourceWindowID = nil
                isFollowing = false
                status = matches.count > 1
                    ? "Multiple matching windows; close the extra window to resume."
                    : "Device Hub window unavailable; open \(target.name) to resume."
                return
            }
            guard let primary = NSScreen.screens.first else { return }
            // ScreenCaptureKit's window frame uses a top-left desktop origin.
            let sourceFrame = NSRect(x: source.frame.minX,
                                     y: primary.frame.maxY - source.frame.maxY,
                                     width: source.frame.width,
                                     height: source.frame.height)
            let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: sourceFrame.midX, y: sourceFrame.midY)) }) ?? primary
            let visible = screen.visibleFrame
            let gap: CGFloat = 12
            let right = sourceFrame.maxX + gap
            let left = sourceFrame.minX - window.frame.width - gap
            let preferredX = right + window.frame.width <= visible.maxX ? right : left
            let x = min(max(preferredX, visible.minX), visible.maxX - window.frame.width)
            let preferredY = sourceFrame.maxY - window.frame.height
            let y = min(max(preferredY, visible.minY), visible.maxY - window.frame.height)
            if abs(window.frame.minX - x) > 2 || abs(window.frame.minY - y) > 2 {
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
            isFollowing = true
            status = "Following the selected Device Hub window"
        } catch {
            isFollowing = false
            let nsError = error as NSError
            status = nsError.domain == SCStreamErrorDomain && nsError.code == -3801
                ? "Allow OrbitSim Screen Recording access in System Settings, then reopen the app."
                : "Window access unavailable: \(error.localizedDescription)"
        }
    }
}
