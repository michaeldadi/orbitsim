import AppKit
import OrbitSimCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    var model: TargetViewModel
    @State private var deepLink = ""
    @State private var bundleID = ""
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var statusTime = ""
    @State private var batteryText = ""

    var body: some View {
        NavigationSplitView {
            List(selection: Bindable(model).selectedTargetID) {
                Section("Simulators") {
                    ForEach(model.targets.filter { $0.kind == .simulator }) { target in
                        TargetRow(target: target).tag(target.id)
                    }
                }
                Section("Devices") {
                    ForEach(model.targets.filter { $0.kind == .physical }) { target in
                        TargetRow(target: target).tag(target.id)
                    }
                }
            }
            .navigationTitle("Targets")
            .frame(minWidth: 245)
        } detail: {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.07, green: 0.11, blue: 0.18), Color(red: 0.12, green: 0.17, blue: 0.26)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if let target = model.selectedTarget {
                    targetDetails(target)
                } else {
                    ContentUnavailableView("Select a target", systemImage: "iphone", description: Text("Choose a Simulator or connected device to begin."))
                }
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("Refresh Targets", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isBusy)
                }
            }
        }
        .task { await model.refresh() }
    }

    @ViewBuilder
    private func targetDetails(_ target: DeviceTarget) -> some View {
        let canAct = target.state == .booted || target.state == .connected
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(target.kind == .simulator ? "SIMULATOR" : "PHYSICAL DEVICE")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.cyan)
                        Text(target.name)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("\(target.platform) \(target.osVersion ?? "")  •  \(target.state.rawValue.capitalized)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: target.kind == .simulator ? "iphone.gen3" : "iphone.radiowaves.left.and.right")
                        .font(.system(size: 44, weight: .ultraLight))
                        .foregroundStyle(.cyan)
                }

                HStack(spacing: 16) {
                    actionCard("Screenshot", symbol: "camera.viewfinder", detail: "Save a PNG from this target") {
                        saveScreenshot(target)
                    }
                    .disabled(target.state != .booted && target.state != .connected)
                    if target.kind == .simulator {
                        actionCard("Live Preview", symbol: "play.rectangle", detail: "Watch a selected Simulator window") {
                            openWindow(id: "preview")
                        }
                        .disabled(target.state != .booted)
                        actionCard("Record", symbol: "record.circle", detail: "Save a 10-second MP4 clip") {
                            saveRecording(target)
                        }
                        .disabled(target.state != .booted)
                    }
                    actionCard("Refresh", symbol: "arrow.clockwise", detail: "Update target state") {
                        Task { await model.refresh() }
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("App actions", symbol: "bolt.fill")
                    HStack {
                        TextField("com.example.App", text: $bundleID)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("App bundle identifier")
                        Button("Launch") { Task { await model.launch(bundleID: bundleID) } }
                            .disabled(bundleID.isEmpty || model.isBusy || !canAct)
                        Button("Install App…") { selectApp() }
                            .disabled(model.isBusy || !canAct)
                    }
                    HStack {
                        TextField("https://example.com or yourapp://path", text: $deepLink)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Deep link URL")
                        Button("Open URL") {
                            guard let url = URL(string: deepLink), url.scheme != nil else {
                                model.error = "Enter an absolute URL"
                                return
                            }
                            Task { await model.openURL(url) }
                        }
                        .disabled(deepLink.isEmpty || model.isBusy || !canAct)
                    }
                }
                .padding(22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))

                if target.kind == .simulator {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionTitle("Simulator controls", symbol: "slider.horizontal.3")
                        HStack {
                            Button(target.state == .booted ? "Shut Down" : "Boot") {
                                Task { await model.bootOrShutdown() }
                            }
                            Spacer()
                        }
                        .disabled(model.isBusy)

                        Divider()
                        HStack {
                            Button("Light") { Task { await model.setAppearance(dark: false) } }
                            Button("Dark") { Task { await model.setAppearance(dark: true) } }
                            Button("Import Media…") { selectMedia() }
                            Button("Send Push…") { selectPushPayload() }
                                .disabled(bundleID.isEmpty)
                            Spacer()
                        }
                        .disabled(model.isBusy || !canAct)

                        HStack {
                            TextField("Latitude", text: $latitudeText).frame(width: 105)
                            TextField("Longitude", text: $longitudeText).frame(width: 105)
                            Button("Set Location") { applyLocation() }
                                .disabled(latitudeText.isEmpty || longitudeText.isEmpty)
                            Button("Clear Location") { Task { await model.clearLocation() } }
                            Spacer()
                        }
                        .disabled(model.isBusy || !canAct)

                        HStack {
                            TextField("Time (9:41)", text: $statusTime).frame(width: 120)
                            TextField("Battery %", text: $batteryText).frame(width: 90)
                            Button("Set Status Bar") { applyStatusBar() }
                                .disabled(statusTime.isEmpty && batteryText.isEmpty)
                            Button("Clear") { Task { await model.clearStatusBar() } }
                            Spacer()
                        }
                        .disabled(model.isBusy || !canAct)
                    }
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }

                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityAddTraits(.isStaticText)
                } else if let message = model.message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(32)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.title3.weight(.semibold))
    }

    private func actionCard(_ title: String, symbol: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol).font(.title2).foregroundStyle(.cyan)
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
    }

    private func saveScreenshot(_ target: DeviceTarget) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "OrbitSim_\(target.name.replacingOccurrences(of: " ", with: "_"))_\(Date.now.formatted(.iso8601.year().month().day())).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.screenshot(to: url) }
    }

    private func selectApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "app") ?? .application]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.install(app: url) }
    }

    private func selectMedia() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.addMedia(url) }
    }

    private func selectPushPayload() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.sendPush(bundleID: bundleID, payload: url) }
    }

    private func applyLocation() {
        guard let latitude = Double(latitudeText), let longitude = Double(longitudeText) else {
            model.error = "Latitude and longitude must be numbers."
            return
        }
        Task { await model.setLocation(latitude: latitude, longitude: longitude) }
    }

    private func applyStatusBar() {
        let battery = batteryText.isEmpty ? nil : Int(batteryText)
        if !batteryText.isEmpty && battery == nil {
            model.error = "Battery must be an integer from 0 to 100."
            return
        }
        Task { await model.setStatusBar(time: statusTime.isEmpty ? nil : statusTime,
                                        batteryLevel: battery) }
    }

    private func saveRecording(_ target: DeviceTarget) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "OrbitSim_\(target.name.replacingOccurrences(of: " ", with: "_"))_\(Date.now.formatted(.iso8601.year().month().day())).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            model.error = "Choose a new filename for this recording."
            return
        }
        Task { await model.recordVideo(to: url) }
    }
}

private struct TargetRow: View {
    let target: DeviceTarget

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: target.kind == .simulator ? "iphone.gen3" : "iphone.radiowaves.left.and.right")
                .foregroundStyle(target.state == .booted || target.state == .connected ? .cyan : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(target.name).lineLimit(1)
                Text(target.state.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
