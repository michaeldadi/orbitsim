import SwiftUI

struct SettingsView: View {
    let updatesConfigured: Bool
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showPhysicalDevices") private var showPhysicalDevices = true

    var body: some View {
        Form {
            Section("OrbitSim") {
                LabeledContent("Version", value: "0.1.0 development")
                LabeledContent("Minimum macOS", value: "27.0")
            }
            Section("Targets") {
                Toggle("Show physical devices", isOn: $showPhysicalDevices)
            }
            Section("Updates") {
                Text(updatesConfigured
                     ? "Signed automatic update checks are enabled."
                     : "Signed automatic updates will be enabled after the first notarized release.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
