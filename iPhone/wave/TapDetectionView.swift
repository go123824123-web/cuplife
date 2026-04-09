//
//  TapDetectionView.swift
//  wave
//
//  Created by C on 2026/4/8.
//

import SwiftUI

struct TapDetectionView: View {

    @ObservedObject private var detector = TapDetector.shared
    @State private var showInfo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Toggle
                HStack {
                    Label("检测开关", systemImage: "waveform.path")
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: $detector.isRunning)
                        .labelsHidden()
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                if detector.isRunning {
                    // Tap indicator
                    ZStack {
                        Circle()
                            .fill(detector.tapDetected ? Color.red.opacity(0.15) : Color.green.opacity(0.08))
                            .frame(width: 160, height: 160)
                            .scaleEffect(detector.tapDetected ? 1.15 : 1.0)
                            .animation(.easeOut(duration: 0.3), value: detector.tapDetected)

                        Circle()
                            .strokeBorder(detector.tapDetected ? .red : .green, lineWidth: 3)
                            .frame(width: 160, height: 160)

                        VStack(spacing: 6) {
                            Image(systemName: detector.tapDetected ? "hand.tap.fill" : "hand.tap")
                                .font(.system(size: 36))
                                .foregroundStyle(detector.tapDetected ? .red : .green)
                            Text(detector.tapDetected ? "检测到拍打!" : "监听中...")
                                .font(.headline)
                                .foregroundStyle(detector.tapDetected ? .red : .primary)
                        }
                    }

                    // Force
                    Text(String(format: "%.3f g", detector.lastForce))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(forceColor(detector.lastForce))

                    liveMagnitudeBar

                    // Threshold & Cooldown sliders
                    parameterSection

                    // History
                    if !detector.tapHistory.isEmpty {
                        tapHistorySection
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 64))
                            .foregroundStyle(.tertiary)
                        Text("打开检测开关，然后拍打桌面")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 60)
                }
            }
            .padding()
        }
        .navigationTitle("拍打检测")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showInfo) {
            InfoSheet(detector: detector)
        }
    }

    // MARK: - Parameter adjustments (on main page)

    private var parameterSection: some View {
        VStack(spacing: 16) {
            // Threshold
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("拍打阈值")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.3f g", detector.threshold))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                Slider(value: $detector.threshold, in: 0.02...1.0, step: 0.01)
                    .tint(.orange)
                Text("值越低越灵敏，越高越不容易误触发")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Cooldown
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("冷却时间")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.1f 秒", detector.cooldown))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.blue)
                }
                Slider(value: $detector.cooldown, in: 0.1...2.0, step: 0.1)
                    .tint(.blue)
                Text("两次拍打之间的最短间隔")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    private var liveMagnitudeBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let ratio = min(detector.currentMagnitude / max(detector.threshold * 3, 0.01), 1.0)
                let thresholdRatio = min(detector.threshold / max(detector.threshold * 3, 0.01), 1.0)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(detector.currentMagnitude >= detector.threshold ? Color.red : Color.green)
                        .frame(width: geo.size.width * ratio)
                        .animation(.linear(duration: 0.05), value: detector.currentMagnitude)

                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 2)
                        .offset(x: geo.size.width * thresholdRatio)
                }
            }
            .frame(height: 8)

            HStack {
                Text("0")
                Spacer()
                Text("阈值")
                    .foregroundStyle(.orange)
                Spacer()
                Text(String(format: "%.2fg", detector.threshold * 3))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var tapHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("历史记录")
                    .font(.headline)
                Spacer()
                Button("清除") { detector.clearHistory() }
                    .font(.caption)
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(detector.tapHistory) { event in
                        HStack {
                            Circle()
                                .fill(forceColor(event.force))
                                .frame(width: 8, height: 8)
                            Text(event.timestamp, style: .time)
                                .font(.caption)
                                .monospacedDigit()
                            Spacer()
                            Text(String(format: "%.3f g", event.force))
                                .font(.system(.caption, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(forceColor(event.force))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(maxHeight: 180)
        }
    }

    private var idlePlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "hand.tap")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("打开检测开关，然后拍打桌面")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func forceColor(_ force: Double) -> Color {
        if force < detector.threshold * 2 { return .green }
        if force < detector.threshold * 5 { return .orange }
        return .red
    }

}

// MARK: - Sensor Components (shared)

struct SensorSection<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let isAvailable: Bool
    @Binding var isEnabled: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        Section {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(isEnabled ? .green : .secondary)
                        .font(.title2)
                }

                Spacer()

                if isAvailable {
                    Toggle("", isOn: $isEnabled)
                        .labelsHidden()
                } else {
                    Text("不可用")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)

            if isEnabled {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isEnabled)
    }
}

struct XYZRow: View {
    let label: String
    let data: MotionManager.XYZ
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                AxisValue(axis: "X", value: data.x, color: .red)
                AxisValue(axis: "Y", value: data.y, color: .green)
                AxisValue(axis: "Z", value: data.z, color: .blue)
            }

            Text("|\(label)| = \(magnitude(data), specifier: "%.4f") \(unit)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private func magnitude(_ v: MotionManager.XYZ) -> Double {
        (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
    }
}

