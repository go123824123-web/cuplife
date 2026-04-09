//
//  MotionManager.swift
//  wave
//
//  Created by C on 2026/4/8.
//

import Foundation
import CoreMotion
import Combine

final class MotionManager: ObservableObject {

    // MARK: - Sensor availability

    var isAccelerometerAvailable: Bool { manager.isAccelerometerAvailable }
    var isGyroAvailable: Bool { manager.isGyroAvailable }
    var isMagnetometerAvailable: Bool { manager.isMagnetometerAvailable }
    var isDeviceMotionAvailable: Bool { manager.isDeviceMotionAvailable }

    // MARK: - Toggle states

    @Published var accelerometerEnabled = false { didSet { toggleAccelerometer() } }
    @Published var gyroEnabled = false { didSet { toggleGyro() } }
    @Published var magnetometerEnabled = false { didSet { toggleMagnetometer() } }
    @Published var deviceMotionEnabled = false { didSet { toggleDeviceMotion() } }

    // MARK: - Raw sensor data

    struct XYZ: Equatable {
        var x: Double = 0
        var y: Double = 0
        var z: Double = 0
    }

    struct Attitude: Equatable {
        var roll: Double = 0
        var pitch: Double = 0
        var yaw: Double = 0
    }

    @Published var acceleration = XYZ()
    @Published var rotationRate = XYZ()
    @Published var magneticField = XYZ()

    @Published var attitude = Attitude()
    @Published var gravity = XYZ()
    @Published var userAcceleration = XYZ()

    // MARK: - Private

    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private let updateInterval: TimeInterval = 1.0 / 60.0 // 60 Hz

    init() {
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
    }

    deinit {
        stopAll()
    }

    func stopAll() {
        accelerometerEnabled = false
        gyroEnabled = false
        magnetometerEnabled = false
        deviceMotionEnabled = false
    }

    // MARK: - Accelerometer

    private func toggleAccelerometer() {
        if accelerometerEnabled {
            guard manager.isAccelerometerAvailable else {
                accelerometerEnabled = false
                return
            }
            manager.accelerometerUpdateInterval = updateInterval
            manager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
                guard let data else { return }
                let acc = XYZ(x: data.acceleration.x,
                              y: data.acceleration.y,
                              z: data.acceleration.z)
                DispatchQueue.main.async { self?.acceleration = acc }
            }
        } else {
            manager.stopAccelerometerUpdates()
            acceleration = XYZ()
        }
    }

    // MARK: - Gyroscope

    private func toggleGyro() {
        if gyroEnabled {
            guard manager.isGyroAvailable else {
                gyroEnabled = false
                return
            }
            manager.gyroUpdateInterval = updateInterval
            manager.startGyroUpdates(to: queue) { [weak self] data, _ in
                guard let data else { return }
                let rate = XYZ(x: data.rotationRate.x,
                               y: data.rotationRate.y,
                               z: data.rotationRate.z)
                DispatchQueue.main.async { self?.rotationRate = rate }
            }
        } else {
            manager.stopGyroUpdates()
            rotationRate = XYZ()
        }
    }

    // MARK: - Magnetometer

    private func toggleMagnetometer() {
        if magnetometerEnabled {
            guard manager.isMagnetometerAvailable else {
                magnetometerEnabled = false
                return
            }
            manager.magnetometerUpdateInterval = updateInterval
            manager.startMagnetometerUpdates(to: queue) { [weak self] data, _ in
                guard let data else { return }
                let field = XYZ(x: data.magneticField.x,
                                y: data.magneticField.y,
                                z: data.magneticField.z)
                DispatchQueue.main.async { self?.magneticField = field }
            }
        } else {
            manager.stopMagnetometerUpdates()
            magneticField = XYZ()
        }
    }

    // MARK: - Device Motion (Sensor Fusion)

    private func toggleDeviceMotion() {
        if deviceMotionEnabled {
            guard manager.isDeviceMotionAvailable else {
                deviceMotionEnabled = false
                return
            }
            manager.deviceMotionUpdateInterval = updateInterval
            manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
                guard let motion else { return }
                let att = Attitude(roll: motion.attitude.roll,
                                   pitch: motion.attitude.pitch,
                                   yaw: motion.attitude.yaw)
                let grav = XYZ(x: motion.gravity.x,
                               y: motion.gravity.y,
                               z: motion.gravity.z)
                let userAcc = XYZ(x: motion.userAcceleration.x,
                                  y: motion.userAcceleration.y,
                                  z: motion.userAcceleration.z)
                DispatchQueue.main.async {
                    self?.attitude = att
                    self?.gravity = grav
                    self?.userAcceleration = userAcc
                }
            }
        } else {
            manager.stopDeviceMotionUpdates()
            attitude = Attitude()
            gravity = XYZ()
            userAcceleration = XYZ()
        }
    }
}
