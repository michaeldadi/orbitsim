import Foundation
import Observation
import OrbitSimCore

@MainActor
@Observable
final class TargetViewModel {
    var targets: [DeviceTarget] = []
    var selectedTargetID: String?
    var isBusy = false
    var message: String?
    var error: String?
    var displays: [SimulatorDisplay] = []
    var selectedDisplayID: String?
    var displayError: String?
    var isLoadingDisplays = false
    var latestCaptureURL: URL?
    var contrastEnabled: Bool?
    var contentSize: SimulatorContentSize?
    var environmentError: String?

    private let registry = TargetRegistry()

    var selectedTarget: DeviceTarget? {
        targets.first { $0.id == selectedTargetID }
    }

    var captureDisplays: [SimulatorDisplay] {
        let integrated = displays.filter(\.isIntegrated)
        return integrated.isEmpty ? displays : integrated
    }

    var needsDisplaySelection: Bool {
        captureDisplays.count > 1 && selectedDisplayID == nil
    }

    var canCaptureSelectedTarget: Bool {
        guard selectedTarget?.kind == .simulator else { return true }
        return !isLoadingDisplays && displayError == nil &&
            !captureDisplays.isEmpty && !needsDisplaySelection
    }

    func refresh() async {
        isBusy = true
        defer { isBusy = false }
        do {
            targets = try await registry.allTargets()
            // Actions must always be tied to a target the user selected. If the
            // selected device disappears, clear the selection instead of silently
            // redirecting an action to another booted Simulator.
            if selectedTargetID != nil && selectedTarget == nil {
                selectedTargetID = nil
            }
            error = nil
            await refreshDisplays()
            await refreshEnvironment()
        } catch {
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func screenshot(to destination: URL) async -> Bool {
        guard let selectedTargetID else { return false }
        if needsDisplaySelection {
            error = "Choose a display before capturing this Simulator."
            return false
        }
        let display = selectedTarget?.kind == .simulator ? selectedDisplayID : nil
        let saved = await run("Saved screenshot to \(destination.lastPathComponent)") {
            try await registry.screenshotReplacing(selectedTargetID, at: destination, display: display)
        }
        if saved { latestCaptureURL = destination }
        return saved
    }

    func recordVideo(to destination: URL) async {
        guard let target = selectedTarget, target.kind == .simulator else { return }
        if needsDisplaySelection {
            error = "Choose a display before recording this Simulator."
            return
        }
        let display = selectedDisplayID
        await run("Saved video to \(destination.lastPathComponent)") {
            try await SimulatorVideoRecorder().record(targetID: target.id, to: destination,
                                                      durationSeconds: 10, display: display)
        }
    }

    func recordGIF(to destination: URL) async {
        guard let target = selectedTarget, target.kind == .simulator else { return }
        if needsDisplaySelection {
            error = "Choose a display before recording this Simulator."
            return
        }
        let display = selectedDisplayID
        await run("Saved GIF to \(destination.lastPathComponent)") {
            try await SimulatorGIFRecorder().record(targetID: target.id, to: destination,
                                                    durationSeconds: 5, framesPerSecond: 10,
                                                    display: display)
        }
    }

    func refreshDisplays() async {
        displays = []
        selectedDisplayID = nil
        displayError = nil
        isLoadingDisplays = false
        guard let target = selectedTarget, target.kind == .simulator,
              target.state == .booted else { return }
        isLoadingDisplays = true
        defer { if selectedTargetID == target.id { isLoadingDisplays = false } }
        do {
            let found = try await registry.simulators.connectedDisplays(target.id)
            guard selectedTargetID == target.id else { return }
            displays = found
            if captureDisplays.count == 1 { selectedDisplayID = captureDisplays[0].id }
        } catch {
            guard selectedTargetID == target.id else { return }
            displayError = error.localizedDescription
        }
    }

    func refreshEnvironment() async {
        contrastEnabled = nil
        contentSize = nil
        environmentError = nil
        guard let target = selectedTarget, target.kind == .simulator,
              target.state == .booted else { return }
        do {
            async let contrast = registry.simulators.increaseContrast(target.id)
            async let size = registry.simulators.contentSize(target.id)
            let (foundContrast, foundSize) = try await (contrast, size)
            guard selectedTargetID == target.id else { return }
            contrastEnabled = foundContrast
            contentSize = foundSize
        } catch {
            guard selectedTargetID == target.id else { return }
            environmentError = error.localizedDescription
        }
    }

    func setIncreaseContrast(_ enabled: Bool) async {
        guard let target = selectedTarget, target.kind == .simulator,
              target.state == .booted else { return }
        let changed = await run("\(enabled ? "Enabled" : "Disabled") Increase Contrast") {
            try await registry.simulators.setIncreaseContrast(target.id, enabled: enabled)
        }
        if changed { await refreshEnvironment() }
    }

    func setContentSize(_ size: SimulatorContentSize) async {
        guard let target = selectedTarget, target.kind == .simulator,
              target.state == .booted else { return }
        let changed = await run("Set text size to \(size.label)") {
            try await registry.simulators.setContentSize(target.id, size: size)
        }
        if changed { await refreshEnvironment() }
    }

    func install(app: URL) async {
        guard let selectedTargetID else { return }
        await run("Installed \(app.lastPathComponent)") {
            try await registry.install(selectedTargetID, app: app)
        }
    }

    @discardableResult
    func installAndRelaunch(_ product: BuildProduct, expectedTargetID: String) async -> Bool {
        guard selectedTargetID == expectedTargetID,
              let target = selectedTarget, target.kind == .simulator,
              target.platform == "iOS",
              target.state == .booted, product.platform == .simulator else {
            error = "The selected Simulator changed. Select it again before installing a build."
            return false
        }
        return await run("Installed and relaunched \(product.name) on \(target.name)") {
            try BuildProductIndex().validate(product)
            try await registry.simulators.install(target.id, app: product.appURL)
            try await registry.simulators.launch(target.id, bundleID: product.bundleID,
                                                 terminateRunningProcess: true)
        }
    }

    func launch(bundleID: String) async {
        guard let selectedTargetID else { return }
        await run("Launched \(bundleID)") {
            try await registry.launch(selectedTargetID, bundleID: bundleID)
        }
    }

    func terminate(bundleID: String, expectedTargetID: String) async {
        guard selectedTargetID == expectedTargetID,
              let target = selectedTarget, target.kind == .simulator,
              target.state == .booted else {
            error = "The selected Simulator changed. Select it again before terminating the app."
            return
        }
        await run("Terminated \(bundleID) on \(target.name)") {
            try await registry.simulators.terminate(target.id, bundleID: bundleID)
        }
    }

    func uninstall(bundleID: String, expectedTargetID: String) async {
        guard selectedTargetID == expectedTargetID,
              let target = selectedTarget,
              target.state == .booted || target.state == .connected else {
            error = "The selected target changed. Select it again before uninstalling the app."
            return
        }
        await run("Uninstalled \(bundleID) from \(target.name)") {
            try await registry.uninstall(target.id, bundleID: bundleID)
        }
    }

    func openURL(_ url: URL) async {
        guard let selectedTargetID else { return }
        await run("Opened \(url.absoluteString)") {
            try await registry.openURL(selectedTargetID, url: url)
        }
    }

    func bootOrShutdown() async {
        guard let target = selectedTarget, target.kind == .simulator else { return }
        let success = target.state == .booted ? "Shut down \(target.name)" : "Booted \(target.name)"
        await run(success) {
            if target.state == .booted {
                try await registry.simulators.shutdown(target.id)
            } else {
                try await registry.simulators.boot(target.id)
            }
        }
        await refresh()
    }

    func setAppearance(dark: Bool) async {
        guard let target = selectedTarget, target.kind == .simulator else { return }
        await run("Set \(target.name) to \(dark ? "Dark" : "Light") appearance") {
            try await registry.simulators.setAppearance(target.id, dark: dark)
        }
    }

    func setLocation(latitude: Double, longitude: Double) async {
        guard let target = selectedTarget, target.kind == .simulator else { return }
        await run("Set test location for \(target.name)") {
            try await registry.simulators.setLocation(target.id, latitude: latitude, longitude: longitude)
        }
    }

    func clearLocation() async {
        guard let target = selectedTarget, target.kind == .simulator else { return }
        await run("Cleared test location") {
            try await registry.simulators.clearLocation(target.id)
        }
    }

    func setStatusBar(time: String?, batteryLevel: Int?) async {
        guard let target = selectedTarget, target.kind == .simulator else { return }
        await run("Updated status bar") {
            try await registry.simulators.overrideStatusBar(target.id, time: time, batteryLevel: batteryLevel)
        }
    }

    func clearStatusBar() async {
        guard let target = selectedTarget, target.kind == .simulator else { return }
        await run("Cleared status bar overrides") {
            try await registry.simulators.clearStatusBar(target.id)
        }
    }

    func addMedia(_ file: URL) async {
        guard let target = selectedTarget, target.kind == .simulator else { return }
        await run("Imported \(file.lastPathComponent)") {
            try await registry.simulators.addMedia(target.id, file: file)
        }
    }

    func sendPush(bundleID: String, payload: URL) async {
        guard let target = selectedTarget, target.kind == .simulator else { return }
        await run("Sent test notification") {
            try await registry.simulators.sendPush(target.id, bundleID: bundleID, payload: payload)
        }
    }

    func setPrivacy(bundleID: String, action: PrivacyAction, service: PrivacyService) async {
        guard let target = selectedTarget, target.kind == .simulator,
              target.state == .booted else { return }
        let verb: String
        switch action {
        case .grant: verb = "Granted"
        case .revoke: verb = "Revoked"
        case .reset: verb = "Reset"
        }
        await run("\(verb) \(service.rawValue) for \(bundleID)") {
            try await registry.simulators.setPrivacy(target.id, action: action,
                                                     service: service, bundleID: bundleID)
        }
    }

    @discardableResult
    private func run(_ success: String, operation: () async throws -> Void) async -> Bool {
        isBusy = true
        message = nil
        error = nil
        defer { isBusy = false }
        do {
            try await operation()
            message = success
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
