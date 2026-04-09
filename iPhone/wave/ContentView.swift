//
//  ContentView.swift
//  wave
//
//  Created by C on 2026/4/8.
//

import SwiftUI
import AVKit

// MARK: - Video Library

struct VideoItem: Identifiable, Equatable {
    let id: String; let ext: String; let title: String
    var fileName: String { id }
}

private let videoLibrary: [VideoItem] = [
    VideoItem(id: "dream_pet",    ext: "mov", title: "猫猫安静"),
    VideoItem(id: "wave_video",   ext: "mp4", title: "猫猫向左走"),
    VideoItem(id: "drink_water",  ext: "mov", title: "猫猫喝水"),
    VideoItem(id: "fox_greeting", ext: "mov", title: "狐狸打招呼"),
    VideoItem(id: "elf_greeting", ext: "mov", title: "精灵打招呼"),
    VideoItem(id: "cat_greeting", ext: "mov", title: "猫猫打招呼"),
]

// MARK: - Content View

struct ContentView: View {

    @State private var showSensors = false
    @State private var showTapDetail = false
    @State private var showSoundDetail = false
    @State private var showPersonDetector = false
    @State private var showDrinkDetail = false
    @State private var reminderIndex = 0
    @State private var textVisible = true
    @State private var showControls = false
    @State private var hideTask: DispatchWorkItem?
    @State private var currentVideo: VideoItem = videoLibrary[0]
    @State private var showBLESheet = false
    @State private var showAnglePicker = false
    @State private var loopPlayer: AVQueuePlayer?
    @State private var playerLooper: AVPlayerLooper?
    @State private var showCameraPIP = true
    @State private var showOnboarding = false
    @State private var showCelebration = false
    @State private var lastDrinkCount = 0
    @AppStorage("debugMode") private var debugMode = false
    @ObservedObject private var servo = ServoBLEManager.shared
    @ObservedObject private var tap = TapDetector.shared
    @ObservedObject private var audio = AudioDetector.shared
    @ObservedObject private var camera = CameraManager.shared
    @ObservedObject private var drink = DrinkDetector.shared
    @ObservedObject private var faceAnalyzer = FaceAnalyzer.shared

    private let reminders = [
        "记得喝水哦，身体需要你的关爱 💧",
        "久坐不动？起来倒杯水吧 🥤",
        "每小时一杯水，健康常相随 🌊",
        "你今天喝了几杯水？别忘了补充水分 💦",
        "水是生命之源，现在就喝一口吧 🫧",
        "放下手机，喝口水，你值得被温柔对待 ☁️",
        "保持水分，保持好心情 🌈",
        "别等渴了才喝水，身体早就需要了 🍃",
        "一口温水，温暖整个下午 ☕",
        "喝水小提醒：你已经很久没喝水啦 ⏰",
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Video
                if let player = loopPlayer {
                    VideoPlayer(player: player)
                        .disabled(true)
                        .aspectRatio(1, contentMode: .fit)
                } else {
                    Color.black.aspectRatio(1, contentMode: .fit)
                        .overlay { ProgressView().tint(.gray) }
                }

                Spacer().frame(height: 6)

                // Water reminder
                Text(reminders[reminderIndex])
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .opacity(textVisible ? 1.0 : 0.2)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: textVisible)
                    .padding(.horizontal, 24)

                Spacer()

