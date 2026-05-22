import Foundation
import FirebaseStorage

// MARK: - AutoUploaderError

public enum AutoUploaderError: LocalizedError {
    case uploadFailed(Error)
    case urlGenerationFailed
    case invalidWebhookURL
    case webhookFailed(statusCode: Int)
    case invalidResponse
    
    public var errorDescription: String? {
        switch self {
        case .uploadFailed(let error):
            return "Failed to upload video: \(error.localizedDescription)"
        case .urlGenerationFailed:
            return "Failed to generate download URL."
        case .invalidWebhookURL:
            return "Invalid webhook URL configuration."
        case .webhookFailed(let statusCode):
            return "Webhook trigger failed with status code: \(statusCode)"
        case .invalidResponse:
            return "Invalid response from webhook."
        }
    }
}

// MARK: - AutoUploader

public final class AutoUploader: Sendable {
    
    public static let shared = AutoUploader()
    
    // Replace with your actual Make.com Webhook endpoint
    private let webhookURLString = "https://hook.eu1.make.com/YOUR_WEBHOOK_ENDPOINT"
    
    private init() {}
    
    /// Uploads a local video file to Firebase Storage and triggers an automation webhook.
    /// - Parameters:
    ///   - localVideoURL: The file URL of the local video to upload.
    ///   - caption: The caption text to accompany the video.
    public func uploadAndPublish(localVideoURL: URL, caption: String) async throws {
        let fileName = "\(UUID().uuidString).mp4"
        let storageRef = Storage.storage().reference().child("reels/\(fileName)")
        
        let downloadURL: URL
        do {
            print("🚀 [AutoUploader] Starting video upload to Firebase Storage: \(fileName)")
            
            // Using Firebase Storage async/await wrapper
            let _ = try await storageRef.putFileAsync(from: localVideoURL)
            
            print("✅ [AutoUploader] Upload completed. Fetching download URL...")
            downloadURL = try await storageRef.downloadURL()
            
            print("🔗 [AutoUploader] Download URL retrieved: \(downloadURL.absoluteString)")
        } catch {
            print("❌ [AutoUploader] Upload failed: \(error.localizedDescription)")
            throw AutoUploaderError.uploadFailed(error)
        }
        
        // Trigger Make.com webhook to handle social media publishing
        try await triggerWebhook(videoURL: downloadURL.absoluteString, caption: caption)
    }
    
    /// Triggers the Make.com webhook with the final video URL and metadata.
    private func triggerWebhook(videoURL: String, caption: String) async throws {
        guard let url = URL(string: webhookURLString) else {
            throw AutoUploaderError.invalidWebhookURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Append required tags
        let finalCaption = "\(caption)\n\n#ai #faceless #automation"
        
        let payload = WebhookPayload(
            videoUrl: videoURL,
            caption: finalCaption,
            platforms: WebhookPayload.Platforms(
                instagram: true,
                youtube: true
            )
        )
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)
        
        print("🌐 [AutoUploader] Triggering webhook at \(url.absoluteString)...")
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("❌ [AutoUploader] Network error triggering webhook: \(error.localizedDescription)")
            throw error
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [AutoUploader] Invalid response received from webhook.")
            throw AutoUploaderError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ [AutoUploader] Webhook failed with status: \(httpResponse.statusCode)")
            if let responseBody = String(data: data, encoding: .utf8) {
                print("📄 [AutoUploader] Response body: \(responseBody)")
            }
            throw AutoUploaderError.webhookFailed(statusCode: httpResponse.statusCode)
        }
        
        print("✅ [AutoUploader] Webhook triggered successfully.")
    }
}

// MARK: - Payload Models

extension AutoUploader {
    private struct WebhookPayload: Codable {
        let videoUrl: String
        let caption: String
        let platforms: Platforms
        
        enum CodingKeys: String, CodingKey {
            case videoUrl = "video_url"
            case caption
            case platforms
        }
        
        struct Platforms: Codable {
            let instagram: Bool
            let youtube: Bool
        }
    }
}
