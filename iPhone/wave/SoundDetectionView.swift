//
//  SoundDetectionView.swift
//  wave
//

import SwiftUI

struct SoundDetectionView: View {

    @ObservedObject private var audio = AudioDetector.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Toggle
                HStack {
                    Label("声音监听", systemImage: "mic.fill")
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: $audio.isRunning)
                        .labelsHidden()
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                if audio.isRunning {
                    // Level meter (circular)
                    levelGauge

                    // dB values
                    dbDisplay

                    // Waveform
                    waveformView

                    // Level bars (frequency-style)
                    levelBarsView
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "mic.slash")
                            .font(.system(size: 64))
                            .foregroundStyle(.tertiary)
                        Text("打开监听开关以检测声音")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 60)
                }
            }
            .padding()
        }
        .navigationTitle("声音检测")
    }

    // MARK: - Circular level gauge

    private var levelGauge: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray4), lineWidth: 10)
                .frame(width: 160, height: 160)

            Circle()
                .trim(from: 0, to: CGFloat(audio.normalizedLevel))
                .stroke(
                    levelColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.05), value: audio.normalizedLevel)

            VStack(spacing: 4) {
                Text(String(format: "%.0f", audio.currentLevel))
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(levelColor)
                Text("dBFS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - dB display

    private var dbDisplay: some View {
        HStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("平均")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f dB", audio.currentLevel))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
            VStack(spacing: 4) {
                Text("峰值")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f dB", audio.peakLevel))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.orange)
            }
            VStack(spacing: 4) {
                Text("音量")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", audio.normalizedLevel * 100))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(levelColor)
            }
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Waveform

    private var waveformView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("实时波形")
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let count = audio.levelHistory.count

                if count > 1 {
                    Path { path in
                        for (i, level) in audio.levelHistory.enumerated() {
                            let x = w * CGFloat(i) / CGFloat(count - 1)
                            let y = h * (1 - CGFloat(level))
                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [.green, .yellow, .red],
                            startPoint: .bottom, endPoint: .top
                        ),
                        lineWidth: 2
                    )

                    // Fill under curve
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: h))
                        for (i, level) in audio.levelHistory.enumerated() {
                            let x = w * CGFloat(i) / CGFloat(count - 1)
                            let y = h * (1 - CGFloat(level))
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.3), .yellow.opacity(0.1), .clear],
                            startPoint: .bottom, endPoint: .top
                        )
                    )
                }
            }
            .frame(height: 120)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Level bars

    private var levelBarsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("音量柱")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<audio.levelHistory.suffix(40).count, id: \.self) { i in
                    let level = Array(audio.levelHistory.suffix(40))[i]
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barColor(level))
                        .frame(height: max(2, CGFloat(level) * 80))
                }
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Colors

    private var levelColor: Color {
        if audio.normalizedLevel < 0.3 { return .green }
        if audio.normalizedLevel < 0.7 { return .yellow }
        return .red
    }

    private func barColor(_ level: Float) -> Color {
        if level < 0.3 { return .green }
        if level < 0.7 { return .yellow }
        return .red
    }
}

#Preview {
    NavigationStack {
        SoundDetectionView()
    }
}
