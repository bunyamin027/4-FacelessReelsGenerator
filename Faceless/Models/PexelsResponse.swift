//
//  PexelsResponse.swift
//  Faceless
//

import Foundation

// MARK: - PexelsResponse
public struct PexelsResponse: Codable, Sendable {
    public let page: Int?
    public let perPage: Int?
    public let totalResults: Int?
    public let url: String?
    public let videos: [PexelsVideo]
    
    public enum CodingKeys: String, CodingKey {
        case page
        case perPage = "per_page"
        case totalResults = "total_results"
        case url
        case videos
    }
}

// MARK: - PexelsVideo
public struct PexelsVideo: Codable, Identifiable, Sendable {
    public let id: Int
    public let width: Int?
    public let height: Int?
    public let url: String?
    public let image: String?
    public let duration: Int?
    public let videoFiles: [PexelsVideoFile]
    
    public enum CodingKeys: String, CodingKey {
        case id
        case width
        case height
        case url
        case image
        case duration
        case videoFiles = "video_files"
    }
}

// MARK: - PexelsVideoFile
public struct PexelsVideoFile: Codable, Identifiable, Sendable {
    public let id: Int
    public let quality: String
    public let fileType: String?
    public let width: Int?
    public let height: Int?
    public let link: String
    
    public enum CodingKeys: String, CodingKey {
        case id
        case quality
        case fileType = "file_type"
        case width
        case height
        case link
    }
}
