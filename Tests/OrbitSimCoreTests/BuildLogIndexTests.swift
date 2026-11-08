import Foundation
import XCTest
@testable import OrbitSimCore

final class BuildLogIndexTests: XCTestCase {
    func testReadsXcodeManifestAndComputesPercentiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbitsim-builds-\(UUID().uuidString)", isDirectory: true)
        let logs = root.appendingPathComponent("FixtureProject/Logs/Build", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manifest: [String: Any] = [
            "logs": [
                "build-1": [
                    "domainType": "Xcode.IDEActivityLogDomainType.BuildLog",
                    "timeStartedRecording": 100.0,
                    "timeStoppedRecording": 110.0,
                    "schemeIdentifier-schemeName": "Fixture",
                    "title": "Building Fixture",
                    "primaryObservable": [
                        "highLevelStatus": "S",
                        "totalNumberOfErrors": 0,
                        "totalNumberOfWarnings": 2,
                    ],
                ],
                "build-2": [
                    "domainType": "Xcode.IDEActivityLogDomainType.BuildLog",
                    "timeStartedRecording": 120.0,
                    "timeStoppedRecording": 140.0,
                    "schemeIdentifier-schemeName": "Fixture",
                    "primaryObservable": [
                        "highLevelStatus": "F",
                        "totalNumberOfErrors": 1,
                    ],
                ],
            ],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: manifest, format: .binary, options: 0)
        try data.write(to: logs.appendingPathComponent("LogStoreManifest.plist"))

        let index = BuildLogIndex()
        let records = try index.scan(derivedDataRoot: root)
        XCTAssertEqual(records.map(\.id), ["build-2", "build-1"])
        XCTAssertEqual(records.map(\.durationSeconds), [20, 10])
        XCTAssertEqual(records.first?.project, "FixtureProject")
        let statistics = index.statistics(for: records)
        XCTAssertEqual(statistics.count, 2)
        XCTAssertEqual(statistics.p75Seconds ?? 0, 17.5, accuracy: 0.001)
        XCTAssertEqual(statistics.p95Seconds ?? 0, 19.5, accuracy: 0.001)
        XCTAssertEqual(statistics.errorCount, 1)
        XCTAssertEqual(statistics.warningCount, 2)
    }
}
