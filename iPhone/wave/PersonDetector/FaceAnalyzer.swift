//
//  FaceAnalyzer.swift
//  wave
//

import Foundation
import Vision
import Combine
import CoreGraphics

// MARK: - 分析记录

struct FaceAnalysisRecord: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let energyScore: Int
    let tags: [String]
    let details: String
    let eyeOpenLeft: Double
    let eyeOpenRight: Double
    let smileScore: Double
    let faceYaw: Double
    let facePitch: Double
    let snapshotData: Data?  // JPEG snapshot of face

    var snapshotImage: CGImage? {
        guard let data = snapshotData,
              let provider = CGDataProvider(data: data as CFData),
              let img = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return img
    }

    init(timestamp: Date, eyeOpenLeft: Double, eyeOpenRight: Double,
         smileScore: Double, faceYaw: Double, facePitch: Double,
         snapshotData: Data? = nil) {
        self.id = UUID().uuidString
        self.timestamp = timestamp
        self.eyeOpenLeft = eyeOpenLeft
        self.eyeOpenRight = eyeOpenRight
        self.smileScore = smileScore
        self.faceYaw = faceYaw
        self.facePitch = facePitch
        self.snapshotData = snapshotData

        let avgEyeOpen = (eyeOpenLeft + eyeOpenRight) / 2.0
        var score = 5
        var tagList: [String] = []
        var desc = ""

        if avgEyeOpen > 0.7 {
            score += 2; tagList.append("精神饱满"); desc += "眼睛睁大，精神状态良好。"
        } else if avgEyeOpen > 0.4 {
            tagList.append("状态一般"); desc += "眼睛正常开合。"
        } else if avgEyeOpen > 0.2 {
            score -= 2; tagList.append("有些疲惫"); desc += "眼睛半闭，可能比较困倦。"
        } else {
            score -= 3; tagList.append("非常疲惫"); desc += "眼睛几乎闭合，建议休息。"
        }

        if smileScore > 0.6 {
            score += 2; tagList.append("心情愉快"); desc += "面带笑容，心情不错。"
        } else if smileScore > 0.3 {
            score += 1; tagList.append("心情平静"); desc += "表情平和。"
        } else {
            tagList.append("表情严肃"); desc += "没有笑容。"
        }

        if facePitch < -20 {
            tagList.append("低头"); desc += "头部低垂，可能在看手机或打瞌睡。"; score -= 1
        } else if facePitch > 20 {
            tagList.append("仰头")
        }
        if abs(faceYaw) > 25 { tagList.append("侧脸") }

        self.energyScore = max(1, min(10, score))
        self.tags = tagList
        self.details = desc
    }
}

// MARK: - 定时提醒记录

struct ReminderRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let energyScore: Int
    let tags: [String]
    let snapshot: CGImage?
}

// MARK: - 分析器

final class FaceAnalyzer: ObservableObject {
    static let shared = FaceAnalyzer()

    @Published var records: [FaceAnalysisRecord] = []
    @Published var isAnalyzing = false
    @Published var lastAnalysisTime: Date?

    // 可调参数
    @Published var analysisInterval: TimeInterval = 60          // 精神分析间隔（秒）
    @Published var reminderInterval: TimeInterval = 20 * 60     // 喝水提醒间隔（秒，默认20分钟）
    @Published var showSnapshot = true                          // 提醒时是否显示照片

    // 提醒状态
    @Published var showReminder = false
    @Published var currentReminder: ReminderRecord?
    @Published var reminderVideoName = "cat_thirsty"

    private var analysisTimer: Timer?
    private var reminderTimer: Timer?

    init() { loadRecords() }

    func startAutoAnalysis() {
        stopAutoAnalysis()
        analysisTimer = Timer.scheduledTimer(withTimeInterval: analysisInterval, repeats: true) { [weak self] _ in
            self?.analyzeCurrentFace()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.analyzeCurrentFace()
        }
    }

    func startReminder() {
        stopReminder()
        reminderTimer = Timer.scheduledTimer(withTimeInterval: reminderInterval, repeats: true) { [weak self] _ in
            self?.triggerReminder()
        }
    }

    func stopAutoAnalysis() {
        analysisTimer?.invalidate()
        analysisTimer = nil
    }

    func stopReminder() {
        reminderTimer?.invalidate()
        reminderTimer = nil
    }

    func restartTimers() {
        startAutoAnalysis()
        startReminder()
    }

    // MARK: - 分析