                // Bottom cards (debug mode only)
                if debugMode {
                    bottomCards
                }
            }

            // Camera PIP (debug mode only)
            if debugMode && showCameraPIP {
                cameraPIPWindow
            }

            // Floating menu button (on tap)
            if showControls {
                VStack {
                    HStack {
                        Spacer()
                        mainMenuButton
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 12)
                    Spacer()
                }
                .transition(.opacity)
            }

            // Reminder overlay
            ReminderOverlay(analyzer: faceAnalyzer)

            // Celebration overlay (top layer)
            CelebrationOverlay(isShowing: $showCelebration)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onTapGesture { toggleControls() }
        .onAppear {
            textVisible = false
            startReminderRotation()
            startDetectors()
        }
        .onChange(of: showOnboarding) { newVal in
            if newVal {
                stopDetectors()
            } else {
                startDetectors()
            }
        }
        .onChange(of: showTapDetail) { _ in toggleDetectorsForSheet() }
        .onChange(of: showSoundDetail) { _ in toggleDetectorsForSheet() }
        .onChange(of: showPersonDetector) { _ in toggleDetectorsForSheet() }
        .onChange(of: showDrinkDetail) { _ in toggleDetectorsForSheet() }
        .onChange(of: showSensors) { _ in toggleDetectorsForSheet() }
        .onChange(of: drink.drinkCount) { newCount in
            if newCount > lastDrinkCount {
                lastDrinkCount = newCount
                // Show celebration
                showCelebration = true
                // Play drink video after celebration ends
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    if let drinkVideo = videoLibrary.first(where: { $0.id == "drink_water" }) {
                        switchVideo(to: drinkVideo)
                    }
                }
                // Switch back to default (猫猫安静) after drink video plays ~5s
                DispatchQueue.main.asyncAfter(deadline: .now() + 7.5) {
                    let defaultVideo = videoLibrary[0] // 猫猫安静
                    switchVideo(to: defaultVideo)
                }
            }
        }
        .fullScreenCover(isPresented: $showTapDetail) {
            NavWrap { TapDetectionView() } onBack: { showTapDetail = false }
        }
        .fullScreenCover(isPresented: $showSoundDetail) {
            NavWrap { SoundDetectionView() } onBack: { showSoundDetail = false }
        }
        .fullScreenCover(isPresented: $showPersonDetector) {
            NavWrap { PersonDetectorView() } onBack: { showPersonDetector = false }
        }
        .fullScreenCover(isPresented: $showDrinkDetail) {
            NavWrap { DrinkDetectionView() } onBack: { showDrinkDetail = false }
        }
        .fullScreenCover(isPresented: $showSensors) {
            NavWrap { SensorPageView() } onBack: { showSensors = false }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
    }

    // MARK: - Camera PIP (floating, top-right)

    private let pipW: CGFloat = 80
    private let pipH: CGFloat = 50

    private var cameraPIPWindow: some View {
        VStack(spacing: 0) {
            // Title bar with tracking info
            HStack(spacing: 3) {
                // Face count
                Image(systemName: "face.smiling").font(.system(size: 7)).foregroundStyle(.yellow)
                Text("\(camera.faces.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.yellow)

                // Tracking direction arrow
                if camera.tracking.targetDetected {
                    Text(camera.tracking.inDeadZone ? "•" : (camera.tracking.error > 0 ? "→" : "←"))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(camera.tracking.inDeadZone ? .green : .orange)
                }

                Spacer()

                Button { showPersonDetector = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                Button { withAnimation(.easeOut(duration: 0.2)) { showCameraPIP = false } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.85))

            // Main content: big data on left, cameras on right
            HStack(spacing: 0) {
                // Left: big tracking data
                VStack(alignment: .leading, spacing: 2) {
                    if camera.tracking.targetDetected, let face = camera.faces.first {
                        Text(String(format: "%.2f", face.center.x))
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                        Text(String(format: "%+.2f", camera.tracking.error))
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(camera.tracking.inDeadZone ? .green : .orange)
                        Text(String(format: "%+d°", camera.tracking.servoAdjustment))
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(.yellow)
                    } else {
                        Text("--")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(.gray)
                        Text("无人脸")
                            .font(.system(size: 10))
                            .foregroundStyle(.gray)
                    }
                }
                .frame(width: 80)
                .padding(.leading, 6)

                // Right: two camera feeds stacked
                VStack(spacing: 1) {
                    pipCameraFeed(image: camera.originalImage, label: "原始")
                    pipCameraFeed(image: camera.compressedImage, label: "压缩")
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, 8)
        .padding(.top, UIScreen.main.bounds.width - 90)
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }

    private func pipCameraFeed(image: CGImage?, label: String) -> some View {
        ZStack {
            if let img = image {
                Image(decorative: img, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: pipW, height: pipH)
                    .clipped()

                // Detection overlay
                GeometryReader { _ in
                    ForEach(camera.targets) { t in
                        let c = t.source == .body ? Color.red : Color.yellow
                        // Bounding box
                        Rectangle()
                            .stroke(c.opacity(0.8), lineWidth: 1)
                            .frame(width: t.boundingBox.width * pipW,
                                   height: t.boundingBox.height * pipH)
                            .position(x: t.boundingBox.midX * pipW,
                                      y: t.boundingBox.midY * pipH)
                        // Center dot
                        Circle().fill(c).frame(width: 5, height: 5)
                            .position(x: t.center.x * pipW, y: t.center.y * pipH)
                        // Joints
                        ForEach(0..<t.joints.count, id: \.self) { i in
                            Circle().fill(Color.red.opacity(0.6)).frame(width: 2, height: 2)
                                .position(x: t.joints[i].x * pipW, y: t.joints[i].y * pipH)
                        }
                    }

                    // Center line (target)
                    Path { p in
                        p.move(to: CGPoint(x: pipW / 2, y: 0))
                        p.addLine(to: CGPoint(x: pipW / 2, y: pipH))
                    }
                    .stroke(Color.green.opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                }
                .frame(width: pipW, height: pipH)
            } else {
                Color.black.frame(width: pipW, height: pipH)
                    .overlay {
                        Image(systemName: "camera").font(.system(size: 10)).foregroundStyle(.gray)
                    }
            }

            // Label
            VStack {
                Spacer()
                HStack {
                    Text(label)
                        .font(.system(size: 5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 2).padding(.vertical, 1)
                        .background(Color.black.opacity(0.5)).cornerRadius(2)
                    Spacer()
                }.padding(2)
            }.frame(width: pipW, height: pipH)
        }
    }

    // MARK: - Bottom 3 cards

    private var bottomCards: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                servoCard
                tapCard
            }
            HStack(spacing: 4) {
                soundCard
                drinkCard
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    // MARK: - Card: Servo (tappable)

    private var servoCard: some View {
        Button { showAnglePicker = true } label: {
            VStack(spacing: 2) {
                HStack {
                    Image(systemName: "gyroscope").font(.system(size: 8)).foregroundStyle(.cyan)
                    Spacer()
                    HStack(spacing: 2) {
                        Circle().fill(servo.isConnected ? Color.green : Color.red).frame(width: 5, height: 5)
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 7)).foregroundStyle(.white.opacity(0.4))
                    }
                }
                Text("\(servo.currentAngle)°")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
                HStack(spacing: 3) {
                    Text(servo.direction.arrow)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(directionColor)
                    Text(String(format: "%.0f°/s", servo.speed))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(.gray)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 7)).foregroundStyle(.gray)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .sheet(isPresented: $showAnglePicker) {
            ServoControlSheet(servo: servo, showBLE: $showBLESheet)
        }
        .sheet(isPresented: $showBLESheet) { BLEConnectionSheet(ble: servo) }
    }

    // MARK: - Card: Tap

    private var tapCard: some View {
        VStack(spacing: 2) {
            HStack {
                Circle().fill(tap.tapDetected ? Color.red : Color.green.opacity(0.5))
                    .frame(width: 5, height: 5)
                    .scaleEffect(tap.tapDetected ? 1.5 : 1.0)
                    .animation(.easeOut(duration: 0.2), value: tap.tapDetected)
                Spacer()
                Button { showTapDetail = true } label: {
                    Image(systemName: "chevron.right").font(.system(size: 6)).foregroundStyle(.gray)
                }
            }
            Image(systemName: "hand.tap.fill").font(.system(size: 10)).foregroundStyle(.red.opacity(0.6))
            Text(String(format: "%.2f", tap.lastForce))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)
            Text("g").font(.system(size: 6)).foregroundStyle(.gray)
            GeometryReader { geo in
                let ratio = min(tap.currentMagnitude / max(tap.threshold * 3, 0.01), 1.0)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(tap.currentMagnitude >= tap.threshold ? Color.red : Color.green)
                        .frame(width: geo.size.width * ratio)
                }
            }.frame(height: 3)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Card: Sound

    private var soundCard: some View {
        VStack(spacing: 2) {
            HStack {
                Image(systemName: "mic.fill").font(.system(size: 8)).foregroundStyle(.orange)
                Spacer()
                Button { showSoundDetail = true } label: {
                    Image(systemName: "chevron.right").font(.system(size: 6)).foregroundStyle(.gray)
                }
            }
            Text(String(format: "%.0f", audio.currentLevel))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(soundLevelColor)
            Text("dB").font(.system(size: 6)).foregroundStyle(.gray)
            HStack(alignment: .bottom, spacing: 0.8) {
                ForEach(0..<audio.levelHistory.suffix(20).count, id: \.self) { i in
                    let level = Array(audio.levelHistory.suffix(20))[i]
                    RoundedRectangle(cornerRadius: 0.5).fill(miniBarColor(level))
                        .frame(height: max(1, CGFloat(level) * 12))
                }
            }.frame(height: 12).frame(maxWidth: .infinity)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Card: Drink

    private var drinkCard: some View {
        Button { showDrinkDetail = true } label: {
        VStack(spacing: 2) {
            HStack {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 8)).foregroundStyle(.cyan)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 6)).foregroundStyle(.gray)
            }
            Text("\(drink.todayCount)")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
            Text("次").font(.system(size: 7)).foregroundStyle(.gray)
            // Phase indicator
            Text(drink.phase.rawValue)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(drinkPhaseColor)
            // Tilt mini bar
            GeometryReader { geo in
                let ratio = min(drink.tiltAngle / 90.0, 1.0)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(drink.tiltAngle > drink.tiltThreshold ? Color.orange : Color.cyan)
                        .frame(width: geo.size.width * ratio)
                }
            }.frame(height: 3)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var drinkPhaseColor: Color {
        switch drink.phase {
        case .idle: return .gray
        case .tilting: return .blue
        case .drinking: return .orange
        case .cooldown: return .green
        }
    }

    // MARK: - Detector lifecycle

    private var anySheetOpen: Bool {
        showTapDetail || showSoundDetail || showPersonDetector || showDrinkDetail || showSensors || showOnboarding
    }

    private func startDetectors() {
        guard !anySheetOpen else { return }
        if !tap.isRunning { tap.isRunning = true }
        if !audio.isRunning { audio.isRunning = true }
        if !drink.isRunning { drink.isRunning = true }
        camera.start()
        faceAnalyzer.startAutoAnalysis()
        faceAnalyzer.startReminder()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { setupVideoPlayer() }
    }

    private func stopDetectors() {
        tap.isRunning = false
        audio.isRunning = false
        drink.isRunning = false
        camera.stop()
        faceAnalyzer.stopAutoAnalysis()
        faceAnalyzer.stopReminder()
        loopPlayer?.pause()
    }

    private func toggleDetectorsForSheet() {
        if anySheetOpen {
            // Don't stop everything for detail sheets — only stop conflicting ones
            // Camera and audio may be needed in some detail views
        } else {
            startDetectors()
        }
    }

    private func setAnalysisInterval(_ seconds: TimeInterval) {
        faceAnalyzer.analysisInterval = seconds
        faceAnalyzer.restartTimers()
    }

    private func setReminderInterval(_ seconds: TimeInterval) {
        faceAnalyzer.reminderInterval = seconds
        faceAnalyzer.restartTimers()
    }

    private func formatInterval(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))秒" }
        return "\(Int(seconds / 60))分钟"
    }

    // MARK: - Helpers

    private func adjustAngle(by d: Int) { servo.sendServoCommand(angle: max(0, min(180, servo.currentAngle + d))) }
    private var directionColor: Color {
        switch servo.direction { case .left: return .blue; case .right: return .green; case .still: return .gray }
    }
    private var soundLevelColor: Color {
        if audio.normalizedLevel < 0.3 { return .green }; if audio.normalizedLevel < 0.7 { return .yellow }; return .red
    }
    private func miniBarColor(_ l: Float) -> Color {
        if l < 0.3 { return .green }; if l < 0.7 { return .yellow }; return .red
    }

    // MARK: - Video

    private func setupVideoPlayer() {
        guard let url = Bundle.main.url(forResource: currentVideo.fileName, withExtension: currentVideo.ext) else { return }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        let looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = false
        player.play()
        self.loopPlayer = player
        self.playerLooper = looper
    }

    // MARK: - Main Menu (single entry point)

    private var mainMenuButton: some View {
        Menu {
            // Video switch
            Menu {
                ForEach(videoLibrary) { v in
                    Button { if currentVideo != v { switchVideo(to: v) } } label: {
                        HStack { Text(v.title); if currentVideo == v { Image(systemName: "checkmark") } }
                    }
                }
            } label: {
                Label("切换视频", systemImage: "film.stack")
            }

            // Onboarding
            Button { showOnboarding = true } label: {
                Label("初始化向导", systemImage: "sparkles")
            }

            // Raw sensors
            Button { showSensors = true } label: {
                Label("原始传感器", systemImage: "sensor.fill")
            }

            Divider()

            // Debug mode toggle
            Button {
                withAnimation { debugMode.toggle() }
            } label: {
                Label(debugMode ? "关闭调试模式" : "开启调试模式",
                      systemImage: debugMode ? "ladybug.fill" : "ladybug")
            }

            if debugMode {
                Divider()

                // Camera PIP
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showCameraPIP.toggle() }
                } label: {
                    Label(showCameraPIP ? "隐藏摄像头" : "显示摄像头",
                          systemImage: showCameraPIP ? "eye.slash" : "eye")
                }

                // Analysis interval
                Menu {
                    Button { setAnalysisInterval(10) } label: { Text("10 秒（调试）") }
                    Button { setAnalysisInterval(30) } label: { Text("30 秒") }
                    Button { setAnalysisInterval(60) } label: { Text("1 分钟（默认）") }
                    Button { setAnalysisInterval(300) } label: { Text("5 分钟") }
                } label: {
                    Label("分析间隔: \(Int(faceAnalyzer.analysisInterval))秒", systemImage: "clock")
                }

                // Reminder interval
                Menu {
                    Button { setReminderInterval(30) } label: { Text("30 秒（调试）") }
                    Button { setReminderInterval(60) } label: { Text("1 分钟") }
                    Button { setReminderInterval(300) } label: { Text("5 分钟") }
                    Button { setReminderInterval(600) } label: { Text("10 分钟") }
                    Button { setReminderInterval(1200) } label: { Text("20 分钟（默认）") }
                    Button { setReminderInterval(1800) } label: { Text("30 分钟") }
                } label: {
                    Label("提醒间隔: \(formatInterval(faceAnalyzer.reminderInterval))", systemImage: "bell")
                }

                // Show snapshot toggle
                Button {
                    faceAnalyzer.showSnapshot.toggle()
                } label: {
                    Label(faceAnalyzer.showSnapshot ? "隐藏提醒照片" : "显示提醒照片",
                          systemImage: faceAnalyzer.showSnapshot ? "person.crop.rectangle.badge.minus" : "person.crop.rectangle.badge.plus")
                }

                // Test reminder now
                Button {
                    faceAnalyzer.analyzeCurrentFace()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        faceAnalyzer.showReminder = true
                        faceAnalyzer.currentReminder = ReminderRecord(
                            timestamp: Date(),
                            message: "测试提醒：记得喝水哦",
                            energyScore: faceAnalyzer.records.first?.energyScore ?? 5,
                            tags: faceAnalyzer.records.first?.tags ?? ["测试"],
                            snapshot: CameraManager.shared.originalImage
                        )
                    }
                } label: {
                    Label("立即测试提醒", systemImage: "play.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.15), in: Circle())
        }
    }

    private func switchVideo(to video: VideoItem) {
        guard let url = Bundle.main.url(forResource: video.fileName, withExtension: video.ext) else { return }
        // Stop old player completely
        loopPlayer?.pause()
        loopPlayer?.replaceCurrentItem(with: nil)
        playerLooper?.disableLooping()
        playerLooper = nil
        loopPlayer = nil

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        let looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = false
        player.play()
        self.loopPlayer = player
        self.playerLooper = looper
        self.currentVideo = video
    }

    private func toggleControls() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { showControls = true }
        let task = DispatchWorkItem { withAnimation(.easeIn(duration: 0.3)) { showControls = false } }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
    }

    // videoSwitchButton and sensorButton merged into mainMenuButton

    private func startReminderRotation() {
        Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) { reminderIndex = (reminderIndex + 1) % reminders.count }
        }
    }
}

