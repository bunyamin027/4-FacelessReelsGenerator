import SwiftUI

@main
struct FacelessApp: App {
    @StateObject private var subManager = SubscriptionManager()
    @StateObject private var featureFlagManager = FeatureFlagManager.shared
    
    var body: some SwiftUI.Scene {
        WindowGroup {
            HomeView()
                .environmentObject(subManager)
                .environmentObject(featureFlagManager)
        }
    }
}
