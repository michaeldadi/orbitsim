import OrbitSimCore
import SwiftUI

struct SettingsView: View {
    let updatesConfigured: Bool
    @AppStorage("showPhysicalDevices") private var showPhysicalDevices = true
    @State private var cliMessage: String?

    var body: some View {
        Form {
            Section("OrbitSim") {
                LabeledContent("Version", value: OrbitSimVersion.app + " development")
                LabeledContent("Minimum macOS", value: "27.0")
            }
            Section("Command Line") {
#if DEBUG
                Button("Install orbitsim in ~/.local/bin") { installCLI() }
                    .disabled(true)
                Text("Install the signed release app in Applications before enabling the CLI link.")
                    .font(.caption).foregroundStyle(.secondary)
#else
                Button("Install orbitsim in ~/.local/bin") { installCLI() }
#endif
                if let cliMessage {
                    Text(cliMessage).font(.caption)
                }
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

    private func installCLI() {
        do {
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin", isDirectory: true)
            let link = try CLIInstaller().install(from: Bundle.main.bundleURL, into: directory)
            cliMessage = "Installed \(link.path). Add ~/.local/bin to PATH if needed."
        } catch {
            cliMessage = error.localizedDescription
        }
    }
}
