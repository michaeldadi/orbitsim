import AppKit
import OrbitSimCore
import OrbitSimUpdater
import SwiftUI

@main
struct OrbitSimApp: App {
    @State private var model = TargetViewModel()
    private let updates = UpdateController()

    var body: some Scene {
        Window("OrbitSim", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 880, minHeight: 580)
        }
        .defaultSize(width: 1040, height: 700)

        Window("Build Insights", id: "builds") {
            BuildInsightsView()
                .frame(minWidth: 700, minHeight: 480)
        }
        .defaultSize(width: 820, height: 560)

        MenuBarExtra("OrbitSim", systemImage: "circle.hexagongrid.fill") {
            StatusMenu(model: model, updates: updates)
        }

        Settings {
            SettingsView(updatesConfigured: updates.isConfigured)
                .frame(width: 480, height: 320)
        }
    }
}

private struct StatusMenu: View {
    @Environment(\.openWindow) private var openWindow
    var model: TargetViewModel
    let updates: UpdateController

    var body: some View {
        Button("Open OrbitSim") { openWindow(id: "main") }
        Button("Build Insights") { openWindow(id: "builds") }
        Button("Check for Updates…") { updates.checkForUpdates() }
            .disabled(!updates.isConfigured)
        Button("Refresh Targets") { Task { await model.refresh() } }
        Divider()
        Text("\(model.targets.filter { $0.state == .booted }.count) active Simulators")
        Divider()
        Button("Quit OrbitSim") { NSApplication.shared.terminate(nil) }
    }
}
