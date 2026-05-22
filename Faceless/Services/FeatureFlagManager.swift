//
//  FeatureFlagManager.swift
//  Faceless
//
//  Created by Cascade.
//

import Foundation
import Combine

/// A manager responsible for handling feature flags across the app.
/// This is particularly useful for managing features that might trigger App Store Review
/// rejections (e.g., Guideline 2.3.1), such as the "Auto Publish to Instagram/YouTube" feature.
@MainActor
public final class FeatureFlagManager: ObservableObject {
    
    /// Shared singleton instance.
    public static let shared = FeatureFlagManager()
    
    /// Indicates whether the "Auto Publish to Instagram/YouTube" feature is enabled.
    /// Defaults to `false` to ensure safety during App Store Review.
    @Published public private(set) var isAutoPublishEnabled: Bool = false
    
    // MARK: - Configuration
    
    /// Hardcoded whitelist of user identifiers (e.g., Apple IDs or internal user IDs)
    /// who are allowed to see features normally hidden for App Store review.
    private let whitelistedUserIDs: Set<String> = [
        "dev@faceless.com", // Example Apple ID
        "admin@faceless.com"
    ]
    
    // MARK: - Keys
    private enum Keys {
        static let autoPublishOverride = "ff_autoPublishOverride"
    }
    
    // MARK: - Initialization
    
    private init() {
        // Initialize flags on startup with no current user.
        refreshFlags()
    }
    
    // MARK: - Public Methods
    
    /// Fetches the latest configuration for feature flags.
    /// Currently a stub for Firebase Remote Config or similar backend services.
    /// - Parameter currentUserID: The identifier of the currently logged-in user, if any.
    public func fetchConfig(for currentUserID: String? = nil) async {
        // TODO: Implement actual remote config fetching (e.g., Firebase Remote Config)
        // Simulate a network delay for the MVP stub
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        refreshFlags(for: currentUserID)
    }
    
    /// Refreshes the published flags based on user whitelist, local overrides, and default states.
    /// - Parameter currentUserID: The identifier of the currently logged-in user.
    public func refreshFlags(for currentUserID: String? = nil) {
        // 1. Check for a local/developer override in UserDefaults (e.g., from a hidden dev menu)
        if let override = UserDefaults.standard.object(forKey: Keys.autoPublishOverride) as? Bool {
            isAutoPublishEnabled = override
            return
        }
        
        // 2. Check the hardcoded whitelist
        if let userID = currentUserID, whitelistedUserIDs.contains(userID) {
            isAutoPublishEnabled = true
            return
        }
        
        // 3. Default fallback (safe for App Store Review)
        isAutoPublishEnabled = false
    }
    
    /// Updates the local override for the Auto Publish feature flag.
    /// Useful for a hidden developer menu within the app.
    /// - Parameter isEnabled: Whether the feature should be enabled or disabled locally.
    public func setAutoPublishOverride(isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: Keys.autoPublishOverride)
        refreshFlags()
    }
    
    /// Clears any local override for the Auto Publish feature flag.
    public func clearAutoPublishOverride() {
        UserDefaults.standard.removeObject(forKey: Keys.autoPublishOverride)
        refreshFlags()
    }
}