// MARK: - NavWrap

struct NavWrap<Content: View>: View {
    @ViewBuilder let content: () -> Content
    let onBack: () -> Void
    var body: some View {
        NavigationStack {
            content()
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("返回") { onBack() } } }
        }.preferredColorScheme(.dark)
    }
}

// MARK: - Sensor Page

struct SensorPageView: View {
    @StateObject private var motion = MotionManager()
    var body: some View {
        List {
            SensorSection(title: "加速度计", subtitle: "线性加速度 (g)", icon: "move.3d",
                          isAvailable: motion.isAccelerometerAvailable, isEnabled: $motion.accelerometerEnabled) {
                XYZRow(label: "加速度", data: motion.acceleration, unit: "g")
            }
            SensorSection(title: "陀螺仪", subtitle: "角速度 (rad/s)", icon: "gyroscope",
                          isAvailable: motion.isGyroAvailable, isEnabled: $motion.gyroEnabled) {
                XYZRow(label: "旋转速率", data: motion.rotationRate, unit: "rad/s")
            }
            SensorSection(title: "磁力计", subtitle: "磁场强度 (\u{00B5}T)", icon: "location.north.fill",
                          isAvailable: motion.isMagnetometerAvailable, isEnabled: $motion.magnetometerEnabled) {
                XYZRow(label: "磁场", data: motion.magneticField, unit: "\u{00B5}T")
            }
            SensorSection(title: "设备运动（融合）", subtitle: "加速度计 + 陀螺仪融合", icon: "sensor.fill",
                          isAvailable: motion.isDeviceMotionAvailable, isEnabled: $motion.deviceMotionEnabled) {
                AttitudeRow(attitude: motion.attitude)
                XYZRow(label: "重力", data: motion.gravity, unit: "g")
                XYZRow(label: "用户加速度", data: motion.userAcceleration, unit: "g")
            }
        }.navigationTitle("原始传感器").listStyle(.insetGrouped)
    }
}

