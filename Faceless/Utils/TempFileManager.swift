// TempFileManager.swift
// Faceless
//
// Utility for managing temporary video and audio files.

import Foundation
import os.log

// MARK: - TempFileManager

/// Manages temporary files created during the video generation pipeline.
/// Provides cleanup, unique URL generation, and disk usage tracking.
final class TempFileManager: Sendable {
    
    // MARK: - Singleton
    
    static let shared = TempFileManager()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.faceless.app", category: "TempFileManager")
    
    /// File extensions created by the app's pipeline
    private let managedExtensions: Set<String> = ["mp4", "caf", "m4a", "mov", "wav", "jpg", "jpeg", "png"]
    
    // MARK: - Init
    
    private init() {}
    
    // MARK: - Cleanup
    
    /// Cleans up all temporary video and audio files created by the app.
    func cleanupTempFiles() {
        let tempDir = NSTemporaryDirectory()
        let fileManager = FileManager.default
        
        do {
            let tempFiles = try fileManager.contentsOfDirectory(atPath: tempDir)
            var removedCount = 0
            var freedBytes: Int64 = 0
            
            for file in tempFiles {
                let fileExtension = (file as NSString).pathExtension.lowercased()
                guard managedExtensions.contains(fileExtension) else { continue }
                
                let fullPath = (tempDir as NSString).appendingPathComponent(file)
                
                // Track size before removal
                if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                   let fileSize = attrs[.size] as? Int64 {
                    freedBytes += fileSize
                }
                
                try fileManager.removeItem(atPath: fullPath)
                removedCount += 1
            }
            
            logger.info("Cleaned up \(removedCount) temp files, freed \(freedBytes) bytes")
        } catch {
            logger.error("Failed to cleanup temp files: \(error.localizedDescription)")
        }
    }
    
    // MARK: - URL Generation
    
    /// Creates a unique temporary file URL with the given extension.
    /// - Parameter ext: The file extension (without leading dot), e.g. "mp4", "caf"
    /// - Returns: A unique URL in the system's temporary directory
    func uniqueTempURL(extension ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
    }
    
    // MARK: - Disk Usage
    
    /// Returns the total size of app-managed temp files in bytes.
    func tempDirectorySize() -> Int64 {
        let tempDir = NSTemporaryDirectory()
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        do {
            let tempFiles = try fileManager.contentsOfDirectory(atPath: tempDir)
            
            for file in tempFiles {
                let fileExtension = (file as NSString).pathExtension.lowercased()
                guard managedExtensions.contains(fileExtension) else { continue }
                
                let fullPath = (tempDir as NSString).appendingPathComponent(file)
                if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                   let fileSize = attrs[.size] as? Int64 {
                    totalSize += fileSize
                }
            }
        } catch {
            logger.error("Failed to calculate temp directory size: \(error.localizedDescription)")
        }
        
        return totalSize
    }
    
    /// Returns a human-readable string for the temp directory size.
    func formattedTempDirectorySize() -> String {
        let bytes = tempDirectorySize()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
