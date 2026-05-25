//
//  VoiceoverGenerator.swift
//  Faceless
//
//  Generates TTS voiceover audio from scene scripts using AVSpeechSynthesizer.
//  Synthesizes each scene individually, then combines them into a single
//  .m4a file via AVMutableComposition + AVAssetExportSession.
//

import AVFoundation
import os.log

// MARK: - VoiceoverGenerator

/// On-device Text-to-Speech engine that uses `AVSpeechSynthesizer` to generate
/// voiceover audio files from scene scripts.
///
/// Usage:
/// ```swift
/// let generator = VoiceoverGenerator()
/// let audioURL = try await generator.generateVoiceover(for: scenes)
/// ```
final class VoiceoverGenerator: @unchecked Sendable {

    // MARK: - Types

    /// Errors specific to voiceover generation.
    enum VoiceoverError: LocalizedError {
        case emptyText
        case synthesisFailure(String)
        case noAudioBufferReceived
        case audioFileCreationFailed(String)
        case exportFailed(String)
        case exportCancelled
        case noAudioFiles
        case invalidAudioTrack(URL)

        var errorDescription: String? {
            switch self {
            case .emptyText:
                return "Cannot generate voiceover from empty text."
            case .synthesisFailure(let reason):
                return "Speech synthesis failed: \(reason)"
            case .noAudioBufferReceived:
                return "No audio buffer was received from the speech synthesizer."
            case .audioFileCreationFailed(let reason):
                return "Failed to create audio file: \(reason)"
            case .exportFailed(let reason):
                return "Audio export failed: \(reason)"
            case .exportCancelled:
                return "Audio export was cancelled."
            case .noAudioFiles:
                return "No audio files to combine."
            case .invalidAudioTrack(let url):
                return "Could not load audio track from: \(url.lastPathComponent)"
            }
        }
    }

    /// Configuration for TTS voice parameters.
    struct VoiceConfig: Sendable {
        /// Speech rate. 0.0 (slowest) to 1.0 (fastest).
        var rate: Float

        /// Pitch multiplier. 0.5 (low) to 2.0 (high). Default is 1.0.
        var pitch: Float

        /// Volume. 0.0 (silent) to 1.0 (loudest). Default is 1.0.
        var volume: Float

        /// BCP-47 language code. Default is Turkish (tr-TR).
        var language: String

        /// Pre-utterance delay in seconds.
        var preUtteranceDelay: TimeInterval

        /// Post-utterance delay in seconds.
        var postUtteranceDelay: TimeInterval

        /// Robotik varsayılan ayarlar
        static let `default` = VoiceConfig(
            rate: AVSpeechUtteranceDefaultSpeechRate,
            pitch: 1.0,
            volume: 1.0,
            language: "tr-TR",
            preUtteranceDelay: 0.0,
            postUtteranceDelay: 0.0
        )

        /// Reels'e optimize edilmiş doğal anlatıcı ayarları:
        /// - Daha yavaş rate → anlatıcı tonu
        /// - Biraz yüksek pitch → enerji ve canlılık
        /// - postUtteranceDelay → sahneler arası doğal nefes efekti
        static let reelsOptimized = VoiceConfig(
            rate: 0.48,
            pitch: 1.08,
            volume: 1.0,
            language: "tr-TR",
            preUtteranceDelay: 0.1,
            postUtteranceDelay: 0.4
        )
    }

    // MARK: - Properties

    /// Voice configuration used for all synthesis operations.
    var voiceConfig: VoiceConfig

    private let logger = Logger(subsystem: "com.faceless.app", category: "VoiceoverGenerator")

    /// Active synthesizers retained to prevent premature deallocation during asynchronous writing.
    @MainActor
    private var activeSynthesizers: [AVSpeechSynthesizer] = []

    // MARK: - Initialization

    /// Creates a new `VoiceoverGenerator`.
    /// - Parameter voiceConfig: Voice configuration. Defaults to `.reelsOptimized` for natural Reels sound.
    init(voiceConfig: VoiceConfig = .reelsOptimized) {
        self.voiceConfig = voiceConfig
        logger.info("VoiceoverGenerator initialized — rate: \(voiceConfig.rate), pitch: \(voiceConfig.pitch), lang: \(voiceConfig.language)")
    }

    // MARK: - Public API