// MARK: - Angle Picker

struct ServoControlSheet: View {
    @ObservedObject var servo: ServoBLEManager
    @Binding var showBLE: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Connection status
                HStack(spacing: 6) {
                    Circle().fill(servo.isConnected ? Color.green : Color.red).frame(width: 8, height: 8)
                    Text(servo.statusText).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { showBLE = true; dismiss() } label: {
                        Label("蓝牙", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption).foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal, 24)

                // Big angle display
                ZStack {
                    Circle().stroke(Color(.systemGray4), lineWidth: 10).frame(width: 160, height: 160)
                    Circle().trim(from: 0, to: CGFloat(servo.currentAngle) / 360)
                        .stroke(AngularGradient(colors: [.blue, .cyan, .blue], center: .center),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 160, height: 160).rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(servo.currentAngle)°")
                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                        HStack(spacing: 4) {
                            Text(servo.direction.arrow)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(servo.direction == .left ? .blue : servo.direction == .right ? .green : .gray)
                            Text(servo.direction.rawValue)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .animation(.easeOut(duration: 0.2), value: servo.currentAngle)

                // Left / Right control
                HStack(spacing: 16) {
                    // Left turn
                    Button { sendAngle(max(0, servo.currentAngle - 5)) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 20))
                            Text("左转 -5°").font(.system(size: 10))
                        }
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Right turn
                    Button { sendAngle(min(180, servo.currentAngle + 5)) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 20))
                            Text("右转 +5°").font(.system(size: 10))
                        }
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 24)

                // Slider
                VStack(spacing: 4) {
                    Slider(value: Binding(
                        get: { Double(servo.currentAngle) },
                        set: { sendAngle(Int($0)) }
                    ), in: 0...180, step: 1)
                    .tint(.cyan)
                    HStack { Text("0°"); Spacer(); Text("90°"); Spacer(); Text("180°") }
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)

                // Preset buttons — tap directly sends
                HStack(spacing: 8) {
                    ForEach([0, 45, 90, 135, 180], id: \.self) { p in
                        Button { sendAngle(p) } label: {
                            Text("\(p)°")
                                .font(.system(.callout, design: .monospaced)).fontWeight(.medium)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(servo.currentAngle == p ? Color.cyan : Color(.systemGray5),
                                            in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(servo.currentAngle == p ? .black : .primary)
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.top, 12)
            .navigationTitle("舵机控制").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } } }
        }
    }

    private func sendAngle(_ angle: Int) {
        servo.sendServoCommand(angle: angle)
    }
}

