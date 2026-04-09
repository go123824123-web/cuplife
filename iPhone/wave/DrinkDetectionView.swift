//
//  DrinkDetectionView.swift
//  wave
//

import SwiftUI

struct DrinkDetectionView: View {
    @ObservedObject private var detector = DrinkDetector.shared
    @State private var showInfo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Toggle
                HStack {
                    Label("喝水检测", systemImage: "cup.and.saucer.fill").font(.headline)
                    Spacer()
                    Toggle("", isOn: $detector.isRunning).labelsHidden()
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                if detector.isRunning {
                    // Big count
                    VStack(spacing: 4) {
                        Text("\(detector.todayCount)")
                            .font(.system(size: 56, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                        Text("今日喝水次数").font(.caption).foregroundStyle(.secondary)
                    }

                    // === Two task checklist ===
                    taskChecklist

                    // Tilt gauge
                    tiltGauge

                    // Phase status
                    phaseStatusBar

                    // Parameters
                    parameterSection

                    // History
                    if !detector.history.isEmpty { historySection }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "cup.and.saucer").font(.system(size: 64)).foregroundStyle(.tertiary)
                        Text("打开检测开关，将手机当作水杯").foregroundStyle(.secondary)
                    }.padding(.vertical, 60)
                }
            }
            .padding()
        }
        .navigationTitle("喝水检测")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showInfo = true } label: { Image(systemName: "info.circle") }
            }
        }
        .sheet(isPresented: $showInfo) { DrinkInfoSheet() }
    }

    // MARK: - Task Checklist (核心：两个任务打勾)

    private var taskChecklist: some View {
        VStack(spacing: 12) {
            // 任务 1：倾斜超过阈值
            HStack(spacing: 12) {
                checkCircle(passed: detector.tiltCheckPassed)

                VStack(alignment: .leading, spacing: 2) {
                    Text("任务一：倾斜超过 \(Int(detector.tiltThreshold))°")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundStyle(detector.tiltCheckPassed ? .green : .white)
                    Text("当前倾斜 \(String(format: "%.1f°", detector.tiltAngle))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(detector.tiltCheckPassed ? .green.opacity(0.7) : .gray)
                }

                Spacer()

                // Live tilt value
                Text(String(format: "%.0f°", detector.tiltAngle))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(detector.tiltCheckPassed ? .green : .white.opacity(0.3))
            }
            .padding(12)
            .background(detector.tiltCheckPassed ? Color.green.opacity(0.1) : Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 10))

            // 任务 2：保持时间达标
            HStack(spacing: 12) {
                checkCircle(passed: detector.holdCheckPassed)

                VStack(alignment: .leading, spacing: 2) {
                    Text("任务二：保持 \(String(format: "%.1f", detector.holdTime)) 秒")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundStyle(detector.holdCheckPassed ? .green : .white)
                    Text("已保持 \(String(format: "%.1f 秒", detector.tiltHoldElapsed))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(detector.holdCheckPassed ? .green.opacity(0.7) : .gray)
                }

                Spacer()

                // Live time
                Text(String(format: "%.1fs", detector.tiltHoldElapsed))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(detector.holdCheckPassed ? .green : .white.opacity(0.3))
            }
            .padding(12)
            .background(detector.holdCheckPassed ? Color.green.opacity(0.1) : Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 10))

            // 结果
            if detector.phase == .drinking {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange)
                    Text("两个任务已完成，回正手机即记录一次喝水")
                        .font(.caption).foregroundStyle(.orange)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            } else if detector.phase == .cooldown {
                HStack {
                    Image(systemName: "party.popper.fill").foregroundStyle(.green)
                    Text("喝水完成! +1")
                        .font(.headline).foregroundStyle(.green)
                }
                .padding(10)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func checkCircle(passed: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(passed ? Color.green : Color.gray.opacity(0.3), lineWidth: 2)
                .frame(width: 28, height: 28)
            if passed {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Tilt gauge

    private var tiltGauge: some View {
        ZStack {
            Circle().stroke(Color(.systemGray4), lineWidth: 8).frame(width: 120, height: 120)

            // Tilt arc
            let tiltRatio = min(detector.tiltAngle / 90.0, 1.0)
            Circle()
                .trim(from: 0, to: tiltRatio)
                .stroke(
                    detector.tiltCheckPassed ? Color.green : Color.cyan,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(-90))

            // Threshold marker
            Circle()
                .trim(from: detector.tiltThreshold / 90.0 - 0.008,
                      to: detector.tiltThreshold / 90.0 + 0.008)
                .stroke(Color.orange, lineWidth: 12)
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(String(format: "%.0f", detector.tiltAngle))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(detector.tiltCheckPassed ? .green : .cyan)
                Text("度").font(.system(size: 9)).foregroundStyle(.gray)
            }
        }
    }

    // MARK: - Phase status

    private var phaseStatusBar: some View {
        HStack(spacing: 16) {
            phaseChip("等待", active: detector.phase == .idle, color: .gray)
            phaseChip("倾斜", active: detector.phase == .tilting, color: .blue)
            phaseChip("喝水", active: detector.phase == .drinking, color: .orange)
            phaseChip("完成", active: detector.phase == .cooldown, color: .green)
        }
    }

    private func phaseChip(_ label: String, active: Bool, color: Color) -> some View {
        Text(label)
            .font(.system(size: 11, weight: active ? .bold : .regular))
            .foregroundStyle(active ? .white : .gray)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(active ? color : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? color : Color.gray.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Parameters

    private var parameterSection: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("倾斜阈值").font(.subheadline).fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.0f°", detector.tiltThreshold))
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.orange)
                }
                Slider(value: $detector.tiltThreshold, in: 10...60, step: 5).tint(.orange)
                Text("水满 15-25° | 半满 30-40° | 水少 45-60°").font(.caption2).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("保持时间").font(.subheadline).fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.1f 秒", detector.holdTime))
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.blue)
                }
                Slider(value: $detector.holdTime, in: 0.3...3.0, step: 0.1).tint(.blue)
                Text("倾斜需保持这么久才算喝水").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("喝水记录").font(.headline)
                Spacer()
                Button("清除") { detector.clearHistory() }.font(.caption)
            }
            ForEach(detector.history) { event in
                HStack {
                    Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                    Text(event.timestamp, style: .time).font(.caption).monospacedDigit()
                    Spacer()
                    Text(String(format: "%.0f°", event.tiltAngle))
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.orange)
                    Text(String(format: "%.1f秒", event.duration))
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.gray)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

