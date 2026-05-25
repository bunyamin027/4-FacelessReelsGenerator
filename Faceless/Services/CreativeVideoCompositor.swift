//
//  CreativeVideoCompositor.swift
//  Faceless
//
//  Created on 2026-05-24.
//
//  GPU-accelerated video compositor utilizing Core Image to render
//  cinematic background blurs and composite foreground videos
//  inside a programmatic iPhone 15 device mockup.
//

import AVFoundation
import CoreImage
import UIKit
import OSLog

// MARK: - CreativeVideoCompositionInstruction

/// Holds parameters for a single render segment, mapping track IDs for background and mockup videos.
public final class CreativeVideoCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    public var timeRange: CMTimeRange
    public var enablePostProcessing: Bool = true
    public var containsTweening: Bool = false
    public var requiredSourceTrackIDs: [NSValue]?
    public var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    
    public var backgroundTrackID: CMPersistentTrackID?
    public var foregroundTrackID: CMPersistentTrackID?
    
    public init(
        timeRange: CMTimeRange,
        backgroundTrackID: CMPersistentTrackID,
        foregroundTrackID: CMPersistentTrackID?
    ) {
        self.timeRange = timeRange
        self.backgroundTrackID = backgroundTrackID
        self.foregroundTrackID = foregroundTrackID
        
        var trackIDs: [NSValue] = [NSNumber(value: backgroundTrackID)]
        if let fg = foregroundTrackID {
            trackIDs.append(NSNumber(value: fg))
        }
        self.requiredSourceTrackIDs = trackIDs
    }
}

// MARK: - CreativeVideoCompositor