struct AttitudeRow: View {
    let attitude: MotionManager.Attitude

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("姿态")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                AxisValue(axis: "横滚", value: attitude.roll, color: .red)
                AxisValue(axis: "俯仰", value: attitude.pitch, color: .green)
                AxisValue(axis: "偏航", value: attitude.yaw, color: .blue)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AxisValue: View {
    let axis: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(axis)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(String(format: "%+.4f", value))
                .font(.system(.caption, design: .monospaced))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Info Sheet (详细中文说明)

private struct InfoSheet: View {

    @ObservedObject var detector: TapDetector
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("工作原理") {
                    VStack(alignment: .leading, spacing: 12) {
                        infoRow(icon: "iphone.radiowaves.left.and.right",
                                text: "将手机平放在桌面上。当你拍打桌面时，振动会通过桌面传导到手机。")
                        infoRow(icon: "waveform.path.ecg",
                                text: "应用调用 iPhone 内置的加速度计和陀螺仪，通过苹果的 Core Motion 框架获取「用户加速度」——即去除重力后的纯振动加速度。")
                        infoRow(icon: "function",
                                text: "每秒采集 100 次数据，计算三个方向 (X/Y/Z) 的合成加速度。当合成值超过你设定的阈值时，就判定为一次拍打。")
                        infoRow(icon: "timer",
                                text: "一次拍桌子其实会产生好几个连续的加速度尖峰。冷却时间确保这些尖峰只被算作一次拍打，而不是重复计数。")
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("什么是「g」？")
                            .font(.headline)
                        Text("g 是重力加速度单位。1g = 9.8 m/s²，就是地球表面的重力加速度。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("手机静止平放时，加速度计读数约为 1g（来自重力）。本应用使用的是去除重力后的「用户加速度」，所以静止时接近 0g。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        Text("力度参考值")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        VStack(alignment: .leading, spacing: 4) {
                            forceExample("0.02 ~ 0.10g", desc: "轻微振动（走路、轻敲桌面）")
                            forceExample("0.10 ~ 0.30g", desc: "中等拍打（正常拍桌子）")
                            forceExample("0.30 ~ 0.80g", desc: "用力拍打")
                            forceExample("> 1.0g", desc: "非常用力的撞击")
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("力度单位说明")
                }

                Section("使用的传感器") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text("加速度计（Accelerometer）")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        } icon: {
                            Image(systemName: "move.3d")
                                .foregroundStyle(.blue)
                        }
                        Text("测量手机在三个方向上的加速度变化。是检测振动的核心传感器。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        Label {
                            Text("陀螺仪（Gyroscope）")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        } icon: {
                            Image(systemName: "gyroscope")
                                .foregroundStyle(.blue)
                        }
                        Text("测量手机的旋转角速度。配合加速度计一起使用，可以更精确地分离出重力和用户加速度。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        Label {
                            Text("传感器融合（Device Motion）")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        } icon: {
                            Image(systemName: "sensor.fill")
                                .foregroundStyle(.blue)
                        }
                        Text("苹果系统自动将加速度计和陀螺仪的数据融合，输出去除了重力分量的「用户加速度」(userAcceleration)。本应用使用的正是这个融合后的数据。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("采样频率")
                        Spacer()
                        Text("100 次/秒")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("拍打阈值")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.3f g", detector.threshold))
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                        }
                        Slider(value: $detector.threshold, in: 0.02...1.0, step: 0.01)
                            .tint(.orange)
                        Text("当振动加速度超过此值时，判定为一次拍打。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("调小 → 更灵敏，轻轻拍也能检测到，但可能误触发\n调大 → 不那么灵敏，需要更用力才能触发，误触发少")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("冷却时间")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.1f 秒", detector.cooldown))
                                .monospacedDigit()
                                .foregroundStyle(.blue)
                        }
                        Slider(value: $detector.cooldown, in: 0.1...2.0, step: 0.1)
                            .tint(.blue)
                        Text("两次拍打之间的最短间隔时间。\n调小 → 可以快速连续拍打\n调大 → 避免一次拍打被算成多次")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("阈值设置")
                } footer: {
                    Text("建议：先用默认值试试，如果太灵敏就调高阈值，如果检测不到就调低阈值。")
                }

                Section("使用技巧") {
                    Label("将手机屏幕朝上平放效果最佳。", systemImage: "iphone")
                    Label("硬质桌面（木头、金属、玻璃）传导振动效果更好。", systemImage: "table.furniture")
                    Label("拍打位置离手机越远，检测到的力度越弱。", systemImage: "ruler")
                    Label("可以切换到「原始传感器」页查看实时数据。", systemImage: "sensor.fill")
                }
                .font(.caption)
            }
            .navigationTitle("关于拍打检测")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        Label {
            Text(text).font(.caption)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
        }
    }

    private func forceExample(_ range: String, desc: String) -> some View {
        HStack(spacing: 8) {
            Text(range)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.orange)
                .frame(width: 110, alignment: .leading)
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        TapDetectionView()
    }
}
