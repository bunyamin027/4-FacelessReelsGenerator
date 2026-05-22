// GenerationProgressView.swift
// Faceless
//
// Animated progress overlay displayed during reel generation.

import SwiftUI

// MARK: - GenerationProgressView

/// A premium progress overlay that displays during the reel generation pipeline.
/// Features an animated progress ring, phase indicators, and cancel support.
struct GenerationProgressView: View {
    
    // MARK: - Properties
    
    let currentPhase: GenerationPhase
    let progress: Double
    let onCancel: () -> Void
    
    @State private var ringRotation: Double = 0
    @State private var iconBounce: Bool = false
    @State private var phaseTextOpacity: Double = 0
    @State private var shimmerOffset: CGFloat = -200
    
    // MARK: - Constants
    
    private let ringSize: CGFloat = 160
    private let ringLineWidth: CGFloat = 8
    
    private let accentGradient = LinearGradient(
        colors: [
            Color(hex: "8B5CF6"),
            Color(hex: "EC4899"),
            Color(hex: "8B5CF6")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    private let pipelinePhases: [GenerationPhase] = [
        .creatingBlueprint,
        .fetchingVideo,
        .generatingVoiceover,
        .rendering
    ]
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Blurred dark background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
            
            VStack(spacing: 40) {
                Spacer()
                
                // Progress ring
                progressRing
                
                // Phase info
                phaseInfo
                
                // Step indicators
                stepIndicators
                    .padding(.top, 8)
                
                Spacer()
                
                // Cancel button
                cancelButton
                    .padding(.bottom, 48)
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            startAnimations()
        }
        .onChange(of: currentPhase) { _, _ in
            triggerPhaseTransition()
        }
    }
    
    // MARK: - Progress Ring
    
    private var progressRing: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(
                    Color.white.opacity(0.06),
                    lineWidth: ringLineWidth
                )
                .frame(width: ringSize, height: ringSize)
            
            // Animated gradient ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(hex: "8B5CF6"),
                            Color(hex: "A855F7"),
                            Color(hex: "EC4899"),
                            Color(hex: "8B5CF6")
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(
                        lineWidth: ringLineWidth,
                        lineCap: .round
                    )
                )
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)
            
            // Glow behind ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color(hex: "8B5CF6").opacity(0.3),
                    lineWidth: ringLineWidth + 8
                )
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(-90))
                .blur(radius: 8)
                .animation(.easeInOut(duration: 0.6), value: progress)
            
            // Center content
            VStack(spacing: 8) {
                // Animated phase icon
                Image(systemName: currentPhase.systemIconName)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(accentGradient)
                    .symbolEffect(.pulse, isActive: !currentPhase.isTerminal)
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(iconBounce ? 1.1 : 1.0)
                
                // Percentage
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText(value: progress))
                    .animation(.spring(response: 0.4), value: progress)
            }
        }
        .accessibilityIdentifier("progressRing")
    }
    
    // MARK: - Phase Info
    
    private var phaseInfo: some View {
        VStack(spacing: 8) {
            // Phase label with typewriter effect
            Text(currentPhase.rawValue)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .opacity(phaseTextOpacity)
                .animation(.easeInOut(duration: 0.3), value: currentPhase)
                .id(currentPhase) // Force re-render on phase change
            
            // Subtle subtitle
            if !currentPhase.isTerminal {
                Text("Lütfen bekleyin...")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.35))
            }
        }
        .accessibilityIdentifier("phaseLabel")
    }
    
    // MARK: - Step Indicators
    
    private var stepIndicators: some View {
        VStack(spacing: 12) {
            ForEach(Array(pipelinePhases.enumerated()), id: \.element) { index, phase in
                stepRow(for: phase, index: index)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .accessibilityIdentifier("stepIndicators")
    }
    
    private func stepRow(for phase: GenerationPhase, index: Int) -> some View {
        let state = stepState(for: phase)
        
        return HStack(spacing: 14) {
            // Status icon
            ZStack {
                Circle()
                    .fill(state.backgroundColor)
                    .frame(width: 28, height: 28)
                
                Image(systemName: state.iconName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(state.iconColor)
            }
            
            // Phase name
            Text(phase.rawValue)
                .font(.system(size: 14, weight: state.isActive ? .semibold : .regular, design: .rounded))
                .foregroundColor(state.textColor)
            
            Spacer()
            
            // Activity indicator for current phase
            if state.isActive {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color(hex: "8B5CF6"))
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.3), value: currentPhase)
    }
    
    // MARK: - Cancel Button
    
    private var cancelButton: some View {
        Button {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onCancel()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                
                Text("İptal Et")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
            }
            .foregroundColor(Color.white.opacity(0.5))
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .accessibilityIdentifier("cancelGenerationButton")
    }
    
    // MARK: - Step State
    
    private struct StepState {
        let isCompleted: Bool
        let isActive: Bool
        let isPending: Bool
        
        var iconName: String {
            if isCompleted { return "checkmark" }
            if isActive { return "circle.fill" }
            return "circle"
        }
        
        var iconColor: Color {
            if isCompleted { return .white }
            if isActive { return Color(hex: "8B5CF6") }
            return Color.white.opacity(0.2)
        }
        
        var backgroundColor: Color {
            if isCompleted { return Color(hex: "8B5CF6").opacity(0.8) }
            if isActive { return Color(hex: "8B5CF6").opacity(0.15) }
            return Color.white.opacity(0.04)
        }
        
        var textColor: Color {
            if isCompleted { return Color.white.opacity(0.8) }
            if isActive { return .white }
            return Color.white.opacity(0.25)
        }
    }
    
    private func stepState(for phase: GenerationPhase) -> StepState {
        let currentIndex = pipelinePhases.firstIndex(of: currentPhase) ?? -1
        let phaseIndex = pipelinePhases.firstIndex(of: phase) ?? -1
        
        let isCompleted: Bool
        if currentPhase == .completed {
            isCompleted = true
        } else {
            isCompleted = phaseIndex < currentIndex
        }
        
        let isActive = phase == currentPhase
        let isPending = phaseIndex > currentIndex
        
        return StepState(isCompleted: isCompleted, isActive: isActive, isPending: isPending)
    }
    
    // MARK: - Animations
    
    private func startAnimations() {
        // Phase text fade-in
        withAnimation(.easeIn(duration: 0.4).delay(0.2)) {
            phaseTextOpacity = 1.0
        }
        
        // Icon bounce loop
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            iconBounce = true
        }
    }
    
    private func triggerPhaseTransition() {
        // Reset text opacity for typewriter effect
        phaseTextOpacity = 0
        withAnimation(.easeIn(duration: 0.3).delay(0.1)) {
            phaseTextOpacity = 1.0
        }
    }
}

// MARK: - Terminal State Extension

extension GenerationPhase {
    /// Whether this phase is a terminal state (idle, completed, or failed)
    var isTerminal: Bool {
        self == .completed || self == .failed || self == .idle
    }
}

// MARK: - Preview

#Preview {
    GenerationProgressView(
        currentPhase: .generatingVoiceover,
        progress: 0.5,
        onCancel: {}
    )
}
