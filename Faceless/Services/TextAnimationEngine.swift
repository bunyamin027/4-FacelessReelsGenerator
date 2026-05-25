//
//  TextAnimationEngine.swift
//  Faceless
//
//  Created on 2026-05-24.
//
//  Generates premium animated CALayers for video overlay rendering.
//  Supports CapCut-style effects: Karaoke (color sweep), Typewriter (clip reveal),
//  and Pop-up (scale bounce).
//

import UIKit
import QuartzCore
import AVFoundation

public final class TextAnimationEngine {
    
    // MARK: - Layout Constants
    
    private enum Constants {
        static let textHorizontalPadding: CGFloat = 36
        static let textBottomOffset: CGFloat = 220
        static let textCornerRadius: CGFloat = 16
        static let textInternalPadding: CGFloat = 20
        static let textBackgroundAlpha: CGFloat = 0.70
        static let textFontSize: CGFloat = 58
        static let fadeDuration: CFTimeInterval = 0.25
    }
    
    public init() {}
    
    // MARK: - Public Layer Factory
    
    /// Creates an animated text layer hierarchy for a scene.
    ///
    /// - Parameters:
    ///   - text: The subtitle text to display.
    ///   - style: The style of animation ("karaoke", "typewriter", or "popup").
    ///   - startTime: The time in seconds when this layer should appear.
    ///   - duration: The duration in seconds the text should remain on screen.
    ///   - renderSize: The target canvas size (e.g. 1080x1920).
    /// - Returns: A fully configured and animated CALayer ready for AVVideoCompositionCoreAnimationTool.
    public func makeAnimatedTextLayer(
        text: String,
        style: String,
        startTime: CFTimeInterval,
        duration: CFTimeInterval,
        renderSize: CGSize
    ) -> CALayer {
        
        let endTime = startTime + duration
        let padding = Constants.textInternalPadding
        let fontSize = Constants.textFontSize
        
        // 1. Core container layer with premium dark styling
        let containerLayer = CALayer()
        containerLayer.backgroundColor = UIColor.black.withAlphaComponent(Constants.textBackgroundAlpha).cgColor
        containerLayer.cornerRadius = Constants.textCornerRadius
        containerLayer.masksToBounds = true
        containerLayer.opacity = 0.0 // Managed by fade animation
        
        // Add premium border glow
        containerLayer.borderWidth = 1.5
        containerLayer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        
        // 2. Measure & Layout
        let maxTextWidth = renderSize.width - (Constants.textHorizontalPadding * 2) - (padding * 2)
        let maxTextHeight = renderSize.height * 0.35
        let textSize = estimateTextSize(text, fontSize: fontSize, maxWidth: maxTextWidth, maxHeight: maxTextHeight)
        
        let containerWidth = textSize.width + (padding * 2)
        let containerHeight = textSize.height + (padding * 2)
        let containerX = (renderSize.width - containerWidth) / 2.0
        let containerY = renderSize.height - Constants.textBottomOffset - containerHeight
        
        containerLayer.frame = CGRect(x: containerX, y: containerY, width: containerWidth, height: containerHeight)
        
        let textRect = CGRect(x: padding, y: padding, width: textSize.width, height: textSize.height)
        
        // 3. Build & Apply Animations based on selected style
        let normalizedStyle = style.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch normalizedStyle {
        case "karaoke":
            setupKaraokeStyle(text: text, frame: textRect, container: containerLayer, startTime: startTime, duration: duration)
        case "typewriter":
            setupTypewriterStyle(text: text, frame: textRect, container: containerLayer, startTime: startTime, duration: duration)
        case "popup":
            setupPopupStyle(text: text, frame: textRect, container: containerLayer, startTime: startTime, duration: duration)
        default:
            // Fallback to popup if unspecified
            setupPopupStyle(text: text, frame: textRect, container: containerLayer, startTime: startTime, duration: duration)
        }
        
        // 4. Apply general lifetime fade animations (fade in / out)
        addFadeAnimations(to: containerLayer, startTime: startTime, endTime: endTime)
        
        return containerLayer
    }
    
    // MARK: - Style Configurations
    
    /// Karaoke Style: Base white text with a yellow text overlay that sweeps from left to right
    private func setupKaraokeStyle(
        text: String,
        frame: CGRect,
        container: CALayer,
        startTime: CFTimeInterval,
        duration: CFTimeInterval
    ) {
        // Base white text layer
        let baseTextLayer = makeTextLayer(text: text, frame: frame, color: .white)
        container.addSublayer(baseTextLayer)
        
        // Overlay yellow text layer
        let highlightedColor = UIColor(red: 254.0/255.0, green: 240.0/255.0, blue: 138.0/255.0, alpha: 1.0) // Soft neon yellow
        let highlightTextLayer = makeTextLayer(text: text, frame: frame, color: highlightedColor)
        
        // Mask layer that sweeps across from left to right
        let maskLayer = CALayer()
        maskLayer.backgroundColor = UIColor.white.cgColor
        maskLayer.frame = CGRect(x: 0, y: 0, width: 0, height: frame.height)
        highlightTextLayer.mask = maskLayer
        container.addSublayer(highlightTextLayer)
        
        // Animate the mask bounds to reveal the yellow overlay
        let sweepAnim = CABasicAnimation(keyPath: "bounds.size.width")
        sweepAnim.fromValue = 0.0
        sweepAnim.toValue = frame.width
        sweepAnim.beginTime = AVCoreAnimationBeginTimeAtZero + startTime + Constants.fadeDuration
        sweepAnim.duration = duration - (Constants.fadeDuration * 2)
        sweepAnim.fillMode = .forwards
        sweepAnim.isRemovedOnCompletion = false
        sweepAnim.timingFunction = CAMediaTimingFunction(name: .linear)
        maskLayer.add(sweepAnim, forKey: "karaokeSweep")
        
        // Animate mask position to match the width expansion (anchorPoint is 0.5, 0.5 by default)
        let posAnim = CABasicAnimation(keyPath: "position.x")
        posAnim.fromValue = 0.0
        posAnim.toValue = frame.width / 2.0
        posAnim.beginTime = AVCoreAnimationBeginTimeAtZero + startTime + Constants.fadeDuration
        posAnim.duration = duration - (Constants.fadeDuration * 2)
        posAnim.fillMode = .forwards
        posAnim.isRemovedOnCompletion = false
        posAnim.timingFunction = CAMediaTimingFunction(name: .linear)
        maskLayer.add(posAnim, forKey: "karaokeSweepPosition")
    }
    
