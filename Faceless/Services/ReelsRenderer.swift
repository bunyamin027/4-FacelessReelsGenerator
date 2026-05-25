//
//  ReelsRenderer.swift
//  Faceless
//
//  Created on 2026-05-23.
//
//  Core video composition engine that combines source video, audio,
//  and animated text overlays into a 9:16 portrait reel using
//  AVFoundation and CoreAnimation.
//

import AVFoundation
import CoreImage
import Foundation
import OSLog
import QuartzCore
import UIKit

// MARK: - Errors

/// Errors that can occur during the reel rendering pipeline.
enum ReelsRendererError: Error, LocalizedError {
    /// The source asset has no valid video or audio tracks.
    case trackLoadingFailed
    /// The export session failed with the given reason.
    case exportFailed(String)
    /// One or more inputs (URLs, scenes) are invalid.
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .trackLoadingFailed:
            return "Failed to load tracks from source asset."
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .invalidInput:
            return "Invalid input provided to the renderer."
        }
    }
}

// MARK: - ReelsRenderer

/// A production-quality video composition engine that creates 9:16
/// portrait reels with animated text overlays.
///
/// The renderer takes a background video, an audio track, and an array
/// of ``Scene`` objects, then composites them into a single `.mp4` file
/// using Core Animation for text animations.
///
/// ## Usage
/// ```swift
/// let renderer = ReelsRenderer()
/// let outputURL = try await renderer.renderReel(
///     videoURLs: [url1, url2],
///     audioURL: audioFile,
///     scenes: scenes,
///     resolution: .hd1080
/// )
/// ```
@MainActor
final class ReelsRenderer {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.faceless.app", category: "ReelsRenderer")

    // MARK: - Constants

    private enum Layout {
        /// Horizontal padding from screen edges for text layers.
        static let textHorizontalPadding: CGFloat = 32
        /// Vertical offset from the bottom of the screen to the text layer bottom edge.
        static let textBottomOffset: CGFloat = 200
        /// Corner radius of the text background.
        static let textCornerRadius: CGFloat = 12
        /// Internal padding inside the text background layer.
        static let textInternalPadding: CGFloat = 16
        /// Maximum height fraction the text layer can occupy.
        static let textMaxHeightFraction: CGFloat = 0.35
        /// Font size for scene text.
        static let textFontSize: CGFloat = 62
        /// Background opacity behind text.
        static let textBackgroundAlpha: CGFloat = 0.65
        /// Watermark font size.
        static let watermarkFontSize: CGFloat = 18
        /// Watermark right margin.
        static let watermarkRightMargin: CGFloat = 16
        /// Watermark bottom margin.
        static let watermarkBottomMargin: CGFloat = 40
        /// Animation fade duration in seconds.
        static let fadeDuration: CFTimeInterval = 0.2
        /// Scale animation start value.
        static let scaleFrom: CGFloat = 0.95
        /// Scale animation end value.
        static let scaleTo: CGFloat = 1.0
        /// Output frame rate.
        static let frameRate: Int32 = 30
    }

    // MARK: - Public API

