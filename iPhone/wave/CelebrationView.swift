//
//  CelebrationView.swift
//  wave
//

import SwiftUI
import AVFoundation

struct ConfettiPiece: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    let size: CGFloat
    let color: Color
    let rotation: Double
    let speed: CGFloat
    let wobble: CGFloat
}

struct CelebrationOverlay: View {
    @Binding var isShowing: Bool
    @State private var particles: [ConfettiPiece] = []
    @State private var animationProgress: CGFloat = 0

    private let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink]

    var body: some View {
        if isShowing {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()

                GeometryReader { geo in
                    ForEach(particles) { p in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(p.color)
                            .frame(width: p.size, height: p.size * 0.6)
                            .rotationEffect(.degrees(p.rotation + Double(animationProgress) * 360 * Double(p.wobble)))
                            .position(
                                x: p.x + sin(animationProgress * .pi * 2 * p.wobble) * 30,
                                y: p.y + geo.size.height * animationProgress * p.speed
                            )
                            .opacity(Double(1 - animationProgress))
                    }
                }

                VStack(spacing: 8) {
                    Text("🎉")
                        .font(.system(size: 80))
                        .scaleEffect(animationProgress < 0.3 ? 1 + animationProgress * 2 : 1.6 - animationProgress)

                    Text("喝水完成!")
                        .font(.title2).fontWeight(.bold)
                        .foregroundStyle(.white)
                        .opacity(Double(1 - animationProgress * 0.8))
                }
            }
            .onAppear {
                generateParticles()
                playCelebrationSounds()
                withAnimation(.easeOut(duration: 2.0)) {
                    animationProgress = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    isShowing = false
                    animationProgress = 0
                    particles = []
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func generateParticles() {
        let w = UIScreen.main.bounds.width
        particles = (0..<60).map { _ in
            ConfettiPiece(
                x: CGFloat.random(in: 0...w),
                y: CGFloat.random(in: -100...0),
                size: CGFloat.random(in: 6...12),
                color: colors.randomElement()!,
                rotation: Double.random(in: 0...360),
                speed: CGFloat.random(in: 0.6...1.2),
                wobble: CGFloat.random(in: 0.5...2.0)
            )
        }
    }

    private func playCelebrationSounds() {
        // Multiple system sounds for a celebration feel
        AudioServicesPlaySystemSound(1025)  // positive ding
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AudioServicesPlaySystemSound(1016) // tweet
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AudioServicesPlaySystemSound(1025)
        }
    }
}
