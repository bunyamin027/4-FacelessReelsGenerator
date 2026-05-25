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
    private let apiKey = "dw6ltlKiBzQDT7bnqatBJVYhChA9YjCtSbqJZLSyhpxx52v0t0j3AsXD"
    // TODO: Add Pixabay API Key
    private let pixabayApiKey = "YOUR_PIXABAY_API_KEY"
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
        
        // Cache her zaman atlanıyor — her oluşturmada farklı video gelsin
        logger.info("Fetching fresh video for query: \(normalizedQuery)")
        
        // 2. Build URL and query items
        guard var urlComponents = URLComponents(string: "https://api.pexels.com/videos/search") else {
            throw VideoFetcherError.invalidURL
        }
        
        let randomPage = Int.random(in: 1...5)
        urlComponents.queryItems = [
            URLQueryItem(name: "query", value: normalizedQuery),
            URLQueryItem(name: "orientation", value: "portrait"),
            URLQueryItem(name: "size", value: "medium"),
            URLQueryItem(name: "per_page", value: "15"),
            URLQueryItem(name: "page", value: "\(randomPage)")
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
        
        // 6. Select a random video — prefer longer ones (> 6s) for smoother looping
        guard !pexelsResponse.videos.isEmpty else {
            logger.error("No videos found on Pexels for query: \(normalizedQuery)")
            return try await fetchFromPixabay(query: normalizedQuery)
        }
        
        let validVideos = pexelsResponse.videos.filter { ($0.duration ?? 0) > 6 }
        let selectedVideo: PexelsVideo
        if let longVideo = validVideos.randomElement() {
            selectedVideo = longVideo
            logger.info("Selected video from Pexels (duration: \(longVideo.duration ?? 0)s)")
        } else {
            logger.warning("No Pexels videos longer than 6s found, falling back to Pixabay")
            do {
                return try await fetchFromPixabay(query: normalizedQuery)
            } catch {
                logger.error("Pixabay fallback failed, trying random short Pexels video...")
                if let anyVideo = pexelsResponse.videos.randomElement() {
                    selectedVideo = anyVideo
                    logger.info("Selected short Pexels video (duration: \(anyVideo.duration ?? 0)s)")
                } else {
                    throw VideoFetcherError.noVideosFound
                }
            }
        }
        
        // 7. Find HD quality where height > width
        guard let suitableFile = selectedVideo.videoFiles.first(where: { file in
            let w = file.width ?? 0
            let h = file.height ?? 0
            let q = file.quality?.lowercased() ?? ""
            return (q == "hd" || q == "uhd") && h > w && file.link != nil
        }) ?? selectedVideo.videoFiles.first(where: { $0.link != nil }) else {
            logger.error("No suitable video file found for video ID: \(selectedVideo.id)")
            return try await fetchFromPixabay(query: normalizedQuery)
        }

        guard let linkString = suitableFile.link,
              let downloadURL = URL(string: linkString) else {
            throw VideoFetcherError.invalidURL
        }
        
        // 8. Download the video file
        logger.info("Downloading video from: \(downloadURL.absoluteString)")
        let localURL = try await downloadVideo(from: downloadURL)
        
        // 9. Cache and return
        videoCache[normalizedQuery] = localURL
        return localURL
    }

    private func fetchFromPixabay(query: String) async throws -> URL {
        logger.info("Falling back to Pixabay for query: \(query)")
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        guard let url = URL(string: "https://pixabay.com/api/videos/?key=\(pixabayApiKey)&q=\(encodedQuery)&video_type=film") else {
            throw VideoFetcherError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw VideoFetcherError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = json["hits"] as? [[String: Any]], !hits.isEmpty else {
            throw VideoFetcherError.noVideosFound
        }
        
        // Filter by duration > 6s
        let validHits = hits.filter { hit in
            if let duration = hit["duration"] as? Int {
                return duration > 6
            }
            return false
        }
        
        guard let selectedHit = validHits.randomElement() ?? hits.randomElement(),
              let videos = selectedHit["videos"] as? [String: Any] else {
            throw VideoFetcherError.noVideosFound
        }
        
        // Try to get large or medium quality video URL
        guard let videoFormat = (videos["large"] as? [String: Any]) ?? (videos["medium"] as? [String: Any]) ?? (videos["small"] as? [String: Any]),
              let videoURLString = videoFormat["url"] as? String,
              let downloadURL = URL(string: videoURLString) else {
            throw VideoFetcherError.noSuitableVideoFile
        }
        
        logger.info("Downloading video from Pixabay: \(downloadURL.absoluteString)")
        let localURL = try await downloadVideo(from: downloadURL)
        
        // Cache it manually
        videoCache[query] = localURL
        return localURL
    }

    /// Fetches multiple videos concurrently for an array of keywords.
    ///
    /// - Parameter keywords: An array of search keywords.
    /// - Returns: An array of local file URLs containing the downloaded .mp4 files.
    public func fetchVideos(for keywords: [String]) async throws -> [URL] {
        logger.info("Fetching videos for \(keywords.count) scenes concurrently...")
        
        // Use withThrowingTaskGroup to fetch all videos in parallel
        return try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            for (index, keyword) in keywords.enumerated() {
                group.addTask {
                    let url = try await self.fetchVideo(for: keyword)
                    return (index, url)
                }
            }
            
            var results: [(Int, URL)] = []
            for try await result in group {
                results.append(result)
            }
            
            // Re-order URLs to match the original keywords order
            return results.sorted { $0.0 < $1.0 }.map { $1 }
        }
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
