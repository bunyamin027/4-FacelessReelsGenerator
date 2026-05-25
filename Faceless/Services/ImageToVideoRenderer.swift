//
//  ImageToVideoRenderer.swift
//  Faceless
//
//  Created on 2026-05-26.
//  Memory-efficient image slideshow to video renderer.
//

import AVFoundation
import CoreGraphics
import ImageIO
import UIKit
import os.log

/// Settings for rendering a slideshow video from images.
struct RenderSettings: Sendable {
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
}

/// Scaling options for fitting images to the target size.
enum ScaleMode: Sendable {
    case aspectFill
    case aspectFit
}

/// Detailed errors that can occur during image-to-video rendering.
enum ImageToVideoRendererError: LocalizedError {
    case emptyInput
    case invalidOutputURL
    case fileAccessDenied(String)
    case insufficientDiskSpace(required: Int64, available: Int64)
    case writerInitializationFailed(String)
    case pixelBufferPoolCreationFailed
    case pixelBufferAllocationFailed
    case frameRenderingFailed(Int, String)
    case writeCancelled
    case writerFailed(String)
    case imageLoadingFailed(URL)
    
    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Input images or URLs list is empty."
        case .invalidOutputURL:
            return "The provided output URL is invalid."
        case .fileAccessDenied(let reason):
            return "File access denied: \(reason)"
        case .insufficientDiskSpace(let required, let available):
            return "Insufficient disk space. Required: \(required / 1024 / 1024)MB, Available: \(available / 1024 / 1024)MB"
        case .writerInitializationFailed(let reason):
            return "Failed to initialize AVAssetWriter: \(reason)"
        case .pixelBufferPoolCreationFailed:
            return "Failed to create CVPixelBufferPool."
        case .pixelBufferAllocationFailed:
            return "Failed to allocate pixel buffer from pool."
        case .frameRenderingFailed(let index, let reason):
            return "Failed to render frame at index \(index): \(reason)"
        case .writeCancelled:
            return "Video rendering was cancelled."
        case .writerFailed(let reason):
            return "AVAssetWriter failed: \(reason)"
        case .imageLoadingFailed(let url):
            return "Failed to load or downsample image from URL: \(url.lastPathComponent)"
        }
    }
}

/// An actor that renders a slideshow video from a list of local image URLs.
/// Uses on-demand image downsampling and strict memory management to prevent OOM.
final class ImageToVideoRenderer: @unchecked Sendable {
    
    private let logger = Logger(subsystem: "com.faceless.app", category: "ImageToVideoRenderer")
    
    init() {}
    
