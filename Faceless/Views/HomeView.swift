// HomeView.swift
// Faceless
//
// Premium dark-themed home screen for the Faceless reel generator.

import SwiftUI
import AVKit
import PhotosUI

// MARK: - HomeView

/// The main landing screen of the app featuring a premium dark UI with
/// glassmorphism input, gradient CTA button, and generation pipeline integration.
struct HomeView: View {
    
    // MARK: - Properties
    
    @StateObject private var viewModel = ReelGeneratorViewModel()
    @StateObject private var videoHistory = VideoHistoryManager.shared
    @State private var isTextFieldFocused: Bool = false
    @State private var buttonPressed: Bool = false
    @State private var showError: Bool = false
    @EnvironmentObject private var subManager: SubscriptionManager
    @State private var showPaywall: Bool = false
    @State private var glowAnimation: Bool = false
    @State private var selectedHistoryItem: VideoHistoryItem?
    @Namespace private var animationNamespace
    
    @State private var selectedPickerItem: PhotosPickerItem? = nil
    @State private var isLoadingVideo = false
    
    // MARK: - Colors
    
    private let backgroundGradient = LinearGradient(
        colors: [
            Color(hex: "0A0A0F"),
            Color(hex: "110A1F"),
            Color(hex: "1A0A2E")
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    private let accentGradient = LinearGradient(
        colors: [
            Color(hex: "8B5CF6"),
            Color(hex: "EC4899")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    private let glassBackground = Color.white.opacity(0.06)
    private let glassBorder = Color.white.opacity(0.12)
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                backgroundGradient
                    .ignoresSafeArea()
                
                // Ambient glow effect
                ambientGlow
                
                // Main content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        headerSection
                            .padding(.top, 60)
                        
                        inputSection
                            .padding(.top, 48)
                        
                        mediaPickerSection
                            .padding(.top, 24)
                        
                        generateButton
                            .padding(.top, 32)
                        
                        recentSection
                            .padding(.top, 56)
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 24)
                }
                
                // Generation progress overlay
                if viewModel.isGenerating {
                    GenerationProgressView(
                        currentPhase: viewModel.currentPhase,
                        progress: viewModel.progressValue,
                        onCancel: {
                            viewModel.cancelGeneration()
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $viewModel.isShowingPreview) {
                VideoPreviewView(
                    videoURL: viewModel.generatedVideoURL,
                    onNewVideo: {
                        viewModel.reset()
                    }
                )
            }
            .alert("Hata", isPresented: $showError) {
                Button("Tamam", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "Bilinmeyen bir hata oluştu.")
            }
            .onChange(of: viewModel.errorMessage) { _, newValue in
                showError = newValue != nil
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                    glowAnimation = true
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(subManager)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // App icon / logo area
            ZStack {
                // Glow behind icon
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "8B5CF6").opacity(0.3),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .blur(radius: 20)
                    .scaleEffect(glowAnimation ? 1.15 : 0.95)
                
                Image(systemName: "video.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(accentGradient)
                    .shadow(color: Color(hex: "8B5CF6").opacity(0.5), radius: 16, x: 0, y: 4)
            }
            
            // App title
            Text("Faceless")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color.white.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color(hex: "8B5CF6").opacity(0.3), radius: 12, x: 0, y: 2)
            
            // Tagline
            Text("AI ile Viral Video Üret")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundColor(Color.white.opacity(0.5))
                .tracking(1.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("homeHeader")
    }
    
    // MARK: - Input Section
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section label
            HStack(spacing: 6) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "8B5CF6"))
                
                Text("KONU")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.4))
                    .tracking(2)
            }
            
            // Glassmorphism text field
            ZStack(alignment: .leading) {
                // Glass background
                RoundedRectangle(cornerRadius: 16)
                    .fill(glassBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isTextFieldFocused
                                    ? Color(hex: "8B5CF6").opacity(0.5)
                                    : glassBorder,
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: isTextFieldFocused
                            ? Color(hex: "8B5CF6").opacity(0.15)
                            : Color.clear,
                        radius: 16,
                        x: 0,
                        y: 4
                    )
                
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(
                            isTextFieldFocused ? accentGradient : LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.white.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    TextField("", text: $viewModel.topicInput, prompt: Text("Bir konu girin... (ör: Başarının 5 sırrı)")
                        .foregroundColor(Color.white.opacity(0.25))
                    )
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.sentences)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTextFieldFocused = true
                        }
                    }
                    .onChange(of: viewModel.topicInput) { _, newValue in
                        if newValue.isEmpty {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isTextFieldFocused = false
                            }
                        }
                    }
                    
                    // Clear button
                    if !viewModel.topicInput.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.topicInput = ""
                                isTextFieldFocused = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color.white.opacity(0.3))
                        }
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityIdentifier("clearTopicButton")
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 56)
            .accessibilityIdentifier("topicTextField")
        }
    }
    
    // MARK: - Generate Button
    
    private var generateButton: some View {
        Button {
            guard !viewModel.isGenerating else { return }
            
            // ✅ Madde 5: Klavyeyi kapat
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
            
            // Limit Check & Paywall Presentation
            if !subManager.isPro && UsageTracker.shared.hasReachedFreeLimit() {
                showPaywall = true
                return
            }
            
            // Increment usage limit for free users
            if !subManager.isPro {
                UsageTracker.shared.incrementUsage()
            }
            
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            viewModel.generateReel(isPro: subManager.isPro)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 20, weight: .semibold))
                    .symbolEffect(.bounce, value: buttonPressed)
                
                Text("Oluştur")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                ZStack {
                    // Gradient background
                    RoundedRectangle(cornerRadius: 16)
                        .fill(accentGradient)
                    
                    // Inner highlight
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(
                color: Color(hex: "8B5CF6").opacity(0.4),
                radius: 20,
                x: 0,
                y: 8
            )
            .scaleEffect(buttonPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        buttonPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        buttonPressed = false
                    }
                }
        )
        .disabled(viewModel.isGenerating)
        .opacity(viewModel.isGenerating ? 0.6 : 1.0)
        .accessibilityIdentifier("generateButton")
    }
    
    // MARK: - Recent Generations Section
    
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Son Oluşturulanlar")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.6))
                
                Spacer()
                
                if !videoHistory.items.isEmpty {
                    Text("\(videoHistory.items.count) video")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "8B5CF6").opacity(0.7))
                }
            }
            
            if videoHistory.items.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 36))
                        .foregroundColor(Color.white.opacity(0.1))
                    
                    Text("Henüz video oluşturmadınız")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.2))
                    
                    Text("Yukarıdan bir konu girerek\nilk videonuzu oluşturun")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.12))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
                .accessibilityIdentifier("recentGenerationsEmpty")
            } else {
                // Video history list
                VStack(spacing: 12) {
                    ForEach(videoHistory.items) { item in
                        recentVideoRow(item: item)
                    }
                }
            }
        }
        .sheet(item: $selectedHistoryItem) { item in
            if let url = item.fileURL {
                NavigationStack {
                    VideoPreviewView(
                        videoURL: url,
                        onNewVideo: { }
                    )
                }
            }
        }
    }
    
    /// A single row in the recent generations list
    private func recentVideoRow(item: VideoHistoryItem) -> some View {
        HStack(spacing: 14) {
            // Video icon / thumbnail placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "8B5CF6").opacity(0.2),
                                Color(hex: "EC4899").opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.8))
            }
            .frame(width: 52, height: 52)
            .onTapGesture {
                selectedHistoryItem = item
            }
            
            // Topic + date
            VStack(alignment: .leading, spacing: 4) {
                Text(item.topic)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(item.formattedDate)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.35))
            }
            .onTapGesture {
                selectedHistoryItem = item
            }
            
            Spacer()
            
            // Delete button
            Button {
                withAnimation {
                    videoHistory.removeItem(item)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.red.opacity(0.8))
                    .frame(width: 44, height: 44) // Tap target
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .accessibilityIdentifier("historyItem_\(item.id)")
    }
    
    // MARK: - Ambient Glow
    
    private var ambientGlow: some View {
        ZStack {
            // Top-right purple orb
            Circle()
                .fill(Color(hex: "8B5CF6").opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 120, y: -200)
                .scaleEffect(glowAnimation ? 1.1 : 0.9)
            
            // Bottom-left pink orb
            Circle()
                .fill(Color(hex: "EC4899").opacity(0.06))
                .frame(width: 250, height: 250)
                .blur(radius: 70)
                .offset(x: -100, y: 300)
                .scaleEffect(glowAnimation ? 0.9 : 1.1)
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Media Picker Section
    
    private var mediaPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section label
            HStack(spacing: 6) {
                Image(systemName: "iphone.badge.play")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "8B5CF6"))
                
                Text("EKRAN KAYDI (MOCKUP MODU)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.4))
                    .tracking(2)
            }
            
            ZStack {
                // Glass background
                RoundedRectangle(cornerRadius: 16)
                    .fill(glassBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                viewModel.userMediaURL != nil
                                    ? Color(hex: "8B5CF6").opacity(0.5)
                                    : glassBorder,
                                lineWidth: 1
                            )
                    )
                
                HStack(spacing: 16) {
                    if isLoadingVideo {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color(hex: "8B5CF6"))
                            .frame(width: 24, height: 24)
                        
                        Text("Video yükleniyor...")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.6))
                        
                        Spacer()
                    } else if let userURL = viewModel.userMediaURL {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: "8B5CF6").opacity(0.15))
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color(hex: "EC4899"))
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ekran Kaydı Seçildi 📱")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text("Mockup modunda video birleştirilecek")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundColor(Color.white.opacity(0.4))
                        }
                        
                        Spacer()
                        
                        // Clear button
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.userMediaURL = nil
                                selectedPickerItem = nil
                            }
                        } label: {
                            Image(systemName: "trash.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Color.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    } else {
                        PhotosPicker(selection: $selectedPickerItem, matching: .videos) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.06))
                                        .frame(width: 36, height: 36)
                                    
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ekran Kaydı Ekle")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                    
                                    Text("iPhone 15 mockup'ı içine giydirmek için")
                                        .font(.system(size: 12, weight: .regular, design: .rounded))
                                        .foregroundColor(Color.white.opacity(0.4))
                                }
                                
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 64)
            }
            .frame(height: 64)
        }
        .onChange(of: selectedPickerItem) { _, item in
            guard let item = item else { return }
            isLoadingVideo = true
            
            Task {
                do {
                    if let movie = try await item.loadTransferable(type: Movie.self) {
                        await MainActor.run {
                            viewModel.userMediaURL = movie.url
                            isLoadingVideo = false
                        }
                    } else {
                        await MainActor.run {
                            viewModel.errorMessage = "Video formatı desteklenmiyor."
                            isLoadingVideo = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        viewModel.errorMessage = "Video yüklenemedi: \(error.localizedDescription)"
                        isLoadingVideo = false
                    }
                }
            }
        }
    }
}

// MARK: - Movie Transferable Representation

struct Movie: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = TempFileManager.shared.uniqueTempURL(extension: "mp4")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Movie(url: copy)
        }
    }
}

// MARK: - Color Extension

extension Color {
    /// Creates a Color from a hex string (e.g., "8B5CF6")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview

#Preview {
    HomeView()
}
