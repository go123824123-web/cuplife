import AVFoundation
import CoreImage
import Vision
import SwiftUI
import Combine

// MARK: - 检测目标

enum DetectionSource: String {
    case face = "人脸"
    case body = "人体"
    case both = "人脸+人体"
}

struct DetectedTarget: Identifiable {
    let id = UUID()
    let center: CGPoint           // 归一化坐标，原点左上
    let boundingBox: CGRect       // 归一化坐标，原点左上
    let relativeSize: CGFloat     // 宽度占画面比例
    let source: DetectionSource
    let joints: [CGPoint]         // 身体关节点（仅 body 有）
}

// MARK: - 追踪状态

struct TrackingState {
    var error: CGFloat = 0
    var servoAdjustment: Int = 0
    var inDeadZone: Bool = true
    var targetDetected: Bool = false
    var lostFrames: Int = 0
    var source: DetectionSource = .face
}

// MARK: - 相机 + 人脸/人体检测 + PID 追踪

final class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()

    @Published var originalImage: CGImage?
    @Published var compressedImage: CGImage?
    @Published var targets: [DetectedTarget] = []
    @Published var tracking = TrackingState()

    // PID 参数
    @Published var deadZone: CGFloat = 0.08
    @Published var pGain: CGFloat = 15.0
    @Published var maxStep: Int = 10
    @Published var autoTrackEnabled = true
    @Published var lostTimeout: Int = 15

    // 兼容旧接口
    var faces: [DetectedTarget] { targets }
    var persons: [DetectedTarget] { targets }

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.queue", qos: .userInteractive)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let compressedShortSide: CGFloat = 160
    private var isProcessing = false
    private var lastCommandTime: Date = .distantPast

    // MARK: - 生命周期

    func start() {
        guard !session.isRunning else { return }
        configureSession()
        queue.async { [weak self] in self?.session.startRunning() }
    }

    func stop() { session.stopRunning() }

    // MARK: - 配置

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front
        ), let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration(); return
        }

        if session.canAddInput(input) { session.addInput(input) }
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        if let connection = videoOutput.connection(with: .video) {
            connection.isVideoMirrored = true
            connection.videoOrientation = .portrait
        }
        session.commitConfiguration()
    }

    // MARK: - 检测（人脸 + 人体融合）

    private func detect(in pixelBuffer: CVPixelBuffer) -> [DetectedTarget] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        let faceReq = VNDetectFaceRectanglesRequest()
        let bodyReq = VNDetectHumanBodyPoseRequest()
        try? handler.perform([faceReq, bodyReq])

        var results: [DetectedTarget] = []
        var usedFaceRegions: [CGRect] = []

        // 1. 处理人脸
        if let faceObs = faceReq.results {
            for face in faceObs {
                let fb = face.boundingBox
                let center = CGPoint(x: fb.midX, y: 1 - fb.midY)
                let bbox = CGRect(x: fb.origin.x, y: 1 - fb.origin.y - fb.height,
                                  width: fb.width, height: fb.height)
                usedFaceRegions.append(fb)

                // 检查是否有对应的 body pose
                var matchedJoints: [CGPoint] = []
                if let bodyObs = bodyReq.results {
                    for body in bodyObs {
                        if let nose = try? body.recognizedPoint(.nose), nose.confidence > 0.1 {
                            // 鼻子在人脸框内 → 匹配
                            if fb.contains(nose.location) {
                                let allPts = (try? body.recognizedPoints(.all)) ?? [:]
                                matchedJoints = allPts.values
                                    .filter { $0.confidence > 0.1 }
                                    .map { CGPoint(x: $0.location.x, y: 1 - $0.location.y) }
                                break
                            }
                        }
                    }
                }

                let source: DetectionSource = matchedJoints.isEmpty ? .face : .both
                results.append(DetectedTarget(center: center, boundingBox: bbox,
                                              relativeSize: fb.width, source: source,
                                              joints: matchedJoints))
            }
        }

        // 2. 处理没有匹配到人脸的 body pose（远距离/侧面）
        if let bodyObs = bodyReq.results {
            for body in bodyObs {
                let allPts = (try? body.recognizedPoints(.all)) ?? [:]
                let validPts = allPts.values.filter { $0.confidence > 0.1 }
                guard !validPts.isEmpty else { continue }

                // 检查这个 body 是否已被人脸覆盖
                let hasFaceMatch: Bool = {
                    if let nose = try? body.recognizedPoint(.nose), nose.confidence > 0.1 {
                        return usedFaceRegions.contains { $0.contains(nose.location) }
                    }
                    // 没有鼻子，用肩膀中点判断
                    let bodyXs = validPts.map(\.location.x)
                    let bodyCenter = CGPoint(
                        x: (bodyXs.min()! + bodyXs.max()!) / 2,
                        y: validPts.map(\.location.y).reduce(0, +) / CGFloat(validPts.count)
                    )
                    return usedFaceRegions.contains { expanded($0, by: 0.1).contains(bodyCenter) }
                }()

                if hasFaceMatch { continue }

                // Body-only target
                let xs = validPts.map(\.location.x)
                let ys = validPts.map(\.location.y)
                let minX = xs.min()!, maxX = xs.max()!
                let minY = ys.min()!, maxY = ys.max()!

                let center = CGPoint(x: (minX + maxX) / 2, y: 1 - (minY + maxY) / 2)
                let bbox = CGRect(x: minX, y: 1 - maxY, width: maxX - minX, height: maxY - minY)
                let joints = validPts.map { CGPoint(x: $0.location.x, y: 1 - $0.location.y) }

                results.append(DetectedTarget(center: center, boundingBox: bbox,
                                              relativeSize: maxX - minX, source: .body,
                                              joints: joints))
            }
        }

        return results
    }

    private func expanded(_ rect: CGRect, by margin: CGFloat) -> CGRect {
        rect.insetBy(dx: -margin, dy: -margin)
    }

    // MARK: - PID 追踪

    private func computeTracking(targets: [DetectedTarget]) -> TrackingState {
        // 优先选人脸目标，没有则选人体
        let target = targets.first(where: { $0.source == .face || $0.source == .both })
                     ?? targets.first

        guard let t = target else {
            let lost = tracking.lostFrames + 1
            return TrackingState(error: 0, servoAdjustment: 0, inDeadZone: true,
                                 targetDetected: false, lostFrames: lost, source: .face)
        }

        let error = t.center.x - 0.5

        if abs(error) < deadZone {
            return TrackingState(error: error, servoAdjustment: 0, inDeadZone: true,
                                 targetDetected: true, lostFrames: 0, source: t.source)
        }

        let raw = error * pGain
        let clamped = max(-CGFloat(maxStep), min(CGFloat(maxStep), raw))
        return TrackingState(error: error, servoAdjustment: Int(clamped), inDeadZone: false,
                             targetDetected: true, lostFrames: 0, source: t.source)
    }

    private func autoSendServoCommand(state: TrackingState) {
        guard autoTrackEnabled, state.targetDetected, !state.inDeadZone, state.servoAdjustment != 0 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCommandTime) >= 0.1 else { return }
        lastCommandTime = now
        let servo = ServoBLEManager.shared
        servo.sendServoCommand(angle: max(0, min(180, servo.currentAngle + state.servoAdjustment)))
    }

    // MARK: - 压缩

    private func compressImage(_ ciImage: CIImage) -> CGImage? {
        let scale = compressedShortSide / min(ciImage.extent.width, ciImage.extent.height)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = scaled.applyingGaussianBlur(sigma: 1.0)
        return ciContext.createCGImage(blurred, from: scaled.extent)
    }
}

// MARK: - 视频帧回调

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !isProcessing, let buf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessing = true

        let ci = CIImage(cvPixelBuffer: buf)
        let original = ciContext.createCGImage(ci, from: ci.extent)
        let compressed = compressImage(ci)
        let detected = detect(in: buf)
        let trackState = computeTracking(targets: detected)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.originalImage = original
            self.compressedImage = compressed
            self.targets = detected
            self.tracking = trackState
            self.autoSendServoCommand(state: trackState)
            self.isProcessing = false
        }
    }
}
