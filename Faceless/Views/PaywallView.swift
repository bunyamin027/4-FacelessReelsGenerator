import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var subManager: SubscriptionManager
    
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Dark theme background
            Color.black.ignoresSafeArea()
            
            // Background glow effect
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.4), Color.blue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 350, height: 350)
                .blur(radius: 80)
                .offset(y: -250)
            
            VStack(spacing: 0) {
                // Top bar with close button
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.gray.opacity(0.8))
                    }
                    .padding()
                }
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        
                        // Stunning visual element at the top
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 110, height: 110)
                                .shadow(color: .purple.opacity(0.6), radius: isAnimating ? 30 : 15, x: 0, y: 0)
                            
                            Image(systemName: "crown.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(.white)
                                .shadow(color: .white.opacity(0.5), radius: 5, x: 0, y: 0)
                        }
                        .scaleEffect(isAnimating ? 1.05 : 0.95)
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
                        .padding(.top, 10)
                        
                        // Titles
                        VStack(spacing: 12) {
                            Text("Faceless Pro'ya Yükseltin")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            
                            Text("Sınırları kaldırın ve tam otonom viral bir makineye dönüşün.")
                                .font(.body)
                                .foregroundStyle(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        
                        // Feature comparison list
                        VStack(alignment: .leading, spacing: 20) {
                            FeatureRow(emoji: "🚀", text: "Sınırsız Video Üretimi (Ücretsiz: Günde 3)")
                            FeatureRow(emoji: "✨", text: "Filigranı (Watermark) Kaldırın")
                            FeatureRow(emoji: "📱", text: "1080p HD Yüksek Kalite Render")
                            FeatureRow(emoji: "🤖", text: "Otomatik Sosyal Medya Paylaşımı (Instagram & YouTube)")
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(
                                            LinearGradient(
                                                colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .padding(.horizontal, 24)
                        
                        Spacer(minLength: 20)
                        
                        // Price display
                        VStack(spacing: 8) {
                            // Assuming SubscriptionManager has a monthlyPriceString property,
                            // otherwise we provide the requested default
                            Text("Sadece 9.99$/Ay")
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                            
                            Text("İstediğiniz zaman iptal edebilirsiniz.")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                        
                        // Massive, glowing CTA button
                        Button {
                            // Assuming SubscriptionManager has a purchase function
                            // Task { await subManager.purchase() }
                        } label: {
                            Text("Pro'ya Geç")
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(
                                    LinearGradient(
                                        colors: [.purple, .blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .purple.opacity(0.6), radius: isAnimating ? 20 : 10, x: 0, y: 5)
                        }
                        .padding(.horizontal, 24)
                        
                        // Links at the bottom
                        VStack(spacing: 20) {
                            Button("Satın Almaları Geri Yükle") {
                                // Task { await subManager.restorePurchases() }
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.white.opacity(0.9))
                            
                            HStack(spacing: 24) {
                                Link("Kullanım Şartları", destination: URL(string: "https://example.com/terms")!)
                                Link("Gizlilik Politikası", destination: URL(string: "https://example.com/privacy")!)
                            }
                            .font(.caption)
                            .foregroundStyle(.gray)
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct FeatureRow: View {
    let emoji: String
    let text: String
    
    var body: some View {
        HStack(spacing: 16) {
            Text(emoji)
                .font(.title2)
            
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
}