    /// Renders an MP4 slideshow video from an array of local image URLs.
    ///
    /// - Parameters:
    ///   - imageURLs: List of local file URLs pointing to images.
    ///   - outputURL: Target file URL for the output video (.mp4).
    ///   - settings: Video and timing configurations.
    ///   - progressHandler: Progress callback called on the `@MainActor`. Ranges from 0.0 to 1.0.
    func renderVideo(
        from imageURLs: [URL],
        to outputURL: URL,
        settings: RenderSettings,
        progressHandler: (@Sendable @MainActor (Double) -> Void)? = nil
    ) async throws {
        
        // 1. Validation
        guard !imageURLs.isEmpty else {
            throw ImageToVideoRendererError.emptyInput
        }
        
        // Ensure output directory exists and file can be written
        let fileManager = FileManager.default
        let outputDirectory = outputURL.deletingLastPathComponent()
        
        if !fileManager.fileExists(atPath: outputDirectory.path) {
            do {
                try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                throw ImageToVideoRendererError.fileAccessDenied("Could not create output directory: \(error.localizedDescription)")
            }
        }
        
        // Remove existing file if any
        if fileManager.fileExists(atPath: outputURL.path) {
            do {
                try fileManager.removeItem(at: outputURL)
            } catch {
                throw ImageToVideoRendererError.fileAccessDenied("Could not remove existing file at output path: \(error.localizedDescription)")
            }
        }
        
        // 2. Disk space check
        // Estimate minimum disk space (roughly 1MB per second of 1080p H.264 high quality video, or 100MB to be safe)
        let totalDuration = Double(imageURLs.count) * settings.slideDuration
        let estimatedRequiredBytes: Int64 = Int64(totalDuration * Double(settings.videoBitrate) / 8.0) * 2 // 2x buffer
        
        do {
            let resourceValues = try outputDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let availableCapacity = resourceValues.volumeAvailableCapacityForImportantUsage {
                if availableCapacity < estimatedRequiredBytes {
                    throw ImageToVideoRendererError.insufficientDiskSpace(required: estimatedRequiredBytes, available: availableCapacity)
                }
            }
        } catch {
            logger.warning("Failed to query available disk space: \(error.localizedDescription)")
        }
        
        logger.info("Starting memory-efficient slideshow render. Images count: \(imageURLs.count), total duration: \(totalDuration)s")
        
        // 3. Perform rendering on a detached background thread
        try await Task.detached(priority: .userInitiated) { [logger] in
            let writer: AVAssetWriter
            do {
                writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            } catch {
                throw ImageToVideoRendererError.writerInitializationFailed(error.localizedDescription)
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
                let errorMsg = writer.error?.localizedDescription ?? "Unknown failure starting asset writer"
                throw ImageToVideoRendererError.writerFailed(errorMsg)
            }
            
            writer.startSession(atSourceTime: .zero)
            
            let fps = settings.fps
            var frameIndex: Int64 = 0
            
            let slideFrameCount = Int(settings.slideDuration * Double(fps))
            let transitionFrameCount = Int(settings.transitionDuration * Double(fps))
            
            // We calculate total frames to report progress accurately
            var totalEstimatedFrames = 0
            for i in 0..<imageURLs.count {
                let isLast = i == imageURLs.count - 1
                let staticFrames = isLast ? slideFrameCount : max(slideFrameCount - transitionFrameCount, 1)
                totalEstimatedFrames += staticFrames
                if !isLast {
                    totalEstimatedFrames += transitionFrameCount
                }
            }
            
            // Loop state variables to maintain the current loaded image
            var currentCGImage: CGImage? = nil
            
            for index in 0..<imageURLs.count {
                // Periodically check for cancellation
                try Task.checkCancellation()
                
                let url = imageURLs[index]
                let isLast = index == imageURLs.count - 1
                
                // 1. Load current image (if not pre-loaded from the previous loop transition)
                let cgImage: CGImage
                if let preloaded = currentCGImage {
                    cgImage = preloaded
                } else {
                    guard let loaded = try Self.loadAndScaleImage(from: url, to: settings.size, scaleMode: settings.scaleMode) else {
                        writer.cancelWriting()
                        throw ImageToVideoRendererError.imageLoadingFailed(url)
                    }
                    cgImage = loaded
                }
                
                // 2. Write static frames
                let staticFrames = isLast ? slideFrameCount : max(slideFrameCount - transitionFrameCount, 1)
                
                for _ in 0..<staticFrames {
                    try Task.checkCancellation()
                    
                    let presentationTime = CMTime(value: frameIndex, timescale: fps)
                    
                    while !writerInput.isReadyForMoreMediaData {
                        try await Task.sleep(nanoseconds: 5_000_000) // 5ms sleep to free CPU
                    }
                    
                    let success = autoreleasepool { () -> Bool in
                        guard let pool = adaptor.pixelBufferPool,
                              let pixelBuffer = Self.createPixelBuffer(from: cgImage, size: settings.size, pool: pool) else {
                            return false
                        }
                        return adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                    }
                    
                    if !success {
                        let writerError = writer.error?.localizedDescription ?? "Pixel buffer append failed"
                        writer.cancelWriting()
                        throw ImageToVideoRendererError.frameRenderingFailed(Int(frameIndex), writerError)
                    }
                    
                    frameIndex += 1
                    
                    // Progress report
                    if let progressHandler = progressHandler {
                        let currentProgress = Double(frameIndex) / Double(totalEstimatedFrames)
                        await progressHandler(min(currentProgress, 0.99))
                    }
                }
                
                // 3. Write transition frames (crossfade blend) if there is a next image
                if !isLast {
                    let nextURL = imageURLs[index + 1]
                    guard let nextCGImage = try Self.loadAndScaleImage(from: nextURL, to: settings.size, scaleMode: settings.scaleMode) else {
                        writer.cancelWriting()
                        throw ImageToVideoRendererError.imageLoadingFailed(nextURL)
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
                            let writerError = writer.error?.localizedDescription ?? "Blended buffer append failed"
                            writer.cancelWriting()
                            throw ImageToVideoRendererError.frameRenderingFailed(Int(frameIndex), writerError)
                        }
                        
                        frameIndex += 1
                        
                        // Progress report
                        if let progressHandler = progressHandler {
                            let currentProgress = Double(frameIndex) / Double(totalEstimatedFrames)
                            await progressHandler(min(currentProgress, 0.99))
                        }
                    }
                    
                    // Promote next image to current image for the next loop run
                    currentCGImage = nextCGImage
                } else {
                    currentCGImage = nil
                }
            }
            
            writerInput.markAsFinished()
            await writer.finishWriting()
            
            if writer.status == .failed {
                let errorMsg = writer.error?.localizedDescription ?? "AVAssetWriter failed to finalize"
                throw ImageToVideoRendererError.writerFailed(errorMsg)
            }
            
            // Report completion progress
            if let progressHandler = progressHandler {
                await progressHandler(1.0)
            }
            
            logger.info("Slideshow video rendered successfully at: \(outputURL.lastPathComponent)")
        }.value
    }
    
    // MARK: - CoreGraphics Resizing & Downsampling
    
    /// Loads an image from a local URL and downsamples it using CGImageSource to prevent high memory spikes.
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
        
        // Aspect-fill/aspect-fit scale it to the exact target size
        return resizeCGImage(cgImage, to: targetSize, scaleMode: scaleMode)
    }
    
    /// Resizes a CGImage to exact target size using a background-thread-safe pure CoreGraphics context.
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
        
        // Fill background with black
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
    
    // MARK: - Pixel Buffer Generation
    
    /// Creates a CVPixelBuffer from a single CGImage, drawing it directly inside locked memory.
    private static func createPixelBuffer(from cgImage: CGImage, size: CGSize, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }
    
    /// Creates a blended CVPixelBuffer by crossfading from one CGImage to another using locked memory.
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
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        
        let rect = CGRect(origin: .zero, size: size)
        
        // Draw the base image
        context.draw(fromImage, in: rect)
        
        // Draw the incoming image with blending alpha opacity
        context.setAlpha(alpha)
        context.draw(toImage, in: rect)
        
        return buffer
    }
}