    /// Typewriter Style: Reveals character by character by expanding a clipping mask horizontally
    private func setupTypewriterStyle(
        text: String,
        frame: CGRect,
        container: CALayer,
        startTime: CFTimeInterval,
        duration: CFTimeInterval
    ) {
        let textLayer = makeTextLayer(text: text, frame: frame, color: .white)
        
        // Clipping mask
        let maskLayer = CALayer()
        maskLayer.backgroundColor = UIColor.white.cgColor
        maskLayer.frame = CGRect(x: 0, y: 0, width: 0, height: frame.height)
        textLayer.mask = maskLayer
        container.addSublayer(textLayer)
        
        // Stepwise typewriter effect (using multiple keyframes to simulate character jumps)
        let steps = min(text.count, 45) // Cap steps to prevent massive animation data
        var keyTimes: [NSNumber] = []
        var values: [NSNumber] = []
        
        for i in 0...steps {
            keyTimes.append(NSNumber(value: Double(i) / Double(steps)))
            values.append(NSNumber(value: Double(i) / Double(steps) * frame.width))
        }
        
        let typeAnim = CAKeyframeAnimation(keyPath: "bounds.size.width")
        typeAnim.values = values
        typeAnim.keyTimes = keyTimes
        typeAnim.beginTime = AVCoreAnimationBeginTimeAtZero + startTime + Constants.fadeDuration
        typeAnim.duration = min(duration * 0.7, 3.5) // Finish typing before scene ends
        typeAnim.fillMode = .forwards
        typeAnim.isRemovedOnCompletion = false
        typeAnim.calculationMode = .discrete // Sharp jumps for typing look
        maskLayer.add(typeAnim, forKey: "typewriterBounds")
        
        let posAnim = CAKeyframeAnimation(keyPath: "position.x")
        posAnim.values = values.map { NSNumber(value: $0.doubleValue / 2.0) }
        posAnim.keyTimes = keyTimes
        posAnim.beginTime = AVCoreAnimationBeginTimeAtZero + startTime + Constants.fadeDuration
        posAnim.duration = min(duration * 0.7, 3.5)
        posAnim.fillMode = .forwards
        posAnim.isRemovedOnCompletion = false
        posAnim.calculationMode = .discrete
        maskLayer.add(posAnim, forKey: "typewriterPosition")
    }
    
    /// Pop-up Style: Word bounces up with an elastic spring animation on appearance
    private func setupPopupStyle(
        text: String,
        frame: CGRect,
        container: CALayer,
        startTime: CFTimeInterval,
        duration: CFTimeInterval
    ) {
        // Soft gradient text color style using standard white
        let textLayer = makeTextLayer(text: text, frame: frame, color: .white)
        container.addSublayer(textLayer)
        
        // Elastic scale bounce animation
        let scaleAnim = CAKeyframeAnimation(keyPath: "transform.scale")
        scaleAnim.values = [0.1, 1.15, 0.95, 1.0]
        scaleAnim.keyTimes = [0.0, 0.4, 0.75, 1.0]
        scaleAnim.beginTime = AVCoreAnimationBeginTimeAtZero + startTime
        scaleAnim.duration = 0.45
        scaleAnim.fillMode = .forwards
        scaleAnim.isRemovedOnCompletion = false
        scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        container.add(scaleAnim, forKey: "scaleBounce")
    }
    
    // MARK: - Layer Construction Helpers
    
    private func makeTextLayer(text: String, frame: CGRect, color: UIColor) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.frame = frame
        textLayer.string = makeAttributedText(text, fontSize: Constants.textFontSize, color: color)
        textLayer.isWrapped = true
        textLayer.alignmentMode = .center
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.truncationMode = .end
        return textLayer
    }
    
    private func makeAttributedText(_ text: String, fontSize: CGFloat, color: UIColor) -> NSAttributedString {
        // Using System Bold for high readability, can be changed to premium font family
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineHeightMultiple = 1.15
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        
        return NSAttributedString(string: text, attributes: attributes)
    }
    
    private func estimateTextSize(_ text: String, fontSize: CGFloat, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
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
    
    private func addFadeAnimations(to layer: CALayer, startTime: CFTimeInterval, endTime: CFTimeInterval) {
        // Fade In
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 1.0
        fadeIn.beginTime = AVCoreAnimationBeginTimeAtZero + startTime
        fadeIn.duration = Constants.fadeDuration
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        layer.add(fadeIn, forKey: "fadeIn")
        
        // Fade Out
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.beginTime = AVCoreAnimationBeginTimeAtZero + endTime - Constants.fadeDuration
        fadeOut.duration = Constants.fadeDuration
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        layer.add(fadeOut, forKey: "fadeOut")
    }
}
