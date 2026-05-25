//
//  AdvancedVideoRenderer.swift
//  Faceless
//
//  Created on 2026-05-26.
//  Advanced video generator with slideshow rendering and audio track sync/looping.
//

import AVFoundation
import CoreGraphics
import ImageIO
import UIKit
import os.log

/// Settings for rendering a slideshow video with background audio.
struct AdvancedRenderSettings: Sendable {
    /// Target size of the output video. Defaults to 1080x1920 (vertical Reels format).
    var size: CGSize = CGSize(width: 1080, height: 1920)
    
    /// Video frame rate (FPS). Default is 30.
    var fps: Int32 = 30
    
    /// Display duration for each image, in seconds. Default is 3.0.
    var slideDuration: TimeInterval = 3.0
    
    /// Transition duration for crossfade between images, in seconds. Default is 0.5.
    var transitionDuration: TimeInterval = 0.5
    
    /// Average video bitrate. Default is 8,000,000 (8 Mbps).
    var videoBitrate: Int = 8_000_000
    
    /// Scaling mode when resizing images to fit the render size.
    var scaleMode: ScaleMode = .aspectFill
    
    /// Optional voiceover text to synthesize and overlay.
    var voiceoverText: String? = nil
    
    /// Language code for voiceover (e.g. "tr-TR", "en-US").
    var voiceoverLanguage: String = "tr-TR"
}

/// Detailed errors that can occur during slideshow and audio rendering.
enum AdvancedVideoRendererError: LocalizedError {
    case emptyInput
    case audioFileNotFound(URL)
    case invalidOutputURL
    case fileAccessDenied(String)
    case insufficientDiskSpace(required: Int64, available: Int64)
    case writerInitializationFailed(String)
    case writerFailed(String)
    case imageLoadingFailed(URL)
    case pixelBufferPoolCreationFailed
    case pixelBufferAllocationFailed
    case frameRenderingFailed(Int, String)
    case audioVideoSyncFailed(String)
    case exportFailed(String)
    case exportCancelled
    case writeCancelled
    
    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Input images or URLs list is empty."
        case .audioFileNotFound(let url):
            return "Audio file not found at: \(url.path)"
        case .invalidOutputURL:
            return "The provided output URL is invalid."
        case .fileAccessDenied(let reason):
            return "File access denied: \(reason)"
        case .insufficientDiskSpace(let required, let available):
            return "Insufficient disk space. Required: \(required / 1024 / 1024)MB, Available: \(available / 1024 / 1024)MB"
        case .writerInitializationFailed(let reason):
            return "Failed to initialize AVAssetWriter: \(reason)"
        case .writerFailed(let reason):
            return "AVAssetWriter failed: \(reason)"
        case .imageLoadingFailed(let url):
            return "Failed to load or downsample image from URL: \(url.lastPathComponent)"
        case .pixelBufferPoolCreationFailed:
            return "Failed to create CVPixelBufferPool."
        case .pixelBufferAllocationFailed:
            return "Failed to allocate pixel buffer from pool."
        case .frameRenderingFailed(let index, let reason):
            return "Failed to render frame at index \(index): \(reason)"
        case .audioVideoSyncFailed(let reason):
            return "Audio-video sync failed: \(reason)"
        case .exportFailed(let reason):
            return "Video export failed: \(reason)"
        case .exportCancelled:
            return "Video export was cancelled."
        case .writeCancelled:
            return "Video rendering was cancelled."
        }
    }
}

/// An actor/service that renders a slideshow video from a list of local image URLs
/// and merges/synchronizes it with an audio track.
final class AdvancedVideoRenderer: @unchecked Sendable {
    
    private let logger = Logger(subsystem: "com.faceless.app", category: "AdvancedVideoRenderer")
    
    init() {}
    
    private func makeEven(_ value: CGFloat) -> CGFloat {
        return CGFloat(Int(round(value / 2.0)) * 2)
    }
    
    private func synthesizeText(_ text: String, language: String, to fileURL: URL) async throws -> URL {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        
        if let voice = AVSpeechSynthesisVoice(language: language) {
            utterance.voice = voice
        } else if let fallbackVoice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = fallbackVoice
        }
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            var output: AVAudioFile?
            var resumed = false
            