    /// Renders a reel from the given video, audio, and scene data    /// Starts the render pipeline.
    ///
    /// - Parameters:
    ///   - videoURLs: Array of local file URLs for the background videos, corresponding to each scene.
    ///   - audioURL: Local file URL for the voiceover audio track.
    ///   - scenes: Array of scenes defining the timeline structure.
    ///   - resolution: Output resolution (e.g., 1080x1920).
    ///   - watermarkText: Optional watermark text.
    /// - Returns: URL of the final exported `.mp4` file.
    func renderReel(
        videoURLs: [URL],
        audioURL: URL,
        userMediaURL: URL? = nil,
        scenes: [Scene],
        textAnimationStyle: String = "popup",
        resolution: RenderResolution = .hd1080,
        watermarkText: String? = nil
    ) async throws -> URL {

        logger.info("Starting reel render — resolution: \(resolution.size.width)x\(resolution.size.height), scenes: \(scenes.count)")

        // Validate inputs
        guard !scenes.isEmpty else {
            logger.error("No scenes provided.")
            throw ReelsRendererError.invalidInput
        }
        guard !videoURLs.isEmpty else {
            logger.error("No video URLs provided.")
            throw ReelsRendererError.invalidInput
        }

        let audioAsset = AVURLAsset(url: audioURL)
        let audioDuration = try await audioAsset.load(.duration).seconds
        let totalBlueprintDuration = scenes.reduce(0.0) { $0 + $1.duration }
        
        // Scale scene durations to perfectly match the actual generated audio length
        let durationScale = audioDuration > 0 && totalBlueprintDuration > 0 ? audioDuration / totalBlueprintDuration : 1.0
        
        let scaledScenes = scenes.map { scene in
            Scene(
                duration: scene.duration * durationScale,
                onScreenText: scene.onScreenText,
                voiceoverScript: scene.voiceoverScript,
                videoSearchKeyword: scene.videoSearchKeyword
            )
        }

        // 1. Build the composition & collect transforms
        let (composition, videoTrack, userVideoTrack, _, transforms) = try await buildComposition(
            videoURLs: videoURLs,
            audioURL: audioURL,
            userMediaURL: userMediaURL,
            scenes: scaledScenes,
            renderSize: resolution.size
        )

        // 2. Build video composition with layer instructions (custom compositor if userMediaURL exists)
        let videoComposition = buildVideoComposition(
            composition: composition,
            compositionVideoTrack: videoTrack,
            compositionUserVideoTrack: userVideoTrack,
            transforms: transforms,
            renderSize: resolution.size
        )

        // 3. Build animation layers and attach to video composition
        let totalDuration = composition.duration
        attachAnimationLayers(
            to: videoComposition,
            scenes: scaledScenes,
            textAnimationStyle: textAnimationStyle,
            totalDuration: totalDuration,
            renderSize: resolution.size,
            watermarkText: watermarkText
        )

        // 4. Export
        let outputURL = try await export(
            composition: composition,
            videoComposition: videoComposition,
            resolution: resolution
        )

        logger.info("Reel render complete → \(outputURL.lastPathComponent)")
        return outputURL
    }

    // MARK: - Composition Building

    /// Creates an `AVMutableComposition` with video and audio tracks from the
    /// source files. The audio track drives the overall timeline duration.
    /// Maps each scene to its corresponding video URL, applies the video to that scene's duration,
    /// loops if necessary, and returns the calculated transforms.
    private func buildComposition(
        videoURLs: [URL],
        audioURL: URL,
        userMediaURL: URL?,
        scenes: [Scene],
        renderSize: CGSize
    ) async throws -> (AVMutableComposition, AVMutableCompositionTrack, AVMutableCompositionTrack?, AVMutableCompositionTrack, [(CMTime, CGAffineTransform)]) {

        let audioAsset = AVURLAsset(url: audioURL)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        guard let sourceAudioTrack = audioTracks.first else {
            logger.error("No audio track found in audio asset.")
            throw ReelsRendererError.trackLoadingFailed
        }

        let audioDuration = try await audioAsset.load(.duration)
        let composition = AVMutableComposition()

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ReelsRendererError.trackLoadingFailed
        }

        // Add optional user media track for screen recording layer
        var compositionUserVideoTrack: AVMutableCompositionTrack? = nil
        if userMediaURL != nil {
            compositionUserVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        }

        // Insert audio — single insertion covering the full audio
        let audioTimeRange = CMTimeRange(start: .zero, duration: audioDuration)
        try compositionAudioTrack.insertTimeRange(audioTimeRange, of: sourceAudioTrack, at: .zero)

        // Store transforms mapping: (StartTime, Transform)
        var transforms: [(CMTime, CGAffineTransform)] = []
        var currentTime = CMTime.zero

        for (index, scene) in scenes.enumerated() {
            // Match scene duration, but don't exceed remaining audio duration
            let remainingAudio = audioDuration - currentTime
            if remainingAudio <= .zero { break }
            
            let sceneDurationSec = scene.duration
            var targetDuration = CMTime(seconds: sceneDurationSec, preferredTimescale: 600)
            targetDuration = min(targetDuration, remainingAudio)
            
            // Get corresponding video URL (fallback to last if mismatch)
            let safeIndex = min(index, videoURLs.count - 1)
            let videoURL = videoURLs[safeIndex]
            
            let videoAsset = AVURLAsset(url: videoURL)
            guard let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
                continue
            }
            
            let videoDuration = try await videoAsset.load(.duration)
            guard videoDuration.seconds > 0 else {
                logger.error("Source video duration is zero or invalid for URL: \(videoURL)")
                continue
            }
            let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
            let naturalSize = try await sourceVideoTrack.load(.naturalSize)
            
