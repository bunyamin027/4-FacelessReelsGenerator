// ReelGeneratorViewModel.swift
// Faceless
//
// Main ViewModel that orchestrates the reel generation pipeline.

import SwiftUI
import AVFoundation
import Combine
import UIKit
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
    
    /// User selected image URLs for slideshow composition
    @Published var userSelectedImageURLs: [URL] = []
    
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
    /// Starts the full reel generation pipeline.
    /// - Parameter isPro: Whether the user has a pro subscription. Determines watermark.
    func generateReel(isPro: Bool) {
        guard !topicInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Lütfen bir konu girin."
            return
        }
        
        // Cancel any existing generation
        generationTask?.cancel()
        
        generationTask = Task { [weak self] in
            guard let self else { return }
            
            await self.runPipeline(isPro: isPro)
        }
    }
    
    /// The actual async pipeline execution
    private func runPipeline(isPro: Bool) async {
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
            
            // Extract keywords for each scene
            let keywords = blueprint.scenes.map { $0.videoSearchKeyword }
            let sourceVideoURLs = try await videoFetcher.fetchVideos(for: keywords)
            logger.info("\(sourceVideoURLs.count) videos fetched.")
            
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
                videoURLs: sourceVideoURLs,
                audioURL: audioURL,
                userSelectedImageURLs: self.userSelectedImageURLs,
                scenes: blueprint.scenes,
                textAnimationStyle: blueprint.textAnimationStyle,
                resolution: .hd1080,
                watermarkText: isPro ? nil : "Made with Faceless ✨"
            )
            
            logger.info("Video rendered at: \(videoURL.lastPathComponent)")
            
            // ── Completed ────────────────────────────────────────
            try Task.checkCancellation()
            await transitionTo(.completed)
            
            // Videoyu kalıcı olarak Documents'a kaydet + geçmişe ekle
            let permanentURL = VideoHistoryManager.shared.saveVideo(
                tempURL: videoURL,
                topic: self.topicInput
            )
            
            generatedVideoURL = permanentURL ?? videoURL
            isShowingPreview = true
            
            logger.info("Generation pipeline completed — saved to: \(self.generatedVideoURL?.lastPathComponent ?? "nil")")
            
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
            userSelectedImageURLs = []
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
    case minImagesNotMet
    case slideshowCreationFailed(String)
    
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
        case .minImagesNotMet:
            return "Slayt gösterisi için en az 2 resim gereklidir."
        case .slideshowCreationFailed(let reason):
            return "Slayt gösterisi oluşturulamadı: \(reason)"
        }
    }
}
//
//  VideoHistoryManager.swift
//  Faceless
//
//  Manages persistent storage of generated video history using UserDefaults.
//  Provides CRUD operations for the "Son Oluşturulanlar" list on HomeView.
//

import Foundation
import os.log

// MARK: - VideoHistoryItem

/// Represents a single generated video entry in the history.
struct VideoHistoryItem: Codable, Identifiable {
    let id: String
    let topic: String
    let dateCreated: Date
    let fileName: String

    /// Resolves the full file URL from Documents directory.
    var fileURL: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let docsDir = docs else { return nil }
        let url = docsDir.appendingPathComponent("GeneratedVideos").appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Formatted date string for display.
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: dateCreated, relativeTo: Date())
    }
}

// MARK: - VideoHistoryManager

/// Singleton that persists generated video metadata to UserDefaults
/// and copies video files to the Documents directory for long-term storage.
@MainActor
final class VideoHistoryManager: ObservableObject {

    static let shared = VideoHistoryManager()

    @Published private(set) var items: [VideoHistoryItem] = []

    private let userDefaultsKey = "faceless_video_history"
    private let maxHistoryCount = 20
    private let logger = Logger(subsystem: "com.faceless.app", category: "VideoHistory")

    private init() {
        loadItems()
    }

    // MARK: - Public API

    /// Copies the video from temp to Documents and saves the entry.
    /// Returns the new permanent URL.
    @discardableResult
    func saveVideo(tempURL: URL, topic: String) -> URL? {
        let fm = FileManager.default

        // Ensure GeneratedVideos directory exists
        guard let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.error("Could not find Documents directory")
            return nil
        }

        let videosDir = docsDir.appendingPathComponent("GeneratedVideos")
        if !fm.fileExists(atPath: videosDir.path) {
            do {
                try fm.createDirectory(at: videosDir, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create GeneratedVideos directory: \(error.localizedDescription)")
                return nil
            }
        }

        // Generate unique filename
        let fileName = "Faceless_\(UUID().uuidString.prefix(8)).mp4"
        let destinationURL = videosDir.appendingPathComponent(fileName)

        // Copy file (not move — temp cleanup handles original)
        do {
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.copyItem(at: tempURL, to: destinationURL)
            logger.info("Video saved to: \(destinationURL.lastPathComponent)")
        } catch {
            logger.error("Failed to copy video: \(error.localizedDescription)")
            return nil
        }

        // Create history item
        let item = VideoHistoryItem(
            id: UUID().uuidString,
            topic: topic,
            dateCreated: Date(),
            fileName: fileName
        )

        // Add to beginning of list, enforce max count
        items.insert(item, at: 0)
        if items.count > maxHistoryCount {
            // Remove oldest items and their files
            let removed = items.suffix(from: maxHistoryCount)
            for old in removed {
                if let url = old.fileURL {
                    try? fm.removeItem(at: url)
                }
            }
            items = Array(items.prefix(maxHistoryCount))
        }

        persistItems()
        return destinationURL
    }

    /// Removes a specific history item and its file.
    func removeItem(_ item: VideoHistoryItem) {
        if let url = item.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        items.removeAll { $0.id == item.id }
        persistItems()
    }

    /// Clears all history.
    func clearAll() {
        for item in items {
            if let url = item.fileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        items.removeAll()
        persistItems()
    }

    // MARK: - Private

    private func loadItems() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            items = []
            return
        }
        do {
            let decoded = try JSONDecoder().decode([VideoHistoryItem].self, from: data)
            // Filter out items whose files no longer exist
            items = decoded.filter { $0.fileURL != nil }
            let count = items.count
            logger.info("Loaded \(count) history item(s)")
        } catch {
            logger.error("Failed to decode history: \(error.localizedDescription)")
            items = []
        }
    }

    private func persistItems() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            let count = items.count
            logger.debug("Persisted \(count) history item(s)")
        } catch {
            logger.error("Failed to encode history: \(error.localizedDescription)")
        }
    }
}
