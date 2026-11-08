import CoreImage
import CoreMedia
import Observation
import OrbitSimCore
import ScreenCaptureKit
import SwiftUI

struct DeviceWindowPreview: View {
    let target: DeviceTarget?
    @State private var model = DeviceWindowPreviewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Live Preview")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh Windows") {
                    Task { await model.refreshWindows(for: target) }
                }
                .disabled(model.isRunning || model.isRefreshing)
            }

            if model.isRefreshing {
                ProgressView("Looking for device windows and capture access…")
            }

            if let target {
                Text("Select the visible Device Hub window for \(target.name). Window capture requires macOS Screen Recording access.")
                    .foregroundStyle(.secondary)
                Picker("Window", selection: Bindable(model).selectedWindowID) {
                    Text("Choose a window").tag(nil as CGWindowID?)
                    ForEach(model.windows) { window in
                        Text("\(window.title) · \(window.id)").tag(Optional(window.id))
                    }
                }
                .disabled(model.isRunning)

                HStack {
                    Button(model.isRunning ? "Stop Preview" : "Start Preview") {
                        Task {
                            if model.isRunning { await model.stop() }
                            else { await model.start() }
                        }
                    }
                    .disabled(!model.isRunning && model.selectedWindowID == nil)
                    Spacer()
                    Text(model.isRunning ? "Capturing selected window · \(model.framesReceived) frames" : "Preview stopped")
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("Select a target", systemImage: "iphone")
            }

            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.85))
                if let frame = model.frame {
                    Image(decorative: frame, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                } else {
                    ContentUnavailableView("No frames yet", systemImage: "play.rectangle")
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .task { await model.refreshWindows(for: target) }
        .onDisappear { Task { await model.stop() } }
    }
}

private struct PreviewWindow: Identifiable {
    let id: CGWindowID
    let title: String
}

@MainActor
@Observable
private final class DeviceWindowPreviewModel {
    var windows: [PreviewWindow] = []
    var selectedWindowID: CGWindowID?
    var frame: CGImage?
    var error: String?
    var isRunning = false
    var isRefreshing = false
    var framesReceived = 0

    @ObservationIgnored private var candidates: [CGWindowID: SCWindow] = [:]
    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var receiver: PreviewFrameReceiver?
    @ObservationIgnored private var sourceMonitor: Task<Void, Never>?

    func refreshWindows(for target: DeviceTarget?) async {
        guard !isRefreshing else { return }
        guard let target, target.state == .booted || target.state == .connected else {
            windows = []
            selectedWindowID = nil
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let content = try await SCShareableContent.current
            let matches = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == "com.apple.dt.Devices" &&
                ($0.title == target.name || $0.title?.hasPrefix("\(target.name) – ") == true) &&
                $0.frame.width > 0 && $0.frame.height > 0
            }
            candidates = Dictionary(uniqueKeysWithValues: matches.map { ($0.windowID, $0) })
            windows = matches.map { PreviewWindow(id: $0.windowID, title: $0.title ?? target.name) }
                .sorted { $0.id < $1.id }
            if let selectedWindowID, candidates[selectedWindowID] == nil {
                self.selectedWindowID = nil
            }
            error = windows.isEmpty ? "Open this target in Device Hub, then refresh windows." : nil
        } catch {
            self.error = Self.captureErrorDescription(error)
        }
    }

    func start() async {
        guard !isRunning, let selectedWindowID, let window = candidates[selectedWindowID] else {
            error = "Choose an available Simulator window first."
            return
        }
        do {
            framesReceived = 0
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(window.frame.width * 2))
            configuration.height = max(1, Int(window.frame.height * 2))
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.queueDepth = 3
            let receiver = PreviewFrameReceiver(onFrame: { [weak self] image, delivered in
                Task { @MainActor [weak self] in
                    if let self, self.isRunning {
                        self.frame = image
                        self.framesReceived += 1
                    }
                    delivered()
                }
            }, onStop: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.error = Self.captureErrorDescription(error)
                    self?.isRunning = false
                    self?.stream = nil
                    self?.receiver = nil
                    self?.sourceMonitor?.cancel()
                    self?.sourceMonitor = nil
                    self?.frame = nil
                }
            })
            let stream = SCStream(
                filter: SCContentFilter(desktopIndependentWindow: window),
                configuration: configuration,
                delegate: receiver
            )
            try stream.addStreamOutput(receiver, type: .screen,
                                       sampleHandlerQueue: DispatchQueue(label: "orbitsim.preview.frames"))
            try await stream.startCapture()
            self.receiver = receiver
            self.stream = stream
            isRunning = true
            error = nil
            let sourceTitle = window.title
            sourceMonitor = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(2)) }
                    catch { break }
                    guard let self, self.isRunning else { break }
                    do {
                        let content = try await SCShareableContent.current
                        guard content.windows.contains(where: {
                            $0.windowID == selectedWindowID &&
                            $0.owningApplication?.bundleIdentifier == "com.apple.dt.Devices" &&
                            $0.title == sourceTitle
                        }) else {
                            self.error = "Device Hub changed or closed this target. Preview stopped to avoid capturing another device."
                            self.sourceMonitor = nil
                            await self.stop()
                            break
                        }
                    } catch {
                        self.error = Self.captureErrorDescription(error)
                        self.sourceMonitor = nil
                        await self.stop()
                        break
                    }
                }
            }
        } catch {
            self.error = Self.captureErrorDescription(error)
        }
    }

    func stop() async {
        sourceMonitor?.cancel()
        sourceMonitor = nil
        if let stream {
            do { try await stream.stopCapture() }
            catch { self.error = error.localizedDescription }
        }
        stream = nil
        receiver = nil
        isRunning = false
        frame = nil
    }

    private static func captureErrorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain && nsError.code == -3801 {
            return "Allow OrbitSim in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen OrbitSim."
        }
        return error.localizedDescription
    }
}

private final class PreviewFrameReceiver: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let lock = NSLock()
    private var framePending = false
    private let onFrame: @Sendable (CGImage, @escaping @Sendable () -> Void) -> Void
    private let onStop: @Sendable (Error) -> Void

    init(onFrame: @escaping @Sendable (CGImage, @escaping @Sendable () -> Void) -> Void,
         onStop: @escaping @Sendable (Error) -> Void) {
        self.onFrame = onFrame
        self.onStop = onStop
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        guard !framePending else {
            lock.unlock()
            return
        }
        framePending = true
        lock.unlock()
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let frame = context.createCGImage(image, from: image.extent) else {
            delivered()
            return
        }
        onFrame(frame) { [weak self] in self?.delivered() }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop(error)
    }

    private func delivered() {
        lock.lock()
        framePending = false
        lock.unlock()
    }
}
