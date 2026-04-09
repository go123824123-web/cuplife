//
//  DrinkDetector.swift
//  wave
//
//  喝水检测：手机竖立（像杯子），倾倒时检测角度
//  基准：手机竖直 = 0°，向嘴巴方向倾倒 = 角度增大
//

import Foundation
import CoreMotion
import Combine

struct DrinkEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let tiltAngle: Double
    let duration: TimeInterval
}

enum DrinkPhase: String {
    case idle = "等待中"
    case tilting = "倾斜中"
    case drinking = "喝水中"
    case cooldown = "完成!"
}

final class DrinkDetector: ObservableObject {
    static let shared = DrinkDetector()

    @Published var isRunning = false { didSet { toggle() } }
    @Published var phase: DrinkPhase = .idle
    @Published var drinkCount: Int = 0
    @Published var todayCount: Int = 0
    @Published var history: [DrinkEvent] = []

    // 实时数据（给 UI 用）
    @Published var tiltAngle: Double = 0          // 当前倾倒角度（0° = 竖直，90° = 平躺）
    @Published var rawPitch: Double = 0           // 原始 pitch
    @Published var userAccelMag: Double = 0

    // 任务完成状态
    @Published var tiltCheckPassed = false
    @Published var holdCheckPassed = false
    @Published var tiltHoldElapsed: TimeInterval = 0

    // 可调参数
    @Published var tiltThreshold: Double = 30.0   // 倾倒多少度算喝水
    @Published var holdTime: Double = 1.0         // 保持多少秒

    private let manager = CMMotionManager()
    private let queue = OperationQueue()

    private var tiltStartTime: Date?
    private var maxTilt: Double = 0
    private var cooldownUntil: Date = .distantPast

    init() {
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        loadTodayCount()
    }

    private func toggle() {
        if isRunning { startDetection() } else { stopDetection() }
    }

    private func startDetection() {
        guard manager.isDeviceMotionAvailable else { isRunning = false; return }
        phase = .idle
        tiltCheckPassed = false
        holdCheckPassed = false
        tiltHoldElapsed = 0
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.processMotion(motion)
        }
    }

    private func stopDetection() {
        manager.stopDeviceMotionUpdates()
        phase = .idle
        tiltCheckPassed = false
        holdCheckPassed = false
        tiltHoldElapsed = 0
    }

    private func processMotion(_ motion: CMDeviceMotion) {
        // pitch: 手机竖直时 ≈ 90°（弧度 π/2）
        // 手机平躺屏幕朝上时 ≈ 0°
        // 手机顶部朝下倾倒（喝水动作）时 pitch > 90°
        let pitchDeg = motion.attitude.pitch * 180.0 / .pi

        // 倾倒角度 = 相对竖直（90°）的偏移
        // 竖直时 tilt = 0°
        // 向嘴巴方向倒（顶部朝下）时 tilt > 0
        // 向后仰时 tilt < 0（也算，用 abs）
        let tilt = abs(pitchDeg - 90.0)

        let ua = motion.userAcceleration
        let accel = sqrt(ua.x * ua.x + ua.y * ua.y + ua.z * ua.z)

        DispatchQueue.main.async {
            self.tiltAngle = tilt
            self.rawPitch = pitchDeg
            self.userAccelMag = accel
            self.detect(tilt: tilt)
        }
    }

    private func detect(tilt: Double) {
        let now = Date()

        // 冷却期
        if now < cooldownUntil {
            phase = .cooldown
            return
        }

        if phase == .cooldown {
            phase = .idle
            tiltCheckPassed = false
            holdCheckPassed = false
            tiltHoldElapsed = 0
        }

        switch phase {
        case .idle:
            if tilt > tiltThreshold {
                phase = .tilting
                tiltStartTime = now
                maxTilt = tilt
                tiltCheckPassed = true
                holdCheckPassed = false
                tiltHoldElapsed = 0
            }

        case .tilting:
            maxTilt = max(maxTilt, tilt)

            if tilt > tiltThreshold {
                tiltCheckPassed = true
                if let start = tiltStartTime {
                    tiltHoldElapsed = now.timeIntervalSince(start)
                }
                if tiltHoldElapsed >= holdTime {
                    holdCheckPassed = true
                    phase = .drinking
                }
            } else {
                // 没保持住
                phase = .idle
                tiltCheckPassed = false
                tiltHoldElapsed = 0
                tiltStartTime = nil
            }

        case .drinking:
            maxTilt = max(maxTilt, tilt)
            if let start = tiltStartTime {
                tiltHoldElapsed = now.timeIntervalSince(start)
            }

            // 回正（倾倒角度回到阈值的一半以下）
            if tilt < tiltThreshold * 0.5 {
                let duration = tiltStartTime.map { now.timeIntervalSince($0) } ?? 0
                let event = DrinkEvent(timestamp: now, tiltAngle: maxTilt, duration: duration)
                history.insert(event, at: 0)
                if history.count > 100 { history.removeLast() }
                drinkCount += 1
                todayCount += 1
                saveTodayCount()

                cooldownUntil = now.addingTimeInterval(2.5)
                phase = .cooldown
                tiltStartTime = nil
                maxTilt = 0
            }

        case .cooldown:
            break
        }
    }

    func clearHistory() { history = []; drinkCount = 0 }

    func resetCount() { todayCount = 0; drinkCount = 0; saveTodayCount() }

    // MARK: - 持久化

    private func loadTodayCount() {
        todayCount = UserDefaults.standard.integer(forKey: "drinkCount_\(todayKey)")
        drinkCount = todayCount
    }

    private func saveTodayCount() {
        UserDefaults.standard.set(todayCount, forKey: "drinkCount_\(todayKey)")
    }

    private var todayKey: String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; return f.string(from: Date())
    }

    deinit { manager.stopDeviceMotionUpdates() }
}
