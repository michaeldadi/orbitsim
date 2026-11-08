import Foundation

public struct BuildRecord: Codable, Hashable, Sendable {
    public let id: String
    public let project: String
    public let scheme: String
    public let title: String
    public let startedAt: Date
    public let durationSeconds: Double
    public let statusCode: String
    public let errorCount: Int
    public let warningCount: Int
}

public struct BuildStatistics: Codable, Sendable {
    public let count: Int
    public let p50Seconds: Double?
    public let p75Seconds: Double?
    public let p95Seconds: Double?
    public let errorCount: Int
    public let warningCount: Int
}

/// Reads Xcode's build log manifests without modifying DerivedData.
public struct BuildLogIndex: Sendable {
    public init() {}

    public func scan(derivedDataRoot: URL) throws -> [BuildRecord] {
        guard derivedDataRoot.isFileURL else {
            throw OrbitSimError.invalidArgument("DerivedData root must be a local directory")
        }
        let folders = try FileManager.default.contentsOfDirectory(
            at: derivedDataRoot, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var records: [BuildRecord] = []
        func appendManifest(in folder: URL) {
            let manifest = folder.appendingPathComponent("Logs/Build/LogStoreManifest.plist")
            guard let data = try? Data(contentsOf: manifest),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let root = plist as? [String: Any],
                  let logs = root["logs"] as? [String: [String: Any]] else { return }

            for (id, log) in logs where log["domainType"] as? String == "Xcode.IDEActivityLogDomainType.BuildLog" {
                guard let start = (log["timeStartedRecording"] as? NSNumber)?.doubleValue,
                      let stop = (log["timeStoppedRecording"] as? NSNumber)?.doubleValue,
                      stop >= start else { continue }
                let observable = log["primaryObservable"] as? [String: Any] ?? [:]
                records.append(BuildRecord(
                    id: id,
                    project: folder.lastPathComponent,
                    scheme: log["schemeIdentifier-schemeName"] as? String ?? "Unknown",
                    title: log["title"] as? String ?? "Build",
                    startedAt: Date(timeIntervalSinceReferenceDate: start),
                    durationSeconds: stop - start,
                    statusCode: observable["highLevelStatus"] as? String ?? "unknown",
                    errorCount: (observable["totalNumberOfErrors"] as? NSNumber)?.intValue ?? 0,
                    warningCount: (observable["totalNumberOfWarnings"] as? NSNumber)?.intValue ?? 0
                ))
            }
        }
        appendManifest(in: derivedDataRoot)
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            appendManifest(in: folder)
        }
        return records.sorted { $0.startedAt > $1.startedAt }
    }

    public func statistics(for records: [BuildRecord]) -> BuildStatistics {
        let sorted = records.map(\.durationSeconds).sorted()
        func percentile(_ fraction: Double) -> Double? {
            guard !sorted.isEmpty else { return nil }
            let position = fraction * Double(sorted.count - 1)
            let low = Int(position.rounded(.down))
            let high = Int(position.rounded(.up))
            let weight = position - Double(low)
            return sorted[low] * (1 - weight) + sorted[high] * weight
        }
        return BuildStatistics(
            count: records.count,
            p50Seconds: percentile(0.50),
            p75Seconds: percentile(0.75),
            p95Seconds: percentile(0.95),
            errorCount: records.reduce(0) { $0 + $1.errorCount },
            warningCount: records.reduce(0) { $0 + $1.warningCount }
        )
    }
}
