import Foundation

// MARK: - GenerationPhase

/// Tracks the current phase of the video generation pipeline.
/// Each phase has a localized display name, progress value, and SF Symbol icon.
enum GenerationPhase: String, CaseIterable, Sendable {
    case idle = "Hazır"
    case creatingBlueprint = "Senaryo Oluşturuluyor..."
    case fetchingVideo = "Video Aranıyor..."
    case generatingVoiceover = "Seslendirme Üretiliyor..."
    case rendering = "Video Render Ediliyor..."
    case uploading = "Yükleniyor..."
    case publishing = "Yayınlanıyor..."
    case completed = "Tamamlandı!"
    case failed = "Hata Oluştu"

    /// Normalized progress value (0.0 – 1.0) for the current phase.
    var progress: Double {
        switch self {
        case .idle: return 0
        case .creatingBlueprint: return 0.15
        case .fetchingVideo: return 0.30
        case .generatingVoiceover: return 0.50
        case .rendering: return 0.75
        case .uploading: return 0.85
        case .publishing: return 0.95
        case .completed: return 1.0
        case .failed: return 0
        }
    }

    /// SF Symbol name representing this phase visually.
    var systemIconName: String {
        switch self {
        case .idle: return "play.circle"
        case .creatingBlueprint: return "doc.text"
        case .fetchingVideo: return "film"
        case .generatingVoiceover: return "waveform"
        case .rendering: return "paintbrush"
        case .uploading: return "icloud.and.arrow.up"
        case .publishing: return "paperplane"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
}
