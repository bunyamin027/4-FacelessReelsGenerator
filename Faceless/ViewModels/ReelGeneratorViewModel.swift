// ReelGeneratorViewModel.swift
// Faceless
//
// Main ViewModel that orchestrates the reel generation pipeline.

import SwiftUI
import AVFoundation
import Combine
import os.log

// MARK: - ReelGeneratorViewModel

/// Orchestrates the complete reel generation pipeline, managing phase transitions,
/// progress tracking, and error handling for the UI layer.
@MainActor
class ReelGeneratorViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// User's topic input for generating the reel
    @Published var topicInput: String = ""
    
    /// Current phase of the generation pipeline
    @Published var currentPhase: GenerationPhase = .idle
    
    /// Error message to display to the user
    @Published var errorMessage: String?
    
    /// URL to the final generated video (or audio in Sprint 1 fallback)
    @Published var generatedVideoURL: URL?
    
    /// URL to the generated voiceover audio
    @Published var generatedAudioURL: URL?
    
    /// Controls whether the preview screen is shown
    @Published var isShowingPreview: Bool = false
    
    /// Whether a generation is currently in progress
    @Published var isGenerating: Bool = false
    
    /// Progress value from 0.0 to 1.0
    @Published var progressValue: Double = 0
    
    /// The loaded blueprint for the current generation
    @Published var currentBlueprint: ReelsBlueprint?
    
    // MARK: - Services
    
    private let voiceoverGenerator = VoiceoverGenerator()
    private let reelsRenderer = ReelsRenderer()
    private let blueprintService = BlueprintService()
    private let videoFetcher = VideoFetcher.shared
    private let autoUploader = AutoUploader.shared
    private let logger = Logger(subsystem: "com.faceless.app", category: "ReelGeneratorVM")
    
    // MARK: - Generation Task
    
    /// Reference to the current generation task for cancellation support
    private var generationTask: Task<Void, Never>?
    
    // MARK: - Generation Pipeline
    
    /// Starts the full reel generation pipeline.
    /// In Sprint 1, this loads a mock blueprint, generates TTS voiceover,
    /// and falls back gracefully when no source video is available.
    func generateReel() {
        guard !topicInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Lütfen bir konu girin."
            return
        }
        
        // Cancel any existing generation
        generationTask?.cancel()
        
        generationTask = Task { [weak self] in
            guard let self else { return }
            
            await self.runPipeline()
        }
    }
    
    /// The actual async pipeline execution
    private func runPipeline() async {
        // Reset state
        isGenerating = true
        errorMessage = nil
        generatedVideoURL = nil
        generatedAudioURL = nil
        progressValue = 0
        
        do {
            // ── Phase 1: Load Blueprint ──────────────────────────
            try Task.checkCancellation()
            await transitionTo(.creatingBlueprint)
            
            let blueprint = try await blueprintService.generateBlueprint(for: topicInput)
            currentBlueprint = blueprint
            logger.info("Blueprint loaded — \(blueprint.scenes.count) scenes, format: \(blueprint.format)")
            
            // ── Phase 2: Fetch Video ───────────────────────────────
            try Task.checkCancellation()
            await transitionTo(.fetchingVideo)
            
            let sourceVideoURL = try await videoFetcher.fetchVideo(for: blueprint.videoSearchKeyword)
            logger.info("Video fetched at: \(sourceVideoURL.lastPathComponent)")
            
            // ── Phase 3: Generate Voiceover ──────────────────────
            try Task.checkCancellation()
            currentPhase = .generatingVoiceover
            progressValue = currentPhase.progress
            let audioURL = try await voiceoverGenerator.generateVoiceover(for: blueprint.scenes)
            generatedAudioURL = audioURL
            logger.info("Voiceover generated at: \(audioURL.lastPathComponent)")
            
            // ── Phase 4: Render Video ────────────────────────────
            try Task.checkCancellation()
            await transitionTo(.rendering)
            
            let videoURL = try await reelsRenderer.renderReel(
                videoURL: sourceVideoURL,
                audioURL: audioURL,
                scenes: blueprint.scenes,
                resolution: .hd1080,
                watermarkText: "Made with Faceless ✨" // TODO: Feature gate in Sprint 3
            )
            
            logger.info("Video rendered at: \(videoURL.lastPathComponent)")
            
            // ── Completed ────────────────────────────────────────
            try Task.checkCancellation()
            await transitionTo(.completed)
            
            generatedVideoURL = videoURL
            isShowingPreview = true
            
            logger.info("Generation pipeline completed successfully")
            
        } catch is CancellationError {
            logger.info("Generation cancelled by user")
            await transitionTo(.idle)
            errorMessage = nil
            
        } catch {
            logger.error("Generation failed: \(error.localizedDescription)")
            await transitionTo(.failed)
            errorMessage = error.localizedDescription
        }
        
        isGenerating = false
    }
    
    // MARK: - Phase Transitions
    
    /// Smoothly transitions to the next phase with animated progress updates
    private func transitionTo(_ phase: GenerationPhase) async {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPhase = phase
            progressValue = phase.progress
        }
        logger.debug("Phase → \(phase.rawValue)")
    }
    
    // MARK: - Blueprint Loading
    
    /// Loads the mock blueprint from the app bundle.
    /// In production, this will be replaced with an API call to generate blueprints.
    private func loadMockBlueprint() throws -> ReelsBlueprint {
        guard let url = Bundle.main.url(forResource: "mock_blueprint", withExtension: "json") else {
            throw FacelessError.blueprintNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ReelsBlueprint.self, from: data)
    }
    
    // MARK: - Cancel
    
    /// Cancels the current generation pipeline
    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        
        withAnimation {
            isGenerating = false
            currentPhase = .idle
            progressValue = 0
        }
        
        logger.info("Generation cancelled by user")
    }
    
    // MARK: - Reset
    
    /// Resets all state to initial values, ready for a new generation
    func reset() {
        generationTask?.cancel()
        generationTask = nil
        
        withAnimation(.easeInOut(duration: 0.3)) {
            topicInput = ""
            currentPhase = .idle
            errorMessage = nil
            generatedVideoURL = nil
            generatedAudioURL = nil
            isShowingPreview = false
            isGenerating = false
            progressValue = 0
            currentBlueprint = nil
        }
        
        // Clean up temp files from previous generation
        TempFileManager.shared.cleanupTempFiles()
    }
}

// MARK: - FacelessError

/// Domain-specific errors for the Faceless app pipeline
enum FacelessError: LocalizedError {
    case blueprintNotFound
    case emptyTopic
    case videoFetchFailed(String)
    case renderFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .blueprintNotFound:
            return "Senaryo dosyası bulunamadı. Lütfen uygulamayı yeniden yükleyin."
        case .emptyTopic:
            return "Lütfen bir konu girin."
        case .videoFetchFailed(let reason):
            return "Video alınamadı: \(reason)"
        case .renderFailed(let reason):
            return "Video oluşturulamadı: \(reason)"
        }
    }
}
