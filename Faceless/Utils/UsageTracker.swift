//
//  UsageTracker.swift
//  Faceless
//

import Foundation

@MainActor
public class UsageTracker {
    public static let shared = UsageTracker()
    
    private let userDefaults = UserDefaults.standard
    private let usageKey = "com.faceless.generationsToday"
    private let dateKey = "com.faceless.lastGenerationDate"
    private let freeLimit = 3
    
    private init() {
        checkAndResetIfNeeded()
    }
    
    public func incrementUsage() {
        checkAndResetIfNeeded()
        let current = getGenerationsToday()
        userDefaults.set(current + 1, forKey: usageKey)
        userDefaults.set(Date(), forKey: dateKey)
    }
    
    public func getGenerationsToday() -> Int {
        checkAndResetIfNeeded()
        return userDefaults.integer(forKey: usageKey)
    }
    
    public func hasReachedFreeLimit() -> Bool {
        return getGenerationsToday() >= freeLimit
    }
    
    private func checkAndResetIfNeeded() {
        guard let lastDate = userDefaults.object(forKey: dateKey) as? Date else {
            // No previous usage date recorded
            return
        }
        
        if !Calendar.current.isDateInToday(lastDate) {
            // It's a new day, reset usage
            userDefaults.set(0, forKey: usageKey)
            // Update the date key to today when resetting
            userDefaults.set(Date(), forKey: dateKey)
        }
    }
}
