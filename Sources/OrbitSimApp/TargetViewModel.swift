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

    private let registry = TargetRegistry()

    var selectedTarget: DeviceTarget? {
        targets.first { $0.id == selectedTargetID }
    }

    func refresh() async {
        isBusy = true
        defer { isBusy = false }
        do {
            targets = try await registry.allTargets()
            if selectedTargetID == nil || selectedTarget == nil {
                selectedTargetID = targets.first(where: { $0.state == .booted })?.id ?? targets.first?.id
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func screenshot(to destination: URL) async {
        guard let selectedTargetID else { return }
        await run("Saved screenshot to \(destination.lastPathComponent)") {
            try await registry.screenshotReplacing(selectedTargetID, at: destination)
        }
    }

    func recordVideo(to destination: URL) async {
        guard let target = selectedTarget, target.kind == .simulator else { return }
        await run("Saved video to \(destination.lastPathComponent)") {
            try await SimulatorVideoRecorder().record(targetID: target.id, to: destination,
                                                      durationSeconds: 10)
        }
    }

    func install(app: URL) async {
        guard let selectedTargetID else { return }
        await run("Installed \(app.lastPathComponent)") {
            try await registry.install(selectedTargetID, app: app)
        }
    }

    func launch(bundleID: String) async {
        guard let selectedTargetID else { return }
        await run("Launched \(bundleID)") {
            try await registry.launch(selectedTargetID, bundleID: bundleID)
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

    private func run(_ success: String, operation: () async throws -> Void) async {
        isBusy = true
        message = nil
        error = nil
        defer { isBusy = false }
        do {
            try await operation()
            message = success
        } catch {
            self.error = error.localizedDescription
        }
    }
}