/// GPU-accelerated video compositor that implements the custom video composition pipeline.
public final class CreativeVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.faceless.app", category: "CreativeVideoCompositor")
    
    // Reuse a single CIContext to optimize memory and performance
    private let context = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: NSNull()
    ])
    
    private let renderingQueue = DispatchQueue(label: "com.faceless.app.renderingQueue")
    
    public var sourcePixelBufferAttributes: [String : any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA] as any Sendable
    ]
    
    public var requiredPixelBufferAttributesForRenderContext: [String : any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA] as any Sendable
    ]
    
    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        logger.debug("Render context changed — size: \(newRenderContext.size.width)x\(newRenderContext.size.height)")
    }
    
    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderingQueue.async { [weak self] in
            guard let self else {
                request.finish(with: NSError(
                    domain: "CreativeVideoCompositor",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Compositor deallocated"]
                ))
                return
            }
            
            guard let instruction = request.videoCompositionInstruction as? CreativeVideoCompositionInstruction else {
                    request.finish(with: NSError(
                        domain: "CreativeVideoCompositor",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid composition instruction"]
                    ))
                    return
                }
                
                guard let destinationBuffer = request.renderContext.newPixelBuffer() else {
                    request.finish(with: NSError(
                        domain: "CreativeVideoCompositor",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to allocate destination buffer"]
                    ))
                    return
                }
                
                // 1. Resolve background video frame
                guard let bgTrackID = instruction.backgroundTrackID,
                      let bgBuffer = request.sourceFrame(byTrackID: bgTrackID) else {
                    request.finish(with: NSError(
                        domain: "CreativeVideoCompositor",
                        code: -4,
                        userInfo: [NSLocalizedDescriptionKey: "Missing background video track frame"]
                    ))
                    return
                }
                
                let renderSize = request.renderContext.size
                var finalImage = CIImage(cvPixelBuffer: bgBuffer)
                
                // Clean background size transformations if necessary to match render size
                let scaleX = renderSize.width / finalImage.extent.width
                let scaleY = renderSize.height / finalImage.extent.height
                let aspectFillScale = max(scaleX, scaleY)
                let bgTransform = CGAffineTransform(scaleX: aspectFillScale, y: aspectFillScale)
                    .concatenating(CGAffineTransform(
                        translationX: (renderSize.width - finalImage.extent.width * aspectFillScale) / 2,
                        y: (renderSize.height - finalImage.extent.height * aspectFillScale) / 2
                    ))
                finalImage = finalImage.transformed(by: bgTransform).cropped(to: CGRect(origin: .zero, size: renderSize))
                
                // Apply Dynamic "Cinematic Blur" (Gaussian Blur + Dimming)
                if let blurFilter = CIFilter(name: "CIGaussianBlur") {
                    blurFilter.setValue(finalImage, forKey: kCIInputImageKey)
                    blurFilter.setValue(35.0, forKey: kCIInputRadiusKey) // Premium deep blur
                    if let blurred = blurFilter.outputImage {
                        finalImage = blurred.cropped(to: CGRect(origin: .zero, size: renderSize))
                    }
                }
                
                if let dimFilter = CIFilter(name: "CIColorControls") {
                    dimFilter.setValue(finalImage, forKey: kCIInputImageKey)
                    dimFilter.setValue(-0.25, forKey: kCIInputBrightnessKey) // 25% Dimming
                    dimFilter.setValue(0.80, forKey: kCIInputSaturationKey)  // Subdued, premium colors
                    if let dimmed = dimFilter.outputImage {
                        finalImage = dimmed
                    }
                }
                
                // 2. Resolve foreground user media frame
                if let fgTrackID = instruction.foregroundTrackID,
                   let fgBuffer = request.sourceFrame(byTrackID: fgTrackID) {
                    
                    let fgImage = CIImage(cvPixelBuffer: fgBuffer)
                    
                    // Draw iPhone 15 frame overlay
                    let mockupFrame = self.drawIPhoneMockup(renderSize: renderSize)
                    
                    // Define iPhone dimensions & inner screen area
                    let phoneWidth: CGFloat = renderSize.width * 0.72 // Perfect size to pop
                    let phoneHeight: CGFloat = phoneWidth * (19.5 / 9.0) // 19.5:9 aspect ratio
                    let phoneX = (renderSize.width - phoneWidth) / 2.0
                    let phoneY = (renderSize.height - phoneHeight) / 2.0
                    
                    // Calculate bezel size
                    let bezelPercent: CGFloat = 0.035
                    let bezelWidth = phoneWidth * bezelPercent
                    
                    let screenX = phoneX + bezelWidth
                    let screenY = phoneY + bezelWidth
                    let screenWidth = phoneWidth - (bezelWidth * 2)
                    let screenHeight = phoneHeight - (bezelWidth * 2)
                    let screenRect = CGRect(x: screenX, y: screenY, width: screenWidth, height: screenHeight)
                    
                    // Fit screen recording inside mockup screen rect
                    let fgScaleX = screenWidth / fgImage.extent.width
                    let fgScaleY = screenHeight / fgImage.extent.height
                    let fgScale = max(fgScaleX, fgScaleY) // aspect-fill
                    
                    let scaledFgWidth = fgImage.extent.width * fgScale
                    let scaledFgHeight = fgImage.extent.height * fgScale
                    let fgOffsetX = screenX + (screenWidth - scaledFgWidth) / 2.0
                    let fgOffsetY = screenY + (screenHeight - scaledFgHeight) / 2.0
                    
                    let fgTransform = CGAffineTransform(translationX: -fgImage.extent.origin.x, y: -fgImage.extent.origin.y)
                        .concatenating(CGAffineTransform(scaleX: fgScale, y: fgScale))
                        .concatenating(CGAffineTransform(translationX: fgOffsetX, y: fgOffsetY))
                    
                    let transformedFg = fgImage.transformed(by: fgTransform).cropped(to: screenRect)
                    
                    // Generate rounded screen mask
                    let screenCornerRadius = phoneWidth * 0.09
                    let mask = self.makeRoundedMask(rect: screenRect, cornerRadius: screenCornerRadius)
                    
                    var compositeFg = transformedFg
                    if let blendFilter = CIFilter(name: "CIBlendWithMask") {
                        blendFilter.setValue(transformedFg, forKey: kCIInputImageKey)
                        blendFilter.setValue(finalImage, forKey: kCIInputBackgroundImageKey)
                        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)
                        if let output = blendFilter.outputImage {
                            compositeFg = output
                        }
                    }
                    
                    // Add the glossy device overlay
                    if let overlayFilter = CIFilter(name: "CISourceOverCompositing") {
                        overlayFilter.setValue(mockupFrame, forKey: kCIInputImageKey)
                        overlayFilter.setValue(compositeFg, forKey: kCIInputBackgroundImageKey)
                        if let output = overlayFilter.outputImage {
                            finalImage = output
                        }
                    }
                }
                
                self.context.render(finalImage, to: destinationBuffer)
                request.finish(withComposedVideoFrame: destinationBuffer)
        }
    }
    
    public func cancelAllPendingVideoCompositionRequests() {
        renderingQueue.sync(flags: .barrier) {}
    }
    
    // MARK: - Mockup Rendering Caching & Drawing
    
    private var mockupCache: [String: CIImage] = [:]
    private var maskCache: [String: CIImage] = [:]
    
    private func drawIPhoneMockup(renderSize: CGSize) -> CIImage {
        let key = "\(Int(renderSize.width))x\(Int(renderSize.height))"
        if let cached = mockupCache[key] {
            return cached
        }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        
        let image = renderer.image { context in
            let ctx = context.cgContext
            
            let phoneWidth = renderSize.width * 0.72
            let phoneHeight = phoneWidth * (19.5 / 9.0)
            let phoneX = (renderSize.width - phoneWidth) / 2.0
            let phoneY = (renderSize.height - phoneHeight) / 2.0
            let phoneRect = CGRect(x: phoneX, y: phoneY, width: phoneWidth, height: phoneHeight)
            
            let outerRadius = phoneWidth * 0.125
            
            // Draw elegant outer shadow
            ctx.saveGState()
            let shadowPath = UIBezierPath(roundedRect: phoneRect, cornerRadius: outerRadius).cgPath
            ctx.setShadow(offset: CGSize(width: 0, height: 20), blur: 36, color: UIColor.black.withAlphaComponent(0.65).cgColor)
            ctx.setFillColor(UIColor.clear.cgColor)
            ctx.addPath(shadowPath)
            ctx.fillPath()
            ctx.restoreGState()
            
            // Draw premium Titanium Chassis
            ctx.saveGState()
            let chassisPath = UIBezierPath(roundedRect: phoneRect, cornerRadius: outerRadius)
            ctx.setLineWidth(5.0)
            ctx.setStrokeColor(UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1.0).cgColor) // Titanium space-gray
            ctx.addPath(chassisPath.cgPath)
            ctx.strokePath()
            ctx.restoreGState()
            
            // Draw Inner Black Bezel
            ctx.saveGState()
            let bezelPercent: CGFloat = 0.035
            let bezelWidth = phoneWidth * bezelPercent
            let innerRect = phoneRect.insetBy(dx: bezelWidth / 2.0, dy: bezelWidth / 2.0)
            let innerRadius = outerRadius - (bezelWidth / 2.0)
            
            let bezelPath = UIBezierPath(roundedRect: innerRect, cornerRadius: innerRadius)
            ctx.setLineWidth(bezelWidth)
            ctx.setStrokeColor(UIColor.black.cgColor)
            ctx.addPath(bezelPath.cgPath)
            ctx.strokePath()
            ctx.restoreGState()
            
            // Draw Dynamic Island
            ctx.saveGState()
            let islandWidth = phoneWidth * 0.28
            let islandHeight = phoneWidth * 0.075
            let islandX = phoneX + (phoneWidth - islandWidth) / 2.0
            let islandY = phoneY + bezelWidth + (phoneWidth * 0.03)
            let islandRect = CGRect(x: islandX, y: islandY, width: islandWidth, height: islandHeight)
            let islandPath = UIBezierPath(roundedRect: islandRect, cornerRadius: islandHeight / 2.0)
            
            ctx.setFillColor(UIColor(red: 0.03, green: 0.03, blue: 0.03, alpha: 1.0).cgColor)
            ctx.addPath(islandPath.cgPath)
            ctx.fillPath()
            
            // Tiny camera reflection
            let lensRadius = islandHeight * 0.28
            let lensX = islandX + islandHeight * 0.6
            let lensY = islandY + islandHeight * 0.5
            ctx.setFillColor(UIColor(red: 0.08, green: 0.08, blue: 0.15, alpha: 1.0).cgColor)
            ctx.addArc(center: CGPoint(x: lensX, y: lensY), radius: lensRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            ctx.fillPath()
            
            ctx.setFillColor(UIColor.white.withAlphaComponent(0.18).cgColor)
            ctx.addArc(center: CGPoint(x: lensX + 1, y: lensY - 1), radius: lensRadius * 0.35, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            ctx.fillPath()
            ctx.restoreGState()
            
            // Glass Reflection Overlay
            ctx.saveGState()
            let screenRect = phoneRect.insetBy(dx: bezelWidth, dy: bezelWidth)
            let screenRadius = outerRadius - bezelWidth
            let screenPath = UIBezierPath(roundedRect: screenRect, cornerRadius: screenRadius)
            ctx.addPath(screenPath.cgPath)
            ctx.clip()
            
            // Slanted gradient glare
            let glarePath = UIBezierPath()
            glarePath.move(to: CGPoint(x: screenRect.minX - 100, y: screenRect.minY))
            glarePath.addLine(to: CGPoint(x: screenRect.maxX - 80, y: screenRect.minY))
            glarePath.addLine(to: CGPoint(x: screenRect.minX + 80, y: screenRect.maxY))
            glarePath.addLine(to: CGPoint(x: screenRect.minX - 100, y: screenRect.maxY))
            glarePath.close()
            
            let colors = [
                UIColor.white.withAlphaComponent(0.06).cgColor,
                UIColor.white.withAlphaComponent(0.0).cgColor
            ] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: screenRect.minX, y: screenRect.minY),
                end: CGPoint(x: screenRect.maxX, y: screenRect.minY),
                options: []
            )
            ctx.restoreGState()
        }
        
        let ciImage = CIImage(image: image)!
        mockupCache[key] = ciImage
        return ciImage
    }
    
    private func makeRoundedMask(rect: CGRect, cornerRadius: CGFloat) -> CIImage {
        let key = "\(Int(rect.width))x\(Int(rect.height))x\(Int(cornerRadius))"
        if let cached = maskCache[key] {
            return cached
        }
        
        // Render size matching the absolute size required for the mask
        let renderSize = CGSize(width: rect.maxX + 50, height: rect.maxY + 50)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        
        let image = renderer.image { context in
            let ctx = context.cgContext
            ctx.setFillColor(UIColor.black.cgColor) // Mask out
            ctx.fill(CGRect(origin: .zero, size: renderSize))
            
            ctx.setFillColor(UIColor.white.cgColor) // Keep screen
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            ctx.addPath(path.cgPath)
            ctx.fillPath()
        }
        
        let ciImage = CIImage(image: image)!
        maskCache[key] = ciImage
        return ciImage
    }
}
