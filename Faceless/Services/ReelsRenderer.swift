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
///     videoURL: videoFile,
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

    /// Renders a reel from the given video, audio, and scene data.
    ///
    /// - Parameters:
    ///   - videoURL: The source background video file URL.
    ///   - audioURL: The voiceover / music audio file URL.
    ///   - scenes: An array of ``Scene`` objects describing text and timing.
    ///   - resolution: The output resolution (default `.hd1080`).
    ///   - watermarkText: Optional watermark string shown at the bottom-right.
    /// - Returns: A file `URL` pointing to the exported `.mp4` in the temp directory.
    /// - Throws: ``ReelsRendererError`` if any step fails.
    func renderReel(
        videoURL: URL,
        audioURL: URL,
        scenes: [Scene],
        resolution: RenderResolution = .hd1080,
        watermarkText: String? = nil
    ) async throws -> URL {

        logger.info("Starting reel render — resolution: \(resolution.size.width)x\(resolution.size.height), scenes: \(scenes.count)")

        // Validate inputs
        guard !scenes.isEmpty else {
            logger.error("No scenes provided.")
            throw ReelsRendererError.invalidInput
        }

        // 1. Build the composition
        let (composition, videoTrack, audioTrack) = try await buildComposition(
            videoURL: videoURL,
            audioURL: audioURL
        )

        // 2. Build video composition with layer instructions
        let videoComposition = try await buildVideoComposition(
            composition: composition,
            compositionVideoTrack: videoTrack,
            sourceVideoURL: videoURL,
            renderSize: resolution.size
        )

        // 3. Build animation layers and attach to video composition
        let totalDuration = composition.duration
        attachAnimationLayers(
            to: videoComposition,
            scenes: scenes,
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
    /// If the video is shorter than the audio, the video is looped.
    private func buildComposition(
        videoURL: URL,
        audioURL: URL
    ) async throws -> (AVMutableComposition, AVMutableCompositionTrack, AVMutableCompositionTrack) {

        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        // Load source tracks asynchronously
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)

        guard let sourceVideoTrack = videoTracks.first else {
            logger.error("No video track found in source asset.")
            throw ReelsRendererError.trackLoadingFailed
        }
        guard let sourceAudioTrack = audioTracks.first else {
            logger.error("No audio track found in audio asset.")
            throw ReelsRendererError.trackLoadingFailed
        }

        let audioDuration = try await audioAsset.load(.duration)
        let videoDuration = try await videoAsset.load(.duration)

        logger.debug("Audio duration: \(audioDuration.seconds)s, Video duration: \(videoDuration.seconds)s")

        let composition = AVMutableComposition()

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ReelsRendererError.trackLoadingFailed
        }

        guard let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ReelsRendererError.trackLoadingFailed
        }

        // Insert audio — single insertion covering the full audio
        let audioTimeRange = CMTimeRange(start: .zero, duration: audioDuration)
        try compositionAudioTrack.insertTimeRange(audioTimeRange, of: sourceAudioTrack, at: .zero)

        // Insert video — loop if shorter than audio
        let videoTimeRange = CMTimeRange(start: .zero, duration: videoDuration)
        var currentTime = CMTime.zero

        while currentTime < audioDuration {
            let remaining = audioDuration - currentTime
            let insertDuration = min(videoDuration, remaining)
            let insertRange = CMTimeRange(start: .zero, duration: insertDuration)

            try compositionVideoTrack.insertTimeRange(insertRange, of: sourceVideoTrack, at: currentTime)
            currentTime = currentTime + insertDuration
        }

        logger.debug("Composition built — total duration: \(composition.duration.seconds)s")
        return (composition, compositionVideoTrack, compositionAudioTrack)
    }

    // MARK: - Video Composition (Transform & Scaling)

    /// Builds an `AVMutableVideoComposition` with proper transform handling
    /// so the source video is aspect-filled into the target render size.
    private func buildVideoComposition(
        composition: AVMutableComposition,
        compositionVideoTrack: AVMutableCompositionTrack,
        sourceVideoURL: URL,
        renderSize: CGSize
    ) async throws -> AVMutableVideoComposition {

        let sourceAsset = AVURLAsset(url: sourceVideoURL)
        guard let sourceTrack = try await sourceAsset.loadTracks(withMediaType: .video).first else {
            throw ReelsRendererError.trackLoadingFailed
        }

        let preferredTransform = try await sourceTrack.load(.preferredTransform)
        let naturalSize = try await sourceTrack.load(.naturalSize)
        let transformedSize = naturalSize.applying(preferredTransform)
        let videoWidth = abs(transformedSize.width)
        let videoHeight = abs(transformedSize.height)

        logger.debug("Source natural size: \(naturalSize.width)x\(naturalSize.height), transformed: \(videoWidth)x\(videoHeight)")

        // Calculate aspect-fill transform
        let transform = aspectFillTransform(
            sourceSize: CGSize(width: videoWidth, height: videoHeight),
            targetSize: renderSize,
            preferredTransform: preferredTransform
        )

        // Build instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: Layout.frameRate)
        videoComposition.instructions = [instruction]

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

        // Add text layers for each scene
        var currentTime: CFTimeInterval = 0
        for (index, scene) in scenes.enumerated() {
            let textLayer = makeTextLayer(
                for: scene,
                index: index,
                startTime: currentTime,
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

        logger.debug("Animation layers attached — \(scenes.count) text layer(s), watermark: \(watermarkText != nil)")
    }

    /// Creates a single animated text layer for a scene.
    private func makeTextLayer(
        for scene: Scene,
        index: Int,
        startTime: CFTimeInterval,
        renderSize: CGSize
    ) -> CALayer {

        let endTime = startTime + scene.duration
        let padding = Layout.textInternalPadding

        // Container layer (background + rounded corners)
        let containerLayer = CALayer()
        containerLayer.backgroundColor = UIColor.black.withAlphaComponent(Layout.textBackgroundAlpha).cgColor
        containerLayer.cornerRadius = Layout.textCornerRadius
        containerLayer.masksToBounds = true

        // Text layer
        let textLayer = CATextLayer()
        textLayer.string = makeAttributedText(scene.onScreenText, fontSize: Layout.textFontSize, renderSize: renderSize)
        textLayer.isWrapped = true
        textLayer.alignmentMode = .center
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.truncationMode = .end

        // Calculate sizes
        let maxTextWidth = renderSize.width - (Layout.textHorizontalPadding * 2) - (padding * 2)
        let maxTextHeight = renderSize.height * Layout.textMaxHeightFraction
        let textSize = estimateTextSize(
            scene.onScreenText,
            fontSize: Layout.textFontSize,
            maxWidth: maxTextWidth,
            maxHeight: maxTextHeight
        )

        let containerWidth = textSize.width + (padding * 2)
        let containerHeight = textSize.height + (padding * 2)
        let containerX = (renderSize.width - containerWidth) / 2.0
        let containerY = renderSize.height - Layout.textBottomOffset - containerHeight

        containerLayer.frame = CGRect(
            x: containerX,
            y: containerY,
            width: containerWidth,
            height: containerHeight
        )

        textLayer.frame = CGRect(
            x: padding,
            y: padding,
            width: textSize.width,
            height: textSize.height
        )
        containerLayer.addSublayer(textLayer)

        // Animations
        addFadeAnimations(to: containerLayer, startTime: startTime, endTime: endTime)
        addScaleAnimation(to: containerLayer, startTime: startTime)

        // Initially hidden
        containerLayer.opacity = 0

        logger.debug("Text layer [\(index)] — start: \(startTime)s, end: \(endTime)s, text: \"\(scene.onScreenText.prefix(30))...\"")

        return containerLayer
    }

    /// Creates an `NSAttributedString` for the scene text.
    private func makeAttributedText(
        _ text: String,
        fontSize: CGFloat,
        renderSize: CGSize
    ) -> NSAttributedString {

        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineHeightMultiple = 1.15

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle
        ]

        return NSAttributedString(string: text, attributes: attributes)
    }

    /// Estimates the bounding size for the given text.
    private func estimateTextSize(
        _ text: String,
        fontSize: CGFloat,
        maxWidth: CGFloat,
        maxHeight: CGFloat
    ) -> CGSize {

        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineHeightMultiple = 1.15

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]

        let boundingRect = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: maxHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )

        return CGSize(
            width: ceil(boundingRect.width),
            height: ceil(boundingRect.height)
        )
    }

    // MARK: - Animations

    /// Adds opacity fade-in and fade-out animations to the given layer.
    private func addFadeAnimations(
        to layer: CALayer,
        startTime: CFTimeInterval,
        endTime: CFTimeInterval
    ) {

        // Fade in
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 1.0
        fadeIn.beginTime = AVCoreAnimationBeginTimeAtZero + startTime
        fadeIn.duration = Layout.fadeDuration
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        layer.add(fadeIn, forKey: "fadeIn_\(startTime)")

        // Fade out
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.beginTime = AVCoreAnimationBeginTimeAtZero + endTime - Layout.fadeDuration
        fadeOut.duration = Layout.fadeDuration
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        layer.add(fadeOut, forKey: "fadeOut_\(endTime)")
    }

    /// Adds a subtle scale-up animation on appear.
    private func addScaleAnimation(
        to layer: CALayer,
        startTime: CFTimeInterval
    ) {

        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = Layout.scaleFrom
        scaleAnim.toValue = Layout.scaleTo
        scaleAnim.beginTime = AVCoreAnimationBeginTimeAtZero + startTime
        scaleAnim.duration = Layout.fadeDuration
        scaleAnim.fillMode = .forwards
        scaleAnim.isRemovedOnCompletion = false
        scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(scaleAnim, forKey: "scaleIn_\(startTime)")
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

        let presetName: String = switch resolution {
        case .hd1080:
            AVAssetExportPreset1920x1080
        case .sd720:
            AVAssetExportPreset1280x720
        }

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
