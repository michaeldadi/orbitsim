import AppKit
import Foundation
import Observation
import OrbitSimCore
import SwiftUI

@MainActor
@Observable
private final class BuildInsightsModel {
    var records: [BuildRecord] = []
    var statistics = BuildLogIndex().statistics(for: [])
    var isLoading = false
    var error: String?

    func refresh(root: URL) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let records = try await Task.detached(priority: .utility) {
                try BuildLogIndex().scan(derivedDataRoot: root)
            }.value
            self.records = records
            statistics = BuildLogIndex().statistics(for: records)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct BuildInsightsView: View {
    @State private var model = BuildInsightsModel()
    @AppStorage("buildInsightsRoot") private var selectedRootPath = ""

    private var root: URL {
        selectedRootPath.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Developer/Xcode/DerivedData")
            : URL(fileURLWithPath: selectedRootPath).standardizedFileURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(root.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Choose DerivedData…") { chooseRoot() }
            }
            HStack(spacing: 14) {
                metric("Builds", value: "\(model.statistics.count)")
                metric("Median", value: duration(model.statistics.p50Seconds))
                metric("P75", value: duration(model.statistics.p75Seconds))
                metric("P95", value: duration(model.statistics.p95Seconds))
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            List(model.records, id: \.id) { record in
                HStack(spacing: 18) {
                    Image(systemName: record.statusCode == "S" && record.errorCount == 0
                          ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(record.statusCode == "S" && record.errorCount == 0
                                         ? .green : .red)
                        .accessibilityLabel(record.statusCode == "S" ? "Succeeded" : "Build did not succeed")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.scheme).font(.headline)
                        Text(record.project).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(record.startedAt, style: .date).foregroundStyle(.secondary)
                    Text(duration(record.durationSeconds)).monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if model.records.isEmpty && !model.isLoading {
                    ContentUnavailableView("No Xcode builds found", systemImage: "hammer",
                                           description: Text("Build logs in the default DerivedData folder appear here."))
                }
            }
        }
        .padding(24)
        .navigationTitle("Build Insights")
        .toolbar {
            Button {
                Task { await model.refresh(root: root) }
            } label: {
                Label("Refresh Builds", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .task { await model.refresh(root: root) }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func duration(_ seconds: Double?) -> String {
        seconds.map { String(format: "%.1f s", $0) } ?? "—"
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use DerivedData"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedRootPath = url.standardizedFileURL.path
        Task { await model.refresh(root: root) }
    }
}
