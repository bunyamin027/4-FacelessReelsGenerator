// VideoPreviewView.swift
// Faceless
//
// Full-screen video preview with share, reset, and pro publish actions.

import SwiftUI
import AVKit

// MARK: - VideoPreviewView

/// Displays the generated video/audio in a full-screen player with
/// action buttons for sharing, creating a new video, or upgrading to Pro.
struct VideoPreviewView: View {
    
    // MARK: - Properties
    
    let videoURL: URL?
    let onNewVideo: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var showShareSheet: Bool = false
    @State private var showProAlert: Bool = false
    @State private var buttonsVisible: Bool = false
    @State private var playerLoopObserver: Any?
    
    // MARK: - Colors
    
    private let accentGradient = LinearGradient(
        colors: [
            Color(hex: "8B5CF6"),
            Color(hex: "EC4899")
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    private let backgroundGradient = LinearGradient(
        colors: [
            Color(hex: "0A0A0F"),
            Color(hex: "110A1F"),
            Color(hex: "0A0A0F")
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background
            backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Video player area
                videoPlayerSection
                    .frame(maxHeight: .infinity)
                
                // Action buttons
                actionButtonsSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                    .opacity(buttonsVisible ? 1 : 0)
                    .offset(y: buttonsVisible ? 0 : 30)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    cleanupPlayer()
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Geri")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(Color.white.opacity(0.7))
                }
                .accessibilityIdentifier("backButton")
            }
            
            ToolbarItem(placement: .principal) {
                Text("Önizleme")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            setupPlayer()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3)) {
                buttonsVisible = true
            }
        }
        .onDisappear {
            cleanupPlayer()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = videoURL {
                ShareSheet(activityItems: [url])
                    .presentationDetents([.medium, .large])
            }
        }
        .alert("Pro Özellik", isPresented: $showProAlert) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Otomatik yayınlama özelliği Pro aboneliğinde kullanılabilir. Yakında!")
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Video Player Section
    
    private var videoPlayerSection: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(9/16, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: Color(hex: "8B5CF6").opacity(0.2), radius: 30, x: 0, y: 10)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            } else {
                // Placeholder when no video is available
                VStack(spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            )
                        
                        VStack(spacing: 16) {
                            Image(systemName: "waveform")
                                .font(.system(size: 48))
                                .foregroundStyle(accentGradient)
                                .symbolEffect(.variableColor.iterative, isActive: true)
                            
                            Text("Ses dosyası oluşturuldu")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text("Video oluşturma özelliği\nyakında eklenecek")
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundColor(Color.white.opacity(0.4))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }
                    }
                    .aspectRatio(9/16, contentMode: .fit)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
        }
        .accessibilityIdentifier("videoPlayerSection")
    }
    
    // MARK: - Action Buttons
    
    private var actionButtonsSection: some View {
        VStack(spacing: 14) {
            // Share button — primary CTA
            Button {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                showShareSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                    
                    Text("Paylaş")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(accentGradient)
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.12), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color(hex: "8B5CF6").opacity(0.35), radius: 16, x: 0, y: 6)
            }
            .disabled(videoURL == nil)
            .opacity(videoURL == nil ? 0.5 : 1.0)
            .accessibilityIdentifier("shareButton")
            
            HStack(spacing: 12) {
                // New Video button
                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    cleanupPlayer()
                    onNewVideo()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 15, weight: .semibold))
                        
                        Text("Yeni Video")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
                .accessibilityIdentifier("newVideoButton")
                
                // Publish with Pro button
                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    showProAlert = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "F59E0B"), Color(hex: "EF4444")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("Pro ile Yayınla")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color(hex: "F59E0B").opacity(0.3),
                                                Color(hex: "EF4444").opacity(0.3)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                }
                .accessibilityIdentifier("proPublishButton")
            }
        }
    }
    
    // MARK: - Player Management
    
    private func setupPlayer() {
        guard let url = videoURL else { return }
        
        let avPlayer = AVPlayer(url: url)
        player = avPlayer
        
        // Loop playback
        playerLoopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { [weak avPlayer] _ in
            avPlayer?.seek(to: .zero)
            avPlayer?.play()
        }
        
        avPlayer.play()
    }
    
    private func cleanupPlayer() {
        player?.pause()
        player = nil
        
        if let observer = playerLoopObserver {
            NotificationCenter.default.removeObserver(observer)
            playerLoopObserver = nil
        }
    }
}

// MARK: - ShareSheet (UIActivityViewController Wrapper)

/// A UIKit representable that wraps `UIActivityViewController` for SwiftUI.
struct ShareSheet: UIViewControllerRepresentable {
    
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        VideoPreviewView(
            videoURL: nil,
            onNewVideo: {}
        )
    }
}
