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
    @State private var pendingUninstall: UninstallRequest?
    @State private var selectedTextSize: SimulatorContentSize = .large
    @State private var selectedPrivacyService: PrivacyService = .location
    @State private var showRecentBuilds = false
    @State private var recentBuilds: [BuildProduct] = []
    @State private var selectedBuildID: String?
    @State private var recentBuildsError: String?
    @State private var isLoadingRecentBuilds = false
    @State private var recentBuildTargetID: String?
    @State private var recentBuildTargetName = ""
    @AppStorage("showPhysicalDevices") private var showPhysicalDevices = true
    @AppStorage("buildInsightsRoot") private var buildInsightsRoot = ""

    var body: some View {
        NavigationSplitView {
            List(selection: Bindable(model).selectedTargetID) {
                Section("Simulators") {
                    ForEach(model.targets.filter { $0.kind == .simulator }) { target in
                        TargetRow(target: target).tag(target.id)
                    }
                }
                if showPhysicalDevices {
                    Section("Devices") {
                        ForEach(model.targets.filter { $0.kind == .physical }) { target in
                            TargetRow(target: target).tag(target.id)
                        }
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
        .task(id: model.selectedTargetID) {
            await model.refreshDisplays()
            await model.refreshEnvironment()
            if let size = model.contentSize { selectedTextSize = size }
        }
        .onChange(of: model.contentSize) { _, size in
            if let size { selectedTextSize = size }
        }
        .onChange(of: model.selectedTargetID) { _, _ in
            bundleID = ""
            deepLink = ""
            showRecentBuilds = false
        }
        .onChange(of: showPhysicalDevices) { _, visible in
            if !visible, model.selectedTarget?.kind == .physical {
                model.selectedTargetID = nil
            }
        }
        .alert("Uninstall app?", item: $pendingUninstall) { request in
            Button("Uninstall", role: .destructive) {
                Task {
                    await model.uninstall(bundleID: request.bundleID,
                                          expectedTargetID: request.targetID)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text("Remove \(request.bundleID) and its app data from \(request.targetName)?")
        }
        .sheet(isPresented: $showRecentBuilds) { recentBuildsSheet }
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

                if target.kind == .simulator && target.state == .booted {
                    if model.isLoadingDisplays {
                        ProgressView("Discovering displays…")
                    } else if let displayError = model.displayError {
                        Label(displayError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else if model.captureDisplays.count > 1 {
                        Picker("Capture display", selection: Bindable(model).selectedDisplayID) {
                            Text("Choose a display").tag(nil as String?)
                            ForEach(model.captureDisplays) { display in
                                Text("\(display.name) · \(display.pixelWidth) × \(display.pixelHeight)")
                                    .tag(Optional(display.id))
                            }
                        }
                        .frame(maxWidth: 360, alignment: .leading)
                    }
                }

                HStack(spacing: 16) {
                    actionCard("Screenshot", symbol: "camera.viewfinder", detail: "Save a PNG from this target") {
                        saveScreenshot(target)
                    }
                    .disabled(!canAct || !model.canCaptureSelectedTarget)
                    actionCard("Live Preview", symbol: "play.rectangle", detail: "Watch a selected Device Hub window") {
                        openWindow(id: "preview")
                    }
                    .disabled(!canAct)
                    if target.kind == .simulator {
                        actionCard("Record", symbol: "record.circle", detail: "Save a 10-second MP4 clip") {
                            saveRecording(target)
                        }
                        .disabled(target.state != .booted || !model.canCaptureSelectedTarget)
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
                        if target.kind == .simulator {
                            Button("Terminate") { Task { await model.terminate(bundleID: bundleID,
                                                                                  expectedTargetID: target.id) } }
                                .disabled(bundleID.isEmpty || model.isBusy || !canAct)
                        }
                        Button("Uninstall", role: .destructive) {
                            pendingUninstall = UninstallRequest(bundleID: bundleID,
                                                                targetID: target.id,
                                                                targetName: target.name)
                        }
                        .disabled(bundleID.isEmpty || model.isBusy || !canAct)
                        Button("Install App…") { selectApp() }
                            .disabled(model.isBusy || !canAct)
                        if target.kind == .simulator && target.platform == "iOS" {
                            Button("Recent Builds…") {
                                Task { await loadRecentBuilds(for: target) }
                            }
                            .disabled(model.isBusy || !canAct)
                        }
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
                            Button("Record GIF…") { saveGIF(target) }
                            Button("Send Push…") { selectPushPayload() }
                                .disabled(bundleID.isEmpty)
                            Spacer()
                        }
                        .disabled(model.isBusy || !canAct)

                        Divider()
                        HStack {
                            Text("Accessibility")
                                .font(.subheadline.weight(.semibold))
                            if let enabled = model.contrastEnabled {
                                Text("Contrast: \(enabled ? "Increased" : "Standard")")
                                    .foregroundStyle(.secondary)
                            }
                            Button("Increase Contrast") {
                                Task { await model.setIncreaseContrast(true) }
                            }
                            Button("Standard Contrast") {
                                Task { await model.setIncreaseContrast(false) }
                            }
                            Spacer()
                        }
                        .disabled(model.isBusy || !canAct)
                        HStack {
                            Picker("Text Size", selection: $selectedTextSize) {
                                ForEach(SimulatorContentSize.allCases) { size in
                                    Text(size.label).tag(size)
                                }
                            }
                            .frame(maxWidth: 340)
                            Button("Apply Text Size") {
                                Task { await model.setContentSize(selectedTextSize) }
                            }
                            .disabled(model.isBusy || !canAct)
                            if let size = model.contentSize {
                                Text("Current: \(size.label)")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        if let environmentError = model.environmentError {
                            Text(environmentError)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Divider()
                        HStack {
                            Picker("App Permission", selection: $selectedPrivacyService) {
                                ForEach(PrivacyService.allCases.filter { $0 != .all }) { service in
                                    Text(service.rawValue).tag(service)
                                }
                            }
                            .frame(maxWidth: 280)
                            Button("Grant") {
                                Task { await model.setPrivacy(bundleID: bundleID, action: .grant,
                                                               service: selectedPrivacyService) }
                            }
                            Button("Revoke") {
                                Task { await model.setPrivacy(bundleID: bundleID, action: .revoke,
                                                               service: selectedPrivacyService) }
                            }
                            Button("Reset") {
                                Task { await model.setPrivacy(bundleID: bundleID, action: .reset,
                                                               service: selectedPrivacyService) }
                            }
                            Spacer()
                        }
                        .disabled(model.isBusy || !canAct || bundleID.isEmpty)
                        Text("Permission changes may restart the test app.")
                            .font(.caption).foregroundStyle(.secondary)

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
        Task {
            if await model.screenshot(to: url) {
                openWindow(id: "capture")
            }
        }
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

    private func saveGIF(_ target: DeviceTarget) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = "OrbitSim_\(target.name.replacingOccurrences(of: " ", with: "_"))_\(Date.now.formatted(.iso8601.year().month().day())).gif"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            model.error = "Choose a new filename for this GIF."
            return
        }
        Task { await model.recordGIF(to: url) }
    }

    private var recentBuildsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Simulator Builds")
                .font(.title2.weight(.semibold))
            Text("Choose the exact app to install and relaunch on \(recentBuildTargetName).")
                .foregroundStyle(.secondary)
            HStack {
                Text(buildInsightsRoot.isEmpty ? "~/Library/Developer/Xcode/DerivedData" : buildInsightsRoot)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose DerivedData…") { chooseRecentBuildRoot() }
                    .disabled(isLoadingRecentBuilds || model.isBusy)
            }
            if isLoadingRecentBuilds {
                ProgressView("Scanning Xcode build products…")
            } else if let recentBuildsError {
                Label(recentBuildsError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            } else if recentBuilds.isEmpty {
                ContentUnavailableView("No Simulator builds found", systemImage: "hammer",
                                       description: Text("Build an iOS app in Xcode, then refresh this list."))
            } else {
                List(selection: $selectedBuildID) {
                    ForEach(recentBuilds) { product in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.name).font(.headline)
                            Text("\(product.project) · \(product.configuration) · \(product.bundleID)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(product.appURL.path)
                                .font(.caption2).foregroundStyle(.tertiary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        .padding(.vertical, 4)
                        .tag(product.id)
                    }
                }
            }
            if let error = model.error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Refresh") {
                    if let target = model.selectedTarget {
                        Task { await loadRecentBuilds(for: target) }
                    }
                }
                .disabled(isLoadingRecentBuilds || model.isBusy)
                Spacer()
                Button("Cancel") { showRecentBuilds = false }
                Button("Install & Relaunch") {
                    guard let product = recentBuilds.first(where: { $0.id == selectedBuildID }),
                          let recentBuildTargetID else { return }
                    Task {
                        if await model.installAndRelaunch(product, expectedTargetID: recentBuildTargetID) {
                            showRecentBuilds = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedBuildID == nil || model.isBusy || isLoadingRecentBuilds)
            }
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 420)
    }

    private func loadRecentBuilds(for target: DeviceTarget) async {
        guard target.kind == .simulator, target.platform == "iOS",
              target.state == .booted else { return }
        recentBuildTargetID = target.id
        recentBuildTargetName = target.name
        selectedBuildID = nil
        recentBuilds = []
        recentBuildsError = nil
        isLoadingRecentBuilds = true
        showRecentBuilds = true
        let root = buildInsightsRoot.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Developer/Xcode/DerivedData")
            : URL(fileURLWithPath: buildInsightsRoot).standardizedFileURL
        do {
            let found = try await Task.detached(priority: .utility) {
                try BuildProductIndex().scan(derivedDataRoot: root, platform: .simulator)
            }.value
            guard model.selectedTargetID == target.id else { return }
            recentBuilds = found
        } catch {
            guard model.selectedTargetID == target.id else { return }
            recentBuildsError = error.localizedDescription
        }
        isLoadingRecentBuilds = false
    }

    private func chooseRecentBuildRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use DerivedData"
        guard panel.runModal() == .OK, let url = panel.url,
              let target = model.selectedTarget else { return }
        buildInsightsRoot = url.standardizedFileURL.path
        Task { await loadRecentBuilds(for: target) }
    }
}

private struct UninstallRequest: Identifiable {
    let id = UUID()
    let bundleID: String
    let targetID: String
    let targetName: String
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
