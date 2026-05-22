//
//  VideoFetcher.swift
//  Faceless
//

import Foundation
import os.log

// MARK: - VideoFetcherError
public enum VideoFetcherError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case noVideosFound
    case noSuitableVideoFile
    case downloadFailed
    case missingAPIKey
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The URL provided for the API request is invalid."
        case .invalidResponse:
            return "The API returned an invalid response."
        case .noVideosFound:
            return "No videos were found for the given keyword."
        case .noSuitableVideoFile:
            return "No suitable HD video file in portrait mode was found."
        case .downloadFailed:
            return "Failed to download the video file."
        case .missingAPIKey:
            return "Pexels API Key is missing."
        }
    }
}

// MARK: - VideoFetcher
/// A service for fetching and caching videos from Pexels API
public actor VideoFetcher {
    
    public static let shared = VideoFetcher()
    
    // Replace with your actual Pexels API key or fetch it from a config file
    private let apiKey = "YOUR_PEXELS_API_KEY"
    private let logger = Logger(subsystem: "com.faceless.app", category: "VideoFetcher")
    
    // In-memory cache for downloaded videos by keyword
    // Maps keyword -> local URL
    private var videoCache: [String: URL] = [:]
    
    private init() {}
    
    /// Fetches a random HD portrait video for the given keyword and downloads it to a local temporary URL.
    ///
    /// - Parameter query: The search term (e.g., "nature", "meditation").
    /// - Returns: A local file URL containing the downloaded .mp4 file.
    public func fetchVideo(for query: String) async throws -> URL {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // 1. Check cache first
        if let cachedURL = videoCache[normalizedQuery], FileManager.default.fileExists(atPath: cachedURL.path) {
            logger.info("Cache hit for query: \(normalizedQuery) -> \(cachedURL.path)")
            return cachedURL
        }
        
        logger.info("Fetching videos for query: \(normalizedQuery)")
        
        // 2. Build URL and query items
        guard var urlComponents = URLComponents(string: "https://api.pexels.com/videos/search") else {
            throw VideoFetcherError.invalidURL
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "query", value: normalizedQuery),
            URLQueryItem(name: "orientation", value: "portrait"),
            URLQueryItem(name: "size", value: "medium"),
            URLQueryItem(name: "per_page", value: "3")
        ]
        
        guard let url = urlComponents.url else {
            throw VideoFetcherError.invalidURL
        }
        
        // 3. Configure request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Ensure API key isn't obviously invalid for local testing, 
        // though we'll pass it to let the network fail naturally if it is a placeholder.
        if apiKey.isEmpty {
            logger.error("API Key is missing")
            throw VideoFetcherError.missingAPIKey
        }
        
        request.addValue(apiKey, forHTTPHeaderField: "Authorization")
        
        // 4. Perform API request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            logger.error("Invalid response from Pexels API. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw VideoFetcherError.invalidResponse
        }
        
        // 5. Decode JSON
        let pexelsResponse = try JSONDecoder().decode(PexelsResponse.self, from: data)
        
        // 6. Select a random video from the top 3
        guard let randomVideo = pexelsResponse.videos.randomElement() else {
            logger.error("No videos found for query: \(normalizedQuery)")
            throw VideoFetcherError.noVideosFound
        }
        
        // 7. Find HD quality where height > width
        guard let suitableFile = randomVideo.videoFiles.first(where: { file in
            let w = file.width ?? 0
            let h = file.height ?? 0
            return file.quality.lowercased() == "hd" && h > w
        }) else {
            logger.error("No suitable HD portrait file found for video ID: \(randomVideo.id)")
            throw VideoFetcherError.noSuitableVideoFile
        }
        
        guard let downloadURL = URL(string: suitableFile.link) else {
            throw VideoFetcherError.invalidURL
        }
        
        // 8. Download the video file
        logger.info("Downloading video from: \(downloadURL.absoluteString)")
        let localURL = try await downloadVideo(from: downloadURL)
        
        // 9. Cache and return
        videoCache[normalizedQuery] = localURL
        return localURL
    }
    
    private func downloadVideo(from url: URL) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            logger.error("Failed to download video. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw VideoFetcherError.downloadFailed
        }
        
        // Move from system temp to our app's managed temp
        let destinationURL = TempFileManager.shared.uniqueTempURL(extension: "mp4")
        
        // Ensure the previous file is removed if it somehow exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        logger.info("Video downloaded successfully to \(destinationURL.path)")
        
        return destinationURL
    }
    
    /// Clears the in-memory cache and removes corresponding files from disk.
    public func clearCache() {
        for (_, fileURL) in videoCache {
            try? FileManager.default.removeItem(at: fileURL)
        }
        videoCache.removeAll()
        logger.info("Video cache cleared.")
    }
}