    /// Generates a combined voiceover audio file for all scenes.
    ///
    /// This method:
    /// 1. Filters scenes with non-empty voiceover scripts.
    /// 2. Synthesizes speech for each scene sequentially.
    /// 3. Combines all individual audio files into a single output file.
    /// 4. Cleans up intermediate files.
    ///
    /// - Parameter scenes: Array of `Scene` objects containing voiceover scripts.
    /// - Returns: URL of the combined audio file (.m4a).
    /// - Throws: `VoiceoverError` if synthesis or combination fails.
    func generateVoiceover(for scenes: [Scene]) async throws -> URL {
        logger.info("Starting voiceover generation for \(scenes.count) scene(s).")

        // Filter out scenes with empty voiceover scripts
        let validScenes = scenes.filter {
            !$0.voiceoverScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !validScenes.isEmpty else {
            logger.error("No valid scenes with voiceover scripts found.")
            throw VoiceoverError.emptyText
        }

        logger.info("Generating voiceover for \(validScenes.count) valid scene(s).")

        // Generate individual audio files for each scene
        var audioFileURLs: [URL] = []

        for (index, scene) in validScenes.enumerated() {
            logger.info("Synthesizing scene \(index + 1)/\(validScenes.count)...")

            do {
                let url = try await synthesizeSpeech(
                    text: scene.voiceoverScript,
                    language: voiceConfig.language
                )
                audioFileURLs.append(url)
                logger.info("Scene \(index + 1) synthesis complete: \(url.lastPathComponent)")
            } catch {
                logger.error("Failed to synthesize scene \(index + 1): \(error.localizedDescription)")
                cleanUpFiles(audioFileURLs)
                throw error
            }
        }

        // Combine all audio files into a single .m4a
        do {
            let combinedURL = try await combineAudioFiles(audioFileURLs)
            logger.info("Combined voiceover ready: \(combinedURL.lastPathComponent)")

            // Clean up intermediate .caf files
            cleanUpFiles(audioFileURLs)

            return combinedURL
        } catch {
            logger.error("Failed to combine audio files: \(error.localizedDescription)")
            cleanUpFiles(audioFileURLs)
            throw error
        }
    }

    func synthesizeSpeech(text: String, language: String? = nil) async throws -> URL {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            throw VoiceoverError.emptyText
        }

        logger.info("Using completely offline, free Apple Premium Voices for TTS.")
        let outputURL = TempFileManager.shared.uniqueTempURL(extension: "caf")
        
        let utterance = AVSpeechUtterance(string: trimmedText)
        utterance.rate = voiceConfig.rate
        utterance.pitchMultiplier = voiceConfig.pitch
        utterance.volume = voiceConfig.volume
        utterance.preUtteranceDelay = voiceConfig.preUtteranceDelay
        utterance.postUtteranceDelay = voiceConfig.postUtteranceDelay

        let lang = language ?? voiceConfig.language
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // Find best quality available offline voice (Premium > Enhanced > Default)
        let premiumVoice = voices.first(where: { $0.language == lang && $0.quality == .premium }) ??
                           voices.first(where: { $0.language == lang && $0.quality == .enhanced }) ??
                           AVSpeechSynthesisVoice(language: lang)
        
        if let voice = premiumVoice {
            utterance.voice = voice
            logger.info("Selected Voice: \(voice.name) (Quality: \(voice.quality == .premium ? "Premium" : (voice.quality == .enhanced ? "Enhanced" : "Default")))")
        } else {
            logger.warning("No voice found for language '\(lang)'. Using default voice.")
        }

        return try await performLocalSynthesis(utterance: utterance, outputURL: outputURL)
    }

