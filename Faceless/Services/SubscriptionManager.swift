//
//  SubscriptionManager.swift
//  Faceless
//

import Foundation
import StoreKit

@MainActor
public class SubscriptionManager: ObservableObject {
    @Published public var isPro: Bool = false
    @Published public var products: [Product] = []
    
    private let productIDs = ["faceless_pro_monthly"]
    private var updateListenerTask: Task<Void, Never>? = nil
    
    public init() {
        updateListenerTask = listenForTransactions()
        
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    private func listenForTransactions() -> Task<Void, Never> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)
                    await self.updateSubscriptionStatus()
                    await transaction.finish()
                } catch {
                    print("Transaction failed verification: \(error)")
                }
            }
        }
    }
    
    public func loadProducts() async {
        do {
            products = try await Product.products(for: productIDs)
        } catch {
            print("Failed to load products: \(error)")
        }
    }
    
    public func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateSubscriptionStatus()
            await transaction.finish()
        case .userCancelled:
            print("User cancelled purchase.")
        case .pending:
            print("Purchase pending.")
        @unknown default:
            print("Unknown purchase result.")
        }
    }
    
    public func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
        } catch {
            print("Failed to restore purchases: \(error)")
        }
    }
    
    public func updateSubscriptionStatus() async {
        var hasActiveSubscription = false
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                // Check if the entitlement is for our product type
                if transaction.productType == .autoRenewable || transaction.productType == .nonRenewable {
                    hasActiveSubscription = true
                }
            } catch {
                print("Failed to verify entitlement: \(error)")
            }
        }
        
        isPro = hasActiveSubscription
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
