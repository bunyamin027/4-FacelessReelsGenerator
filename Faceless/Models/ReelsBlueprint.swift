import Foundation

// MARK: - ReelsBlueprint

/// Represents the complete blueprint for generating a faceless reel video.
/// Contains format metadata, search parameters, and an ordered list of scenes.
struct ReelsBlueprint: Codable, Sendable {
    let format: String                    // POV, Listicle, Storytime
    let videoSearchKeyword: String        // English, max 3 words
    let audioMood: String                 // e.g. "energetic", "calm"
    let textAnimationStyle: String        // e.g. "typewriter", "karaoke"
    let scenes: [Scene]

    enum CodingKeys: String, CodingKey {
        case format
        case videoSearchKeyword = "video_search_keyword"
        case audioMood = "audio_mood"
        case textAnimationStyle = "text_animation_style"
        case scenes
    }
}

// MARK: - Scene

/// Represents a single scene within a reel, including its duration,
/// on-screen text overlay, and voiceover narration script.
struct Scene: Codable, Sendable {
    let duration: Double
    let onScreenText: String
    let voiceoverScript: String

    enum CodingKeys: String, CodingKey {
        case duration
        case onScreenText = "on_screen_text"
        case voiceoverScript = "voiceover_script"
    }
}