    /// Performs local speech synthesis using AVSpeechSynthesizer on the main actor.
    @MainActor
    private func performLocalSynthesis(
        utterance: AVSpeechUtterance,
        outputURL: URL
    ) async throws -> URL {
        #if targetEnvironment(simulator)
        logger.info("Simulator detected. Creating a mock silent audio file for voiceover to prevent hanging.")
        do {
            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false) else {
                throw VoiceoverError.audioFileCreationFailed("Failed to create AVAudioFormat")
            }
            let audioFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100) else {
                throw VoiceoverError.audioFileCreationFailed("Failed to create AVAudioPCMBuffer")
            }
            buffer.frameLength = 44100
            // Buffer is zero-initialized by default (silence)
            try audioFile.write(from: buffer)
            return outputURL
        } catch {
            logger.error("Failed to create mock audio file: \(error.localizedDescription)")
            throw VoiceoverError.audioFileCreationFailed(error.localizedDescription)
        }
        #else
        let synthesizer = AVSpeechSynthesizer()
        activeSynthesizers.append(synthesizer)
        defer {
            activeSynthesizers.removeAll { $0 === synthesizer }
        }

        return try await withCheckedThrowingContinuation { continuation in
            var audioFile: AVAudioFile?
            var hasResumed = false

            synthesizer.write(utterance) { [logger, synthesizer] buffer in
                // Keep reference to synthesizer inside closure to prevent it from being deallocated
                // until synthesis completes or calls fail/finish.
                let _ = synthesizer

                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    if !hasResumed {
                        hasResumed = true
                        if audioFile != nil {
                            continuation.resume(returning: outputURL)
                        } else {
                            continuation.resume(
                                throwing: VoiceoverError.noAudioBufferReceived
                            )
                        }
                    }
                    return
                }

                guard pcmBuffer.frameLength > 1 else {
                    if !hasResumed {
                        hasResumed = true
                        if audioFile != nil {
                            continuation.resume(returning: outputURL)
                        } else {
                            continuation.resume(
                                throwing: VoiceoverError.noAudioBufferReceived
                            )
                        }
                    }
                    return
                }

                if audioFile == nil {
                    do {
                        audioFile = try AVAudioFile(
                            forWriting: outputURL,
                            settings: pcmBuffer.format.settings,
                            commonFormat: pcmBuffer.format.commonFormat,
                            interleaved: pcmBuffer.format.isInterleaved
                        )
                    } catch {
                        logger.error("Audio file creation failed: \(error.localizedDescription)")
                        if !hasResumed {
                            hasResumed = true
                            continuation.resume(
                                throwing: VoiceoverError.audioFileCreationFailed(
                                    error.localizedDescription
                                )
                            )
                        }
                        return
                    }
                }

                do {
                    try audioFile?.write(from: pcmBuffer)
                } catch {
                    logger.error("Buffer write failed: \(error.localizedDescription)")
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(
                            throwing: VoiceoverError.synthesisFailure(error.localizedDescription)
                        )
                    }
                }
            }
        }
        #endif
    }

    /// Combines multiple audio files into a single `.m4a` file using `AVMutableComposition`.
    ///
    /// - Parameter urls: Array of audio file URLs to combine in order.
    /// - Returns: URL of the combined `.m4a` file.
    /// - Throws: `VoiceoverError` if combination fails.
    func combineAudioFiles(_ urls: [URL]) async throws -> URL {
        guard !urls.isEmpty else {
            throw VoiceoverError.noAudioFiles
        }

        logger.info("Combining \(urls.count) audio file(s) into single track...")

        let composition = AVMutableComposition()

        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VoiceoverError.exportFailed("Could not create composition audio track.")
        }

        var currentTime = CMTime.zero

        for (index, url) in urls.enumerated() {
            let asset = AVURLAsset(url: url)

            // Load tracks asynchronously (iOS 16+)
            let tracks = try await asset.loadTracks(withMediaType: .audio)

            guard let assetTrack = tracks.first else {
                logger.error("No audio track in file \(index + 1): \(url.lastPathComponent)")
                throw VoiceoverError.invalidAudioTrack(url)
            }

            let duration = try await asset.load(.duration)
            let timeRange = CMTimeRange(start: .zero, duration: duration)

            do {
                try compositionTrack.insertTimeRange(timeRange, of: assetTrack, at: currentTime)
                currentTime = CMTimeAdd(currentTime, duration)
                logger.debug("Inserted track \(index + 1), duration: \(CMTimeGetSeconds(duration))s")
            } catch {
                throw VoiceoverError.exportFailed(
                    "Failed to insert track \(index + 1): \(error.localizedDescription)"
                )
            }
        }

        // Export the composition to .m4a
        let outputURL = TempFileManager.shared.uniqueTempURL(extension: "m4a")

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw VoiceoverError.exportFailed("Could not create export session.")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        logger.info("Exporting combined audio → \(outputURL.lastPathComponent)")

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            let totalSeconds = CMTimeGetSeconds(currentTime)
            logger.info("Export completed — total duration: \(totalSeconds)s")
            return outputURL

        case .failed:
            let errorMessage = exportSession.error?.localizedDescription ?? "Unknown error"
            logger.error("Export failed: \(errorMessage)")
            throw VoiceoverError.exportFailed(errorMessage)

        case .cancelled:
            logger.warning("Export was cancelled.")
            throw VoiceoverError.exportCancelled

        default:
            throw VoiceoverError.exportFailed(
                "Unexpected export status: \(exportSession.status.rawValue)"
            )
        }
    }



    // MARK: - Private — Cleanup

    /// Removes specific temporary files.
    private func cleanUpFiles(_ urls: [URL]) {
        let fm = FileManager.default
        for url in urls {
            do {
                if fm.fileExists(atPath: url.path) {
                    try fm.removeItem(at: url)
                    logger.debug("Cleaned up: \(url.lastPathComponent)")
                }
            } catch {
                logger.warning("Cleanup failed for \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
