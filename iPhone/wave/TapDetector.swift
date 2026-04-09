//
//  TapDetector.swift
//  wave
//
//  Created by C on 2026/4/8.
//

import Foundation
import CoreMotion
import Combine

final class TapDetector: ObservableObject {

    static let shared = TapDetector()

    // MARK: - Public state

    @Published var isRunning = false { didSet { toggle() } }
    @Published var tapDetected = false
    @Published var lastForce: Double = 0          // peak acceleration magnitude (g)
    @Published var currentMagnitude: Double = 0   // live magnitude for display

    // MARK: - Configurable thresholds

    @Published var threshold: Double = 0.15       // minimum spike to count as tap (g)
    @Published var cooldown: TimeInterval = 0.4   // seconds to ignore after a tap

    // MARK: - Tap history

    struct TapEvent: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let force: Double
    }

    @Published var tapHistory: [TapEvent] = []

    // MARK: - Private

    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private var lastTapTime: Date = .distantPast

    init() {
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
    }

    deinit {
        manager.stopDeviceMotionUpdates()
    }

    func clearHistory() {
        tapHistory = []
    }

    // MARK: - Detection logic

    private func toggle() {
        if isRunning {
            guard manager.isDeviceMotionAvailable else {
                isRunning = false
                return
            }
            tapDetected = false
            lastForce = 0
            currentMagnitude = 0
            manager.deviceMotionUpdateInterval = 1.0 / 100.0 // 100 Hz for responsiveness
            manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
                guard let self, let motion else { return }
                let ua = motion.userAcceleration
                let mag = (ua.x * ua.x + ua.y * ua.y + ua.z * ua.z).squareRoot()

                DispatchQueue.main.async {
                    self.currentMagnitude = mag
                    self.detectTap(magnitude: mag)
                }
            }
        } else {
            manager.stopDeviceMotionUpdates()
            tapDetected = false
            currentMagnitude = 0
        }
    }

    private func detectTap(magnitude: Double) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTapTime)

        if magnitude >= threshold && elapsed >= cooldown {
            tapDetected = true
            lastForce = magnitude
            lastTapTime = now
            tapHistory.insert(TapEvent(timestamp: now, force: magnitude), at: 0)
            if tapHistory.count > 50 { tapHistory.removeLast() }

            // Auto-reset visual indicator after 0.6s
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.tapDetected = false
            }
        }
    }
}
