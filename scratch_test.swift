import Foundation
import AVFoundation

func createMockAudioFile(outputURL: URL) throws {
    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false) else {
        throw NSError(domain: "AVAudioFormat", code: -1)
    }
    let audioFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
    buffer.frameLength = 44100
    if let floatData = buffer.floatChannelData {
        memset(floatData[0], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
    }
    try audioFile.write(from: buffer)
}

func combineAudioFiles(_ urls: [URL], outputURL: URL) async throws -> URL {
    let composition = AVMutableComposition()
    guard let compositionTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
        throw NSError(domain: "AVMutableComposition", code: -2)
    }

    var currentTime = CMTime.zero

    for (index, url) in urls.enumerated() {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let assetTrack = tracks.first else {
            print("No audio track in file \(index + 1)")
            throw NSError(domain: "AVURLAsset", code: -3)
        }

        let duration = try await asset.load(.duration)
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try compositionTrack.insertTimeRange(timeRange, of: assetTrack, at: currentTime)
        currentTime = CMTimeAdd(currentTime, duration)
    }

    guard let exportSession = AVAssetExportSession(
        asset: composition,
        presetName: AVAssetExportPresetAppleM4A
    ) else {
        throw NSError(domain: "AVAssetExportSession", code: -4)
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .m4a

    print("Exporting combined audio...")
    await exportSession.export()

    switch exportSession.status {
    case .completed:
        print("Export completed successfully.")
        return outputURL
    case .failed:
        print("Export failed: \(exportSession.error?.localizedDescription ?? "unknown")")
        throw exportSession.error ?? NSError(domain: "AVAssetExportSession", code: -5)
    default:
        print("Export status: \(exportSession.status.rawValue)")
        throw NSError(domain: "AVAssetExportSession", code: -6)
    }
}

let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
let file1 = tempDir.appendingPathComponent("scene1.caf")
let file2 = tempDir.appendingPathComponent("scene2.caf")
let file3 = tempDir.appendingPathComponent("scene3.caf")
let combinedFile = tempDir.appendingPathComponent("combined.m4a")

try? FileManager.default.removeItem(at: file1)
try? FileManager.default.removeItem(at: file2)
try? FileManager.default.removeItem(at: file3)
try? FileManager.default.removeItem(at: combinedFile)

print("Creating mock files...")
try createMockAudioFile(outputURL: file1)
try createMockAudioFile(outputURL: file2)
try createMockAudioFile(outputURL: file3)

print("Mock files created successfully.")

print("Combining mock files...")
Task {
    do {
        _ = try await combineAudioFiles([file1, file2, file3], outputURL: combinedFile)
        print("SUCCESS! Combined file is at: \(combinedFile.path)")
        exit(0)
    } catch {
        print("FAILED with error: \(error)")
        exit(1)
    }
}

// Keep the tool alive while task runs
RunLoop.main.run(until: Date(timeIntervalSinceNow: 5.0))