            synthesizer.write(utterance) { buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: NSError(domain: "AVSpeechSynthesizer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to cast buffer to AVAudioPCMBuffer"]))
                    }
                    return
                }
                
                if pcmBuffer.frameLength == 0 {
                    if !resumed {
                        resumed = true
                        continuation.resume(returning: fileURL)
                    }
                } else {
                    do {
                        if output == nil {
                            output = try AVAudioFile(
                                forWriting: fileURL,
                                settings: pcmBuffer.format.settings,
                                commonFormat: pcmBuffer.format.commonFormat,
                                interleaved: pcmBuffer.format.isInterleaved
                            )
                        }
                        try output?.write(from: pcmBuffer)
                    } catch {
                        if !resumed {
                            resumed = true
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        }
    }
    
    /// Renders a slideshow video with synched background music.
    ///
    /// - Parameters:
    ///   - imageURLs: List of local file URLs pointing to images.
    ///   - audioURL: Local file URL pointing to the audio file.
    ///   - outputURL: Target file URL for the final output video (.mp4).
    ///   - settings: Video and timing configurations.
    ///   - progressHandler: Progress callback called on the `@MainActor`. Ranges from 0.0 to 1.0.
    func renderVideoWithAudio(
        from imageURLs: [URL],
        audioURL: URL,
        to outputURL: URL,
        settings: AdvancedRenderSettings,
        progressHandler: (@Sendable @MainActor (Double) -> Void)? = nil
    ) async throws {
        
        // Ensure dimensions are even (H.264 codec requirement)
        var settings = settings
        settings.size = CGSize(
            width: makeEven(settings.size.width),
            height: makeEven(settings.size.height)
        )
        
        // 1. Validations
        guard !imageURLs.isEmpty else {
            throw AdvancedVideoRendererError.emptyInput
        }
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: audioURL.path) else {
            throw AdvancedVideoRendererError.audioFileNotFound(audioURL)
        }
        
        let outputDirectory = outputURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: outputDirectory.path) {
            do {
                try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                throw AdvancedVideoRendererError.fileAccessDenied("Could not create output directory: \(error.localizedDescription)")
            }
        }
        
        // Clean up output path if a file exists
        if fileManager.fileExists(atPath: outputURL.path) {
            do {
                try fileManager.removeItem(at: outputURL)
            } catch {
                throw AdvancedVideoRendererError.fileAccessDenied("Could not remove existing file at output path: \(error.localizedDescription)")
            }
        }
        
        // Voiceover (TTS) Generation and timing adjustments
        var voiceoverURL: URL? = nil
        var voiceoverDuration: CMTime? = nil
        if let voiceoverText = settings.voiceoverText, !voiceoverText.isEmpty {
            let tempVoiceoverURL = fileManager.temporaryDirectory
                .appendingPathComponent("Voiceover_\(UUID().uuidString).caf")
            logger.info("Synthesizing native voiceover...")
            do {
                _ = try await synthesizeText(voiceoverText, language: settings.voiceoverLanguage, to: tempVoiceoverURL)
                let voiceoverAsset = AVURLAsset(url: tempVoiceoverURL)
                let duration = try await voiceoverAsset.load(.duration)
                voiceoverDuration = duration
                voiceoverURL = tempVoiceoverURL
                logger.info("Voiceover synthesized successfully. Duration: \(duration.seconds) seconds.")
                
                // Adjust slide duration if voiceover is longer than the original slideshow duration
                let originalDuration = Double(imageURLs.count) * settings.slideDuration
                if duration.seconds > originalDuration {
                    logger.info("Voiceover duration (\(duration.seconds)s) exceeds original duration (\(originalDuration)s). Extending slide duration.")
                    settings.slideDuration = duration.seconds / Double(imageURLs.count)
                }
            } catch {
                logger.error("🚨 Voiceover synthesis failed: \(error.localizedDescription)")
                try? fileManager.removeItem(at: tempVoiceoverURL)
            }
        }
        
        defer {
            // Clean up temporary voiceover
            if let voiceoverURL = voiceoverURL, fileManager.fileExists(atPath: voiceoverURL.path) {
                try? fileManager.removeItem(at: voiceoverURL)
            }
        }
        
        // 2. Disk space check (slideshow size + audio size + voiceover size)
        let totalDuration = Double(imageURLs.count) * settings.slideDuration
        var estimatedRequiredBytes = Int64(totalDuration * Double(settings.videoBitrate) / 8.0) * 2 + 50_000_000 // 2x video + 50MB audio buffer
        if voiceoverURL != nil {
            estimatedRequiredBytes += 20_000_000 // Add extra buffer for voiceover audio file
        }
        
        do {
            let resourceValues = try outputDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let availableCapacity = resourceValues.volumeAvailableCapacityForImportantUsage {
                if availableCapacity < estimatedRequiredBytes {
                    throw AdvancedVideoRendererError.insufficientDiskSpace(required: estimatedRequiredBytes, available: availableCapacity)
                }
            }
        } catch {
            logger.warning("Failed to query available disk space: \(error.localizedDescription)")
        }
        
        // Create temporary URL for the silent video stage
        let tempSilentVideoURL = fileManager.temporaryDirectory
            .appendingPathComponent("SilentSlideshow_\(UUID().uuidString).mp4")
        
        defer {
            // Clean up temporary silent video
            if fileManager.fileExists(atPath: tempSilentVideoURL.path) {
                try? fileManager.removeItem(at: tempSilentVideoURL)
            }
        }
        
        // 3. Stage 1: Render Silent Slideshow Video
        logger.info("Stage 1: Rendering silent slideshow video...")
        try await renderSilentSlideshow(
            from: imageURLs,
            to: tempSilentVideoURL,
            settings: settings,
            progressHandler: { progress in
                // Map Stage 1 progress to 0.0 - 0.70 range
                if let progressHandler = progressHandler {
                    Task { @MainActor in
                        progressHandler(progress * 0.70)
                    }
                }
            }
        )
        
        // 4. Stage 2: Merge Silent Video with Audio (Loop / Trim / Voiceover)
        logger.info("Stage 2: Merging audio track into silent video...")
        try await mergeVideoAndAudio(
            videoURL: tempSilentVideoURL,
            audioURL: audioURL,
            voiceoverURL: voiceoverURL,
            to: outputURL,
            progressHandler: { progress in
                // Map Stage 2 progress to 0.70 - 1.00 range
                if let progressHandler = progressHandler {
                    Task { @MainActor in
                        progressHandler(0.70 + (progress * 0.30))
                    }
                }
            }
        )
        
        logger.info("Advanced video render successfully completed at: \(outputURL.lastPathComponent)")
    }
    
    // MARK: - Stage 1: Silent Slideshow Rendering
    
    private func renderSilentSlideshow(
        from imageURLs: [URL],
        to outputURL: URL,
        settings: AdvancedRenderSettings,
        progressHandler: @Sendable @escaping (Double) -> Void
    ) async throws {
        
        let task = Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: outputURL.path) {
                try? fileManager.removeItem(at: outputURL)
            }
            
            let writer: AVAssetWriter
            do {
                writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            } catch {
                throw AdvancedVideoRendererError.writerInitializationFailed(error.localizedDescription)
            }
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(settings.size.width),
                AVVideoHeightKey: Int(settings.size.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: settings.videoBitrate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            
            let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            writerInput.expectsMediaDataInRealTime = false
            
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(settings.size.width),
                kCVPixelBufferHeightKey as String: Int(settings.size.height),
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: writerInput,
                sourcePixelBufferAttributes: pixelBufferAttributes
            )
            
            writer.add(writerInput)
            
            guard writer.startWriting() else {
                let underlyingError = writer.error
                print("🚨 [AdvancedVideoRenderer] AVAssetWriter failed to start writing. Status: \(writer.status.rawValue). Error: \(underlyingError?.localizedDescription ?? "None"). Details: \(String(describing: underlyingError))")
                let errorMsg = underlyingError?.localizedDescription ?? "Unknown failure starting asset writer"
                throw AdvancedVideoRendererError.writerFailed(errorMsg)
            }
            
            writer.startSession(atSourceTime: .zero)
            
            let fps = settings.fps
            var frameIndex: Int64 = 0
            
            let slideFrameCount = Int(settings.slideDuration * Double(fps))
            let transitionFrameCount = Int(settings.transitionDuration * Double(fps))
            
            // Calculate total frames to report progress
            var totalEstimatedFrames = 0
            for i in 0..<imageURLs.count {
                let isLast = i == imageURLs.count - 1
                let staticFrames = isLast ? slideFrameCount : max(slideFrameCount - transitionFrameCount, 1)
                totalEstimatedFrames += staticFrames
                if !isLast {
                    totalEstimatedFrames += transitionFrameCount
                }
            }
            
            var currentCGImage: CGImage? = nil
            
            for index in 0..<imageURLs.count {
                try Task.checkCancellation()
                
                let url = imageURLs[index]
                let isLast = index == imageURLs.count - 1
                
                // Load current image (or reuse from previous loop transition)
                let cgImage: CGImage
                if let preloaded = currentCGImage {
                    cgImage = preloaded
                } else {
                    guard let loaded = try Self.loadAndScaleImage(from: url, to: settings.size, scaleMode: settings.scaleMode) else {
                        writer.cancelWriting()
                        throw AdvancedVideoRendererError.imageLoadingFailed(url)
                    }
                    cgImage = loaded
                }
                
                // Write static frames
                let staticFrames = isLast ? slideFrameCount : max(slideFrameCount - transitionFrameCount, 1)
                
                for _ in 0..<staticFrames {
                    try Task.checkCancellation()
                    
                    let presentationTime = CMTime(value: frameIndex, timescale: fps)
                    
                    while !writerInput.isReadyForMoreMediaData {
                        try await Task.sleep(nanoseconds: 5_000_000)
                    }
                    
                    let success = autoreleasepool { () -> Bool in
                        guard let pool = adaptor.pixelBufferPool,
                              let pixelBuffer = Self.createPixelBuffer(from: cgImage, size: settings.size, pool: pool) else {
                            return false
                        }
                        return adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                    }
                    
                    if !success {
                        let underlyingError = writer.error
                        print("🚨 [AdvancedVideoRenderer] AVAssetWriter frame append failed at index \(frameIndex). Status: \(writer.status.rawValue). Error: \(underlyingError?.localizedDescription ?? "None"). Details: \(String(describing: underlyingError))")
                        let writerError = underlyingError?.localizedDescription ?? "Pixel buffer append failed"
                        writer.cancelWriting()
                        throw AdvancedVideoRendererError.frameRenderingFailed(Int(frameIndex), writerError)
                    }
                    
                    frameIndex += 1
                    
                    // Report Stage 1 progress
                    let currentProgress = Double(frameIndex) / Double(totalEstimatedFrames)
                    progressHandler(currentProgress)
                }
                
                // Write transition frames
                if !isLast {
                    let nextURL = imageURLs[index + 1]
                    guard let nextCGImage = try Self.loadAndScaleImage(from: nextURL, to: settings.size, scaleMode: settings.scaleMode) else {
                        writer.cancelWriting()
                        throw AdvancedVideoRendererError.imageLoadingFailed(nextURL)
                    }
                    
                    for transitionFrame in 0..<transitionFrameCount {
                        try Task.checkCancellation()
                        
                        let alpha = CGFloat(transitionFrame) / CGFloat(transitionFrameCount)
                        let presentationTime = CMTime(value: frameIndex, timescale: fps)
                        
                        while !writerInput.isReadyForMoreMediaData {
                            try await Task.sleep(nanoseconds: 5_000_000)
                        }
                        
                        let success = autoreleasepool { () -> Bool in
                            guard let pool = adaptor.pixelBufferPool,
                                  let blendedBuffer = Self.createBlendedPixelBuffer(
                                    from: cgImage,
                                    to: nextCGImage,
                                    alpha: alpha,
                                    size: settings.size,
                                    pool: pool
                                  ) else {
                                return false
                            }
                            return adaptor.append(blendedBuffer, withPresentationTime: presentationTime)
                        }
                        
                        if !success {
                            let underlyingError = writer.error
                            print("🚨 [AdvancedVideoRenderer] AVAssetWriter blended frame append failed at index \(frameIndex). Status: \(writer.status.rawValue). Error: \(underlyingError?.localizedDescription ?? "None"). Details: \(String(describing: underlyingError))")
                            let writerError = underlyingError?.localizedDescription ?? "Blended buffer append failed"
                            writer.cancelWriting()
                            throw AdvancedVideoRendererError.frameRenderingFailed(Int(frameIndex), writerError)
                        }
                        
                        frameIndex += 1
                        
                        // Report Stage 1 progress
                        let currentProgress = Double(frameIndex) / Double(totalEstimatedFrames)
                        progressHandler(currentProgress)
                    }
                    
                    currentCGImage = nextCGImage
                } else {
                    currentCGImage = nil
                }
            }
            
            writerInput.markAsFinished()
            await writer.finishWriting()
            
            if writer.status == .failed {
                let underlyingError = writer.error
                print("🚨 [AdvancedVideoRenderer] AVAssetWriter failed during finalization. Status: .failed. Error: \(underlyingError?.localizedDescription ?? "None"). Details: \(String(describing: underlyingError))")
                let errorMsg = underlyingError?.localizedDescription ?? "AVAssetWriter failed to finalize silent video"
                throw AdvancedVideoRendererError.writerFailed(errorMsg)
            }
        }
        try await task.value
    }
    
    // MARK: - Stage 2: Audio-Video Merging
    
    @MainActor
    private func mergeVideoAndAudio(
        videoURL: URL,
        audioURL: URL,
        voiceoverURL: URL?,
        to outputURL: URL,
        progressHandler: @Sendable @escaping (Double) -> Void
    ) async throws {
        
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        
        let composition = AVMutableComposition()
        
        // 1. Get tracks
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        
        guard let videoAssetTrack = videoTracks.first else {
            throw AdvancedVideoRendererError.audioVideoSyncFailed("Silent video file has no video track.")
        }
        guard let audioAssetTrack = audioTracks.first else {
            throw AdvancedVideoRendererError.audioVideoSyncFailed("Audio file has no audio track.")
        }
        
        var voiceoverAssetTrack: AVAssetTrack? = nil
        var voiceoverDuration = CMTime.zero
        if let voiceoverURL = voiceoverURL {
            let voiceoverAsset = AVURLAsset(url: voiceoverURL)
            let voiceoverTracks = try await voiceoverAsset.loadTracks(withMediaType: .audio)
            voiceoverAssetTrack = voiceoverTracks.first
            if voiceoverAssetTrack != nil {
                voiceoverDuration = try await voiceoverAsset.load(.duration)
            }
        }
        
        // 2. Add composition tracks
        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AdvancedVideoRendererError.audioVideoSyncFailed("Could not create composition tracks.")
        }
        
        var compositionVoiceoverTrack: AVMutableCompositionTrack? = nil
        if voiceoverAssetTrack != nil {
            compositionVoiceoverTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        
        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        
        // Insert complete video track
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: videoAssetTrack,
            at: .zero
        )
        
        // Match natural video track transformation
        let preferredTransform = try await videoAssetTrack.load(.preferredTransform)
        compositionVideoTrack.preferredTransform = preferredTransform
        
        // Insert voiceover track if exists
        if let voiceoverAssetTrack = voiceoverAssetTrack, let compositionVoiceoverTrack = compositionVoiceoverTrack {
            try compositionVoiceoverTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: voiceoverDuration),
                of: voiceoverAssetTrack,
                at: .zero
            )
        }
        
        // 3. Sync timing: Trim or Loop audio
        if audioDuration >= videoDuration {
            // Müzik videodan uzun veya eşitse: Kırp
            logger.info("Audio is longer or equal to video. Trimming audio track.")
            let trimRange = CMTimeRange(start: .zero, duration: videoDuration)
            try compositionAudioTrack.insertTimeRange(trimRange, of: audioAssetTrack, at: .zero)
        } else {
            // Müzik videodan kısaysa: Döngüye (Loop) sok
            logger.info("Audio is shorter than video. Looping audio track.")
            var currentInsertionTime = CMTime.zero
            
            while currentInsertionTime < videoDuration {
                let remainingTime = CMTimeSubtract(videoDuration, currentInsertionTime)
                let chunkDuration = CMTimeMinimum(audioDuration, remainingTime)
                let chunkRange = CMTimeRange(start: .zero, duration: chunkDuration)
                
                try compositionAudioTrack.insertTimeRange(chunkRange, of: audioAssetTrack, at: currentInsertionTime)
                currentInsertionTime = CMTimeAdd(currentInsertionTime, chunkDuration)
            }
        }
        
        // 4. Export composition to output URL
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            do {
                try fileManager.removeItem(at: outputURL)
            } catch {
                logger.error("⚠️ Failed to remove existing file at output URL before exporting: \(error.localizedDescription)")
            }
        }
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw AdvancedVideoRendererError.exportFailed("Could not initialize AVAssetExportSession.")
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Apply Audio Mix and Ducking if Voiceover exists
        if voiceoverAssetTrack != nil {
            let bgMusicParams = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
            
            let rampDownDuration = CMTime(seconds: 0.5, preferredTimescale: 600)
            let rampUpDuration = CMTime(seconds: 0.5, preferredTimescale: 600)
            
            if voiceoverDuration.seconds > 1.0 {
                // Ramp down: 0.0 -> 0.5s (1.0 -> 0.2)
                bgMusicParams.setVolumeRamp(
                    fromStartVolume: 1.0,
                    toEndVolume: 0.2,
                    timeRange: CMTimeRange(start: .zero, duration: rampDownDuration)
                )
                // Ramp up: voiceoverDuration -> voiceoverDuration + 0.5s (0.2 -> 1.0)
                bgMusicParams.setVolumeRamp(
                    fromStartVolume: 0.2,
                    toEndVolume: 1.0,
                    timeRange: CMTimeRange(start: voiceoverDuration, duration: rampUpDuration)
                )
            } else {
                // Voiceover is very short, just step down/up
                bgMusicParams.setVolumeRamp(
                    fromStartVolume: 1.0,
                    toEndVolume: 0.2,
                    timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 0.1, preferredTimescale: 600))
                )
                bgMusicParams.setVolumeRamp(
                    fromStartVolume: 0.2,
                    toEndVolume: 1.0,
                    timeRange: CMTimeRange(start: voiceoverDuration, duration: CMTime(seconds: 0.3, preferredTimescale: 600))
                )
            }
            
            var audioMixInputParameters = [bgMusicParams]
            if let voiceoverTrack = compositionVoiceoverTrack {
                let voiceoverParams = AVMutableAudioMixInputParameters(track: voiceoverTrack)
                voiceoverParams.setVolume(1.0, at: .zero)
                audioMixInputParameters.append(voiceoverParams)
            }
            
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = audioMixInputParameters
            exportSession.audioMix = audioMix
        }
        
        // Asynchronously export and track progress on the MainActor
        let exportTask = Task { @MainActor in
            while exportSession.status == .waiting || exportSession.status == .exporting {
                progressHandler(Double(exportSession.progress))
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
        
        await exportSession.export()
        exportTask.cancel()
        
        switch exportSession.status {
        case .completed:
            progressHandler(1.0)
        case .failed:
            let underlyingError = exportSession.error
            print("🚨 [AdvancedVideoRenderer] AVAssetExportSession failed. Status: .failed. Error: \(underlyingError?.localizedDescription ?? "None"). Details: \(String(describing: underlyingError))")
            let errorMsg = underlyingError?.localizedDescription ?? "Unknown failure during merge export"
            throw AdvancedVideoRendererError.exportFailed(errorMsg)
        case .cancelled:
            throw AdvancedVideoRendererError.exportCancelled
        default:
            throw AdvancedVideoRendererError.exportFailed("Unexpected export status: \(exportSession.status.rawValue)")
        }
    }
    
    // MARK: - CoreGraphics Resizing & Downsampling (Reused for memory safety)
    
    private static func loadAndScaleImage(from url: URL, to targetSize: CGSize, scaleMode: ScaleMode) throws -> CGImage? {
        let maxPixelSize = max(targetSize.width, targetSize.height)
        
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        
        return resizeCGImage(cgImage, to: targetSize, scaleMode: scaleMode)
    }
    
    private static func resizeCGImage(_ cgImage: CGImage, to targetSize: CGSize, scaleMode: ScaleMode) -> CGImage? {
        let width = Int(targetSize.width)
        let height = Int(targetSize.height)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }
        
        context.interpolationQuality = .high
        
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: targetSize))
        
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let scaleX = targetSize.width / imageSize.width
        let scaleY = targetSize.height / imageSize.height
        
        let scale: CGFloat
        switch scaleMode {
        case .aspectFill:
            scale = max(scaleX, scaleY)
        case .aspectFit:
            scale = min(scaleX, scaleY)
        }
        
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let originX = (targetSize.width - scaledWidth) / 2.0
        let originY = (targetSize.height - scaledHeight) / 2.0
        
        let drawRect = CGRect(x: originX, y: originY, width: scaledWidth, height: scaledHeight)
        context.draw(cgImage, in: drawRect)
        
        return context.makeImage()
    }
    
    // MARK: - Pixel Buffer locked memory rendering
    
    private static func createPixelBuffer(from cgImage: CGImage, size: CGSize, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)
        let bitmapInfo: UInt32
        if pixelFormat == kCVPixelFormatType_32BGRA {
            bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        } else if pixelFormat == kCVPixelFormatType_32ARGB {
            bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        } else {
            bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }
    
    private static func createBlendedPixelBuffer(
        from fromImage: CGImage,
        to toImage: CGImage,
        alpha: CGFloat,
        size: CGSize,
        pool: CVPixelBufferPool
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)
        let bitmapInfo: UInt32
        if pixelFormat == kCVPixelFormatType_32BGRA {
            bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        } else if pixelFormat == kCVPixelFormatType_32ARGB {
            bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        } else {
            bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        
        let rect = CGRect(origin: .zero, size: size)
        context.draw(fromImage, in: rect)
        context.setAlpha(alpha)
        context.draw(toImage, in: rect)
        
        return buffer
    }
}
