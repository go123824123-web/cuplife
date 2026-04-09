//
//  AudioDetector.swift
//  wave
//

import Foundation
import AVFoundation
import Combine

final class AudioDetector: ObservableObject {

    static let shared = AudioDetector()

    @Published var isRunning = false { didSet { toggle() } }
    @Published var currentLevel: Float = -160      // dBFS
    @Published var peakLevel: Float = -160         // dBFS
    @Published var normalizedLevel: Float = 0      // 0~1
    @Published var levelHistory: [Float] = []      // recent normalized levels for waveform

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private let historyMax = 80

    private func toggle() {
        if isRunning {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        let session = AVAudioSession.sharedInstance()
        do {
            // playAndRecord 允许同时播放视频和录音
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
        } catch {
            isRunning = false
            return
        }

        let url = URL(fileURLWithPath: "/dev/null")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatAppleLossless),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
        ]

        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else {
            isRunning = false
            return
        }

        recorder.isMeteringEnabled = true
        recorder.record()
        audioRecorder = recorder

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updateMeters()
        }
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        // Don't deactivate session — video player needs it
        currentLevel = -160
        peakLevel = -160
        normalizedLevel = 0
    }

    private func updateMeters() {
        guard let recorder = audioRecorder else { return }
        recorder.updateMeters()

        let avg = recorder.averagePower(forChannel: 0)  // dBFS, -160 ~ 0
        let peak = recorder.peakPower(forChannel: 0)

        // Normalize: -60dB ~ 0dB → 0 ~ 1
        let norm = max(0, min(1, (avg + 60) / 60))

        DispatchQueue.main.async {
            self.currentLevel = avg
            self.peakLevel = peak
            self.normalizedLevel = norm

            self.levelHistory.append(norm)
            if self.levelHistory.count > self.historyMax {
                self.levelHistory.removeFirst()
            }
        }
    }

    deinit {
        stopMonitoring()
    }
}
