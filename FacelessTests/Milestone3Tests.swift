import XCTest
@testable import Faceless

@MainActor
final class Milestone3Tests: XCTestCase {
    
    // MARK: - UserDefaults Keys
    private let usageKey = "com.faceless.generationsToday"
    private let dateKey = "com.faceless.lastGenerationDate"
    private let autoPublishOverrideKey = "ff_autoPublishOverride"
    
    override func setUp() {
        super.setUp()
        // Reset UsageTracker state
        UserDefaults.standard.removeObject(forKey: usageKey)
        UserDefaults.standard.removeObject(forKey: dateKey)
        
        // Reset FeatureFlagManager state
        UserDefaults.standard.removeObject(forKey: autoPublishOverrideKey)
        FeatureFlagManager.shared.refreshFlags()
    }
    
    override func tearDown() {
        // Clean up after tests
        UserDefaults.standard.removeObject(forKey: usageKey)
        UserDefaults.standard.removeObject(forKey: dateKey)
        UserDefaults.standard.removeObject(forKey: autoPublishOverrideKey)
        FeatureFlagManager.shared.refreshFlags()
        super.tearDown()
    }
    
    // MARK: - UsageTracker Tests
    
    func testUsageTracker_Incrementing() {
        let tracker = UsageTracker.shared
        
        // Initial state
        XCTAssertEqual(tracker.getGenerationsToday(), 0, "Initial generations should be 0")
        
        // Increment once
        tracker.incrementUsage()
        XCTAssertEqual(tracker.getGenerationsToday(), 1, "Generations should be 1 after one increment")
        
        // Increment again
        tracker.incrementUsage()
        XCTAssertEqual(tracker.getGenerationsToday(), 2, "Generations should be 2 after two increments")
    }
    
    func testUsageTracker_FreeLimit() {
        let tracker = UsageTracker.shared
        
        // Increment up to free limit (3)
        tracker.incrementUsage() // 1
        XCTAssertFalse(tracker.hasReachedFreeLimit(), "Should not reach limit after 1 generation")
        
        tracker.incrementUsage() // 2
        XCTAssertFalse(tracker.hasReachedFreeLimit(), "Should not reach limit after 2 generations")
        
        tracker.incrementUsage() // 3
        XCTAssertTrue(tracker.hasReachedFreeLimit(), "Should reach limit after 3 generations")
        
        tracker.incrementUsage() // 4
        XCTAssertTrue(tracker.hasReachedFreeLimit(), "Should still be at limit after 4 generations")
    }
    
    func testUsageTracker_DateResetLogic() {
        let tracker = UsageTracker.shared
        
        // Set usage as if it was done yesterday
        UserDefaults.standard.set(3, forKey: usageKey)
        
        // Mock yesterday's date
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        UserDefaults.standard.set(yesterday, forKey: dateKey)
        
        // Trigger a check by getting generations today
        let currentGenerations = tracker.getGenerationsToday()
        
        // Should reset to 0 because the date was yesterday
        XCTAssertEqual(currentGenerations, 0, "Usage should reset to 0 on a new day")
        XCTAssertFalse(tracker.hasReachedFreeLimit(), "Should not have reached free limit on a new day")
        
        // Date key should have been updated to today
        if let lastDate = UserDefaults.standard.object(forKey: dateKey) as? Date {
            XCTAssertTrue(Calendar.current.isDateInToday(lastDate), "Date should be updated to today after reset")
        } else {
            XCTFail("Date key missing after reset")
        }
    }
    
    // MARK: - FeatureFlagManager Tests
    
    func testFeatureFlagManager_DefaultValues() {
        let manager = FeatureFlagManager.shared
        
        // Should default to false for a normal user
        manager.refreshFlags(for: "normal_user@example.com")
        XCTAssertFalse(manager.isAutoPublishEnabled, "Auto Publish should be disabled by default for normal users")
        
        // Should default to false for no user
        manager.refreshFlags(for: nil)
        XCTAssertFalse(manager.isAutoPublishEnabled, "Auto Publish should be disabled by default when no user is logged in")
    }
    
    func testFeatureFlagManager_Whitelist() {
        let manager = FeatureFlagManager.shared
        
        // Whitelisted users should have it enabled
        manager.refreshFlags(for: "dev@faceless.com")
        XCTAssertTrue(manager.isAutoPublishEnabled, "Auto Publish should be enabled for whitelisted developer user")
        
        manager.refreshFlags(for: "admin@faceless.com")
        XCTAssertTrue(manager.isAutoPublishEnabled, "Auto Publish should be enabled for whitelisted admin user")
    }
    
    func testFeatureFlagManager_Overrides() {
        let manager = FeatureFlagManager.shared
        
        // Initially false
        manager.refreshFlags(for: nil)
        XCTAssertFalse(manager.isAutoPublishEnabled)
        
        // Set override to true
        manager.setAutoPublishOverride(isEnabled: true)
        XCTAssertTrue(manager.isAutoPublishEnabled, "Auto Publish should be enabled after override is set to true")
        
        // Verify override is respected even for normal users
        manager.refreshFlags(for: "normal_user@example.com")
        XCTAssertTrue(manager.isAutoPublishEnabled, "Override should bypass normal user defaults")
        
        // Set override to false
        manager.setAutoPublishOverride(isEnabled: false)
        XCTAssertFalse(manager.isAutoPublishEnabled, "Auto Publish should be disabled after override is set to false")
        
        // Clear override
        manager.clearAutoPublishOverride()
        
        // Should revert to normal rules (whitelist check)
        manager.refreshFlags(for: "dev@faceless.com")
        XCTAssertTrue(manager.isAutoPublishEnabled, "Should revert to whitelist rule after override is cleared")
        
        manager.refreshFlags(for: nil)
        XCTAssertFalse(manager.isAutoPublishEnabled, "Should revert to default rule after override is cleared")
    }
}
