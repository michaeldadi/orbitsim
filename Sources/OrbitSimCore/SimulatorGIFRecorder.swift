import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct SimulatorGIFRecorder: Sendable {
    public init() {}

    /// Records a bounded Simulator movie, then samples it into an animated GIF.
    /// GIF carries no audio. Keep the source movie private and remove it after export.
    public func record(targetID: String, to destination: URL, durationSeconds: Int,
                       framesPerSecond: Int = 10, display: String? = nil) async throws {
        try SimulatorClient.checkDestination(destination, extension: "gif")
        guard (1...30).contains(durationSeconds), (1...10).contains(framesPerSecond) else {
            throw OrbitSimError.invalidArgument("GIF duration must be 1–30 seconds and frame rate 1–10 FPS")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbitsim-gif-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let movie = directory.appendingPathComponent("source.mp4")
        let encoded = directory.appendingPathComponent("encoded.gif")

        try await SimulatorVideoRecorder().record(targetID: targetID, to: movie,
                                                  durationSeconds: durationSeconds, display: display)
        try await encode(movie: movie, to: encoded, framesPerSecond: framesPerSecond)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw OrbitSimError.destinationExists(destination.path)
        }
        try FileManager.default.moveItem(at: encoded, to: destination)
    }

    private func encode(movie: URL, to destination: URL, framesPerSecond: Int) async throws {
        let asset = AVURLAsset(url: movie)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0.1 else {
            throw OrbitSimError.invalidResponse(tool: "recorded movie duration")
        }
        let frameCount = max(1, Int((duration * Double(framesPerSecond)).rounded(.down)))
        guard let encoder = CGImageDestinationCreateWithURL(destination as CFURL,
                                                            UTType.gif.identifier as CFString,
                                                            frameCount, nil) else {
            throw OrbitSimError.invalidResponse(tool: "GIF encoder")
        }
        let loop = [kCGImagePropertyGIFDictionary as String:
            [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary
        CGImageDestinationSetProperties(encoder, loop)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
        let frameProperties = [kCGImagePropertyGIFDictionary as String:
            [kCGImagePropertyGIFDelayTime as String: 1.0 / Double(framesPerSecond)]] as CFDictionary

        for index in 0..<frameCount {
            try Task.checkCancellation()
            let seconds = min(Double(index) / Double(framesPerSecond), duration - 0.01)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            let frame = try await generator.image(at: time).image
            CGImageDestinationAddImage(encoder, frame, frameProperties)
        }
        guard CGImageDestinationFinalize(encoder) else {
            throw OrbitSimError.invalidResponse(tool: "GIF encoder finalization")
        }
    }
}