            // Calculate transform for this specific video
            let transformedSize = naturalSize.applying(preferredTransform)
            let videoWidth = abs(transformedSize.width)
            let videoHeight = abs(transformedSize.height)
            let transform = aspectFillTransform(
                sourceSize: CGSize(width: videoWidth, height: videoHeight),
                targetSize: renderSize,
                preferredTransform: preferredTransform
            )
            
            // Append transform for this scene's start time
            transforms.append((currentTime, transform))

            // Insert video segments (looping if the video is shorter than the scene duration)
            let trimDuration = CMTime(seconds: 0.3, preferredTimescale: 600)
            let usableStart: CMTime
            let usableDuration: CMTime

            if videoDuration.seconds > 2.0 {
                usableStart = trimDuration
                usableDuration = videoDuration - trimDuration - trimDuration
            } else {
                usableStart = .zero
                usableDuration = videoDuration
            }

            var sceneCurrentTime = currentTime
            let sceneEndTime = currentTime + targetDuration

            while sceneCurrentTime < sceneEndTime {
                let remainingInScene = sceneEndTime - sceneCurrentTime
                let insertDuration = min(usableDuration, remainingInScene)
                let insertRange = CMTimeRange(start: usableStart, duration: insertDuration)

                try compositionVideoTrack.insertTimeRange(insertRange, of: sourceVideoTrack, at: sceneCurrentTime)
                sceneCurrentTime = sceneCurrentTime + insertDuration
            }
            