// MARK: - BLE Sheet

struct BLEConnectionSheet: View {
    @ObservedObject var ble: ServoBLEManager
    @Environment(\.dismiss) private var dismiss
    private let df: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MM/dd HH:mm"; return f }()
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack { Circle().fill(ble.isConnected ? .green : .red).frame(width: 10, height: 10); Text(ble.statusText).foregroundStyle(.secondary); Spacer() }
                } header: { Text("连接状态") }
                if ble.isConnected {
                    Section { Button(role: .destructive) { ble.disconnect() } label: { Label("断开连接", systemImage: "xmark.circle.fill") } }
                } else {
                    Section {
                        Button { ble.startScan() } label: {
                            HStack { if ble.isScanning { ProgressView().padding(.trailing, 4) }; Text(ble.isScanning ? "扫描中..." : "扫描蓝牙设备") }
                        }.disabled(ble.isScanning)
                    }
                    if !ble.discoveredDevices.isEmpty {
                        Section {
                            ForEach(ble.discoveredDevices) { d in
                                Button { ble.connect(to: d) } label: {
                                    HStack { VStack(alignment: .leading, spacing: 2) { Text(d.name).font(.headline); Text("\(d.rssi) dBm").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("连接").font(.caption).foregroundStyle(.blue) }
                                }
                            }
                        } header: { Text("发现的设备") }
                    }
                }
                if !ble.savedDevices.isEmpty {
                    Section {
                        ForEach(ble.savedDevices) { s in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) { Text(s.name).font(.subheadline).fontWeight(.medium); Text("\(df.string(from: s.lastConnected))").font(.caption2).foregroundStyle(.secondary) }; Spacer()
                                if !ble.isConnected { Button("重连") { ble.reconnectSaved(s) }.font(.caption).buttonStyle(.bordered).tint(.blue) }
                            }
                        }.onDelete { idx in for i in idx { ble.removeSavedDevice(ble.savedDevices[i]) } }
                    } header: { Text("连接历史") } footer: { Text("启动时自动连接") }
                }
            }.navigationTitle("蓝牙管理").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

#Preview { ContentView() }