// MARK: - Info Sheet

private struct DrinkInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("工作原理") {
                    VStack(alignment: .leading, spacing: 12) {
                        infoRow(icon: "iphone", text: "将手机想象为一杯水。开启检测后，系统自动记录当前角度为「基准」。")
                        infoRow(icon: "arrow.up.right", text: "当手机倾斜角度相对基准变化超过阈值时，任务一「倾斜」完成（绿色打勾）。")
                        infoRow(icon: "timer", text: "保持倾斜达到设定时间后，任务二「保持」完成（绿色打勾）。")
                        infoRow(icon: "checkmark.circle", text: "两个任务都打勾后，回正手机，即完成一次喝水，计数 +1。")
                    }.padding(.vertical, 4)
                }

                Section("默认参数") {
                    HStack { Text("倾斜阈值"); Spacer(); Text("30°").foregroundStyle(.orange) }
                    HStack { Text("保持时间"); Spacer(); Text("1.0 秒").foregroundStyle(.blue) }
                    HStack { Text("冷却时间"); Spacer(); Text("1.5 秒（固定）").foregroundStyle(.gray) }
                }

                Section("使用技巧") {
                    Label("开启后先静止 0.5 秒让系统建立基准", systemImage: "clock")
                    Label("水满时阈值调低（15-25°），水少时调高", systemImage: "drop")
                    Label("基准不准时点「重置基准角度」", systemImage: "arrow.counterclockwise")
                    Label("仪表盘绿色 = 超过阈值，橙色标记 = 阈值位置", systemImage: "gauge")
                }.font(.caption)
            }
            .navigationTitle("关于喝水检测").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } } }
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        Label { Text(text).font(.caption) } icon: {
            Image(systemName: icon).foregroundStyle(.cyan).frame(width: 24)
        }
    }
}

#Preview { NavigationStack { DrinkDetectionView() } }