            currentTime = sceneEndTime
        }

        // Loop and insert user media (screen recording) to cover the full composition duration
        if let userURL = userMediaURL, let userVideoTrack = compositionUserVideoTrack {
            let userAsset = AVURLAsset(url: userURL)
            if let sourceUserVideoTrack = try await userAsset.loadTracks(withMediaType: .video).first {
                let userVideoDuration = try await userAsset.load(.duration)
                guard userVideoDuration.seconds > 0 else {
                    logger.error("User video duration is zero or invalid.")
                    throw ReelsRendererError.trackLoadingFailed
                }
                var userCurrentTime = CMTime.zero
                
                while userCurrentTime < composition.duration {
                    let remaining = composition.duration - userCurrentTime
                    let insertDuration = min(userVideoDuration, remaining)
                    let insertRange = CMTimeRange(start: .zero, duration: insertDuration)
                    try userVideoTrack.insertTimeRange(insertRange, of: sourceUserVideoTrack, at: userCurrentTime)
                    userCurrentTime = userCurrentTime + insertDuration
                }
            }
        }

        logger.debug("Composition built — total duration: \(composition.duration.seconds)s")
        return (composition, compositionVideoTrack, compositionUserVideoTrack, compositionAudioTrack, transforms)
    }

    // MARK: - Video Composition (Transform & Scaling)

    /// Builds an `AVMutableVideoComposition` with proper transform handling
    /// using the transforms calculated during `buildComposition`.
    private func buildVideoComposition(
        composition: AVMutableComposition,
        compositionVideoTrack: AVMutableCompositionTrack,
        compositionUserVideoTrack: AVMutableCompositionTrack?,
        transforms: [(CMTime, CGAffineTransform)],
        renderSize: CGSize
    ) -> AVMutableVideoComposition {

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: Layout.frameRate)

        if let userTrack = compositionUserVideoTrack {
            // GPU-accelerated Custom Compositor for iPhone Mockup & Cinematic Blur
            videoComposition.customVideoCompositorClass = CreativeVideoCompositor.self
            
            // Single instructions track for custom compositor covering full range
            let mainInstruction = CreativeVideoCompositionInstruction(
                timeRange: CMTimeRange(start: .zero, duration: composition.duration),
                backgroundTrackID: compositionVideoTrack.trackID,
                foregroundTrackID: userTrack.trackID
            )
            videoComposition.instructions = [mainInstruction]
        } else {
            // Standard Full-screen video composition with basic transforms
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            
            // Apply transforms at their respective start times
            for (time, transform) in transforms {
                layerInstruction.setTransform(transform, at: time)
            }

            instruction.layerInstructions = [layerInstruction]
            videoComposition.instructions = [instruction]
        }

        return videoComposition
    }

    /// Computes a `CGAffineTransform` that scales the source video to
    /// aspect-fill the target render size, centering the result.
    private func aspectFillTransform(
        sourceSize: CGSize,
        targetSize: CGSize,
        preferredTransform: CGAffineTransform
    ) -> CGAffineTransform {

        let scaleX = targetSize.width / sourceSize.width
        let scaleY = targetSize.height / sourceSize.height
        let scale = max(scaleX, scaleY)   // aspect-fill

        let scaledWidth = sourceSize.width * scale
        let scaledHeight = sourceSize.height * scale
        let offsetX = (targetSize.width - scaledWidth) / 2.0
        let offsetY = (targetSize.height - scaledHeight) / 2.0

        // Combine the preferred transform with our scaling + centering
        let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)
        let translateTransform = CGAffineTransform(translationX: offsetX, y: offsetY)

        return preferredTransform
            .concatenating(scaleTransform)
            .concatenating(translateTransform)
    }

    // MARK: - CoreAnimation Layers

    /// Creates the Core Animation layer hierarchy and attaches it to the
    /// video composition via `AVVideoCompositionCoreAnimationTool`.
    private func attachAnimationLayers(
        to videoComposition: AVMutableVideoComposition,
        scenes: [Scene],
        textAnimationStyle: String,
        totalDuration: CMTime,
        renderSize: CGSize,
        watermarkText: String?
    ) {

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = true

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)

        // Setup the TextAnimationEngine for dynamic subtitles
        let textAnimationEngine = TextAnimationEngine()

        // Add text layers for each scene with the chosen creative style
        var currentTime: CFTimeInterval = 0
        for scene in scenes {
            let textLayer = textAnimationEngine.makeAnimatedTextLayer(
                text: scene.onScreenText,
                style: textAnimationStyle,
                startTime: currentTime,
                duration: scene.duration,
                renderSize: renderSize
            )
            parentLayer.addSublayer(textLayer)
            currentTime += scene.duration
        }

        // Watermark
        if let watermark = watermarkText, !watermark.isEmpty {
            let watermarkLayer = makeWatermarkLayer(text: watermark, renderSize: renderSize)
            parentLayer.addSublayer(watermarkLayer)
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        logger.debug("Animation layers attached — \(scenes.count) text layer(s), style: \(textAnimationStyle), watermark: \(watermarkText != nil)")
    }

    // MARK: - Watermark

    /// Creates a persistent watermark text layer at the bottom-right.
    private func makeWatermarkLayer(
        text: String,
        renderSize: CGSize
    ) -> CATextLayer {

        let watermarkLayer = CATextLayer()

        let font = UIFont.systemFont(ofSize: Layout.watermarkFontSize, weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.55),
            .paragraphStyle: paragraphStyle
        ]

        watermarkLayer.string = NSAttributedString(string: text, attributes: attributes)
        watermarkLayer.contentsScale = UIScreen.main.scale
        watermarkLayer.alignmentMode = .right

        let textSize = (text as NSString).size(withAttributes: attributes)
        let originX = renderSize.width - textSize.width - Layout.watermarkRightMargin
        let originY = renderSize.height - Layout.watermarkBottomMargin

        watermarkLayer.frame = CGRect(
            x: originX,
            y: originY,
            width: textSize.width + 8,
            height: textSize.height + 4
        )

        watermarkLayer.opacity = 1.0

        return watermarkLayer
    }

    // MARK: - Export

    /// Exports the composition to an `.mp4` file in the temporary directory.
    private func export(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        resolution: RenderResolution
    ) async throws -> URL {

        // HighestQuality preset → videoComposition.renderSize'a (1080×1920) saygı gösterir
        // Landscape-specific preset (1920×1080) portrait çıktıyla çakışıyordu.
        let presetName = AVAssetExportPresetHighestQuality

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: presetName
        ) else {
            throw ReelsRendererError.exportFailed("Could not create export session.")
        }

        let outputFileName = "Faceless_\(UUID().uuidString).mp4"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)

        // Remove existing file at path if any
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        exportSession.videoComposition = videoComposition
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        logger.info("Starting export — preset: \(presetName), output: \(outputFileName)")

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            logger.info("Export completed successfully.")
            return outputURL

        case .failed:
            let errorMessage = exportSession.error?.localizedDescription ?? "Unknown error"
            logger.error("Export failed: \(errorMessage)")
            throw ReelsRendererError.exportFailed(errorMessage)

        case .cancelled:
            logger.warning("Export was cancelled.")
            throw ReelsRendererError.exportFailed("Export cancelled by user.")

        default:
            let statusDesc = "\(exportSession.status.rawValue)"
            logger.error("Export ended with unexpected status: \(statusDesc)")
            throw ReelsRendererError.exportFailed("Unexpected export status: \(statusDesc)")
        }
    }
}
