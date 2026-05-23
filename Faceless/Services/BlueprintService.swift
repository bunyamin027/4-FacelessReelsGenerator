//
//  BlueprintService.swift
//  Faceless
//

import Foundation
import os

// MARK: - Blueprint Error
enum BlueprintError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, data: Data?)
    case encodingError(Error)
    case decodingError(Error)
    case networkError(Error)
    case maxRetriesReached(Error?)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The endpoint URL is invalid."
        case .invalidResponse:
            return "The server response was invalid."
        case .httpError(let statusCode, _):
            return "HTTP Error with status code: \(statusCode)"
        case .encodingError(let error):
            return "Failed to encode request body: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error occurred: \(error.localizedDescription)"
        case .maxRetriesReached(let lastError):
            if let lastError = lastError {
                return "Failed to generate blueprint after maximum retries. Last error: \(lastError.localizedDescription)"
            }
            return "Failed to generate blueprint after maximum retries."
        }
    }
}

// MARK: - Blueprint Request
fileprivate struct BlueprintRequest: Codable {
    let prompt: String
}

// MARK: - Blueprint Service Protocol
protocol BlueprintServiceProtocol: Sendable {
    func generateBlueprint(for prompt: String) async throws -> ReelsBlueprint
}

// MARK: - Blueprint Service
actor BlueprintService: BlueprintServiceProtocol {
    private let endpointURL: URL
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.faceless.app", category: "BlueprintService")
    
    // Configuration for retries
    private let maxRetries: Int = 3
    private let baseDelay: TimeInterval = 1.0 // seconds
    
    init(
        endpointString: String = "https://faceless-proxy.YOUR_USERNAME.workers.dev",
        urlSession: URLSession = .shared
    ) {
        guard let url = URL(string: endpointString) else {
            fatalError("Invalid endpoint URL string provided to BlueprintService.")
        }
        self.endpointURL = url
        self.urlSession = urlSession
    }
    
    func generateBlueprint(for prompt: String) async throws -> ReelsBlueprint {
        logger.info("Starting blueprint generation for prompt: \(prompt, privacy: .private)")
        
        var currentAttempt = 0
        var lastError: Error?
        
        while currentAttempt <= maxRetries {
            do {
                return try await performRequest(prompt: prompt)
            } catch {
                lastError = error
                currentAttempt += 1
                logger.warning("Attempt \(currentAttempt) failed: \(error.localizedDescription)")
                
                if currentAttempt > maxRetries {
                    logger.error("Max retries reached. Failing request.")
                    break
                }
                
                // Exponential backoff
                let delay = baseDelay * pow(2.0, Double(currentAttempt - 1))
                logger.info("Retrying in \(delay) seconds...")
                
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        if endpointURL.absoluteString.contains("YOUR_USERNAME") {
            logger.info("Using MOCK Blueprint because Cloudflare URL is not configured.")
            try await Task.sleep(nanoseconds: 2_000_000_000) // Simulate network delay
            return ReelsBlueprint(
                title: "Mock Title",
                description: "Mock Description",
                scenes: [
                    ReelScene(id: "1", duration: 3.0, visualPrompt: "nature landscape", voiceoverScript: "Welcome to Faceless.", visualType: .stockVideo, textOverlay: "Welcome"),
                    ReelScene(id: "2", duration: 3.0, visualPrompt: "city night", voiceoverScript: "This is a mock generation.", visualType: .stockVideo, textOverlay: "Mock Video")
                ],
                backgroundAudio: .ambient
            )
        }
        
        throw BlueprintError.maxRetriesReached(lastError)
    }
    
    private func performRequest(prompt: String) async throws -> ReelsBlueprint {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = BlueprintRequest(prompt: prompt)
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw BlueprintError.encodingError(error)
        }
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw BlueprintError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlueprintError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw BlueprintError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
        
        do {
            let blueprint = try JSONDecoder().decode(ReelsBlueprint.self, from: data)
            logger.info("Successfully generated blueprint.")
            return blueprint
        } catch {
            throw BlueprintError.decodingError(error)
        }
    }
}