    func analyzeCurrentFace() {
        let camera = CameraManager.shared
        guard camera.tracking.targetDetected,
              let cgImage = camera.originalImage else { return }

        isAnalyzing = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.performAnalysis(cgImage: cgImage)
            DispatchQueue.main.async {
                guard let self, let record = result else {
                    self?.isAnalyzing = false
                    return
                }
                self.records.insert(record, at: 0)
                if self.records.count > 100 { self.records.removeLast() }
                self.lastAnalysisTime = Date()
                self.isAnalyzing = false
                self.saveRecords()
            }
        }
    }

    // MARK: - 定时提醒

    private func triggerReminder() {
        let camera = CameraManager.shared

        // 截取当前照片
        let snapshot = camera.originalImage

        // 获取最近的分析记录
        let recentScore = records.first?.energyScore ?? 5
        let recentTags = records.first?.tags ?? ["状态未知"]

        var message: String
        if recentScore <= 4 {
            message = "你看起来有些疲惫了，休息一下，喝口水吧"
        } else if recentScore <= 6 {
            message = "已经过了一段时间了，记得补充水分哦"
        } else {
            message = "状态不错！喝口水保持好状态吧"
        }

        let reminder = ReminderRecord(
            timestamp: Date(),
            message: message,
            energyScore: recentScore,
            tags: recentTags,
            snapshot: snapshot
        )

        DispatchQueue.main.async {
            self.currentReminder = reminder
            self.showReminder = true
        }
    }

    func dismissReminder() {
        showReminder = false
        currentReminder = nil
    }

    // MARK: - Vision 分析

    private func performAnalysis(cgImage: CGImage) -> FaceAnalysisRecord? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        try? handler.perform([request])

        guard let face = request.results?.first else { return nil }

        let leftEyeOpen = estimateEyeOpenness(face: face, isLeft: true)
        let rightEyeOpen = estimateEyeOpenness(face: face, isLeft: false)
        let smile = estimateSmile(face: face)
        let yaw = (face.yaw?.doubleValue ?? 0) * 180 / .pi
        let pitch = (face.pitch?.doubleValue ?? 0) * 180 / .pi

        // 生成快照 JPEG data
        var snapshotData: Data? = nil
        if showSnapshot {
            let bitmapCtx = CGContext(data: nil, width: 120, height: 160,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            if let ctx = bitmapCtx {
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: 120, height: 160))
                if let thumb = ctx.makeImage(),
                   let cfData = CFDataCreateMutable(nil, 0),
                   let dest = CGImageDestinationCreateWithData(cfData, "public.jpeg" as CFString, 1, nil) {
                    CGImageDestinationAddImage(dest, thumb, [kCGImageDestinationLossyCompressionQuality: 0.5] as CFDictionary)
                    CGImageDestinationFinalize(dest)
                    snapshotData = cfData as Data
                }
            }
        }

        return FaceAnalysisRecord(
            timestamp: Date(),
            eyeOpenLeft: leftEyeOpen, eyeOpenRight: rightEyeOpen,
            smileScore: smile, faceYaw: yaw, facePitch: pitch,
            snapshotData: snapshotData
        )
    }

    private func estimateEyeOpenness(face: VNFaceObservation, isLeft: Bool) -> Double {
        guard let landmarks = face.landmarks else { return 0.5 }
        let eye = isLeft ? landmarks.leftEye : landmarks.rightEye
        guard let pts = eye?.normalizedPoints, pts.count >= 4 else { return 0.5 }
        let ys = pts.map(\.y); let xs = pts.map(\.x)
        let h = (ys.max() ?? 0) - (ys.min() ?? 0)
        let w = (xs.max() ?? 0) - (xs.min() ?? 0)
        guard w > 0 else { return 0.5 }
        return min(1.0, max(0, (h / w - 0.08) / 0.35))
    }

    private func estimateSmile(face: VNFaceObservation) -> Double {
        guard let landmarks = face.landmarks,
              let outerLips = landmarks.outerLips?.normalizedPoints,
              outerLips.count >= 6 else { return 0.3 }
        let xs = outerLips.map(\.x)
        let mouthWidth = (xs.max() ?? 0) - (xs.min() ?? 0)
        let left = outerLips.first ?? .zero
        let right = outerLips.count > 6 ? outerLips[6] : outerLips.last ?? .zero
        let mid = outerLips.count > 3 ? outerLips[3] : outerLips.last ?? .zero
        let uplift = (left.y + right.y) / 2 - mid.y
        return min(1.0, max(0, mouthWidth * 2 + uplift * 5))
    }

    func clearRecords() { records = []; saveRecords() }

    private func saveRecords() {
        // Save without snapshot data to keep size small
        let lite = records.prefix(50).map { r in
            FaceAnalysisRecord(timestamp: r.timestamp,
                               eyeOpenLeft: r.eyeOpenLeft, eyeOpenRight: r.eyeOpenRight,
                               smileScore: r.smileScore, faceYaw: r.faceYaw, facePitch: r.facePitch,
                               snapshotData: nil)
        }
        if let data = try? JSONEncoder().encode(Array(lite)) {
            UserDefaults.standard.set(data, forKey: "faceAnalysisRecords")
        }
    }

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: "faceAnalysisRecords"),
              let saved = try? JSONDecoder().decode([FaceAnalysisRecord].self, from: data) else { return }
        records = saved
    }
}
