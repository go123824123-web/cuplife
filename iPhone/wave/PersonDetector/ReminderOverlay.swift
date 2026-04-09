//
//  ReminderOverlay.swift
//  wave
//
//  定时提醒弹窗：分析精神状态 + 提示喝水 + 显示照片
//

import SwiftUI
import AVKit

struct ReminderOverlay: View {
    @ObservedObject var analyzer: FaceAnalyzer
    @State private var player: AVPlayer?

    var body: some View {
        if analyzer.showReminder, let reminder = analyzer.currentReminder {
            ZStack {
                Color.black.opacity(0.85).ignoresSafeArea()

                VStack(spacing: 16) {
                    Spacer().frame(height: 30)

                    // Thirsty cat video
                    if let url = Bundle.main.url(forResource: analyzer.reminderVideoName, withExtension: "mov") {
                        VideoPlayer(player: player ?? createPlayer(url: url))
                            .disabled(true)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal, 40)
                            .onAppear { setupVideo(url: url) }
                    }

                    // Message
                    Text(reminder.message)
                        .font(.title3).fontWeight(.bold)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    // Energy score + tags
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().stroke(scoreColor(reminder.energyScore).opacity(0.3), lineWidth: 3)
                                .frame(width: 36, height: 36)
                            Text("\(reminder.energyScore)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(scoreColor(reminder.energyScore))
                        }
                        ForEach(reminder.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.white.opacity(0.12), in: Capsule())
                        }
                    }

                    // Snapshot photo (if available and enabled)
                    if analyzer.showSnapshot, let snapshot = reminder.snapshot {
                        VStack(spacing: 6) {
                            Image(decorative: snapshot, scale: 1)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                )
                            Text("刚才的你")
                                .font(.caption2).foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    Spacer()

                    // Dismiss button
                    Button {
                        player?.pause()
                        player = nil
                        analyzer.dismissReminder()
                    } label: {
                        Text("好的，我去喝水")
                            .font(.headline)
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                            .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 24))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                }
            }
            .transition(.opacity)
        }
    }

    private func createPlayer(url: URL) -> AVPlayer {
        let p = AVPlayer(url: url)
        return p
    }

    private func setupVideo(url: URL) {
        let p = AVPlayer(url: url)
        p.isMuted = false
        // Loop
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in
            p.seek(to: .zero)
            p.play()
        }
        p.play()
        player = p
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 7 { return .green }
        if score >= 4 { return .yellow }
        return .red
    }
}
