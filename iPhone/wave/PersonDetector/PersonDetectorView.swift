import SwiftUI

struct PersonDetectorView: View {
    @ObservedObject private var camera = CameraManager.shared
    @ObservedObject private var analyzer = FaceAnalyzer.shared
    @State private var showInfo = false
    @State private var selectedRecord: FaceAnalysisRecord?

    var body: some View {
        VStack(spacing: 0) {
            // Camera feeds
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height
                let layout = isLandscape
                    ? AnyLayout(HStackLayout(spacing: 2))
                    : AnyLayout(VStackLayout(spacing: 2))

                layout {
                    FaceCameraPanel(title: "原始画面", image: camera.originalImage, faces: camera.targets, tracking: camera.tracking)
                    FaceCameraPanel(title: "压缩画面", image: camera.compressedImage, faces: camera.targets, tracking: camera.tracking)
                }
                .background(Color.black)
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.45)

            // Tracking + Analysis info
            ScrollView {
                VStack(spacing: 8) {
                    trackingInfoBar
                    pidControlsBar
                    analysisSection
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(Color.black)
        }
        .ignoresSafeArea()
        .onAppear {
            camera.start()
            analyzer.startAutoAnalysis()
        }
        .onDisappear {
            analyzer.stopAutoAnalysis()
        }
        .statusBarHidden()
        .navigationTitle("人脸追踪")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showInfo = true } label: { Image(systemName: "info.circle") }
            }
        }
        .sheet(isPresented: $showInfo) { FaceTrackingInfoSheet() }
        .sheet(item: $selectedRecord) { record in
            RecordDetailSheet(record: record)
        }
    }

    // MARK: - Analysis Section

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 11)).foregroundStyle(.purple)
                Text("精神状态分析")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                if analyzer.isAnalyzing {
                    ProgressView().scaleEffect(0.6)
                }
                Text("每分钟自动分析")
                    .font(.system(size: 8)).foregroundStyle(.gray)
                Button { analyzer.clearRecords() } label: {
                    Text("清除").font(.system(size: 9)).foregroundStyle(.gray)
                }
            }

            if analyzer.records.isEmpty {
                Text("检测到人脸后将自动开始分析...")
                    .font(.system(size: 10)).foregroundStyle(.gray)
                    .padding(.vertical, 8)
            } else {
                ForEach(analyzer.records.prefix(10)) { record in
                    Button { selectedRecord = record } label: {
                        recordRow(record)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func recordRow(_ r: FaceAnalysisRecord) -> some View {
        HStack(spacing: 8) {
            // Energy score circle
            ZStack {
                Circle()
                    .stroke(scoreColor(r.energyScore).opacity(0.3), lineWidth: 2)
                    .frame(width: 28, height: 28)
                Text("\(r.energyScore)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(scoreColor(r.energyScore))
            }

            VStack(alignment: .leading, spacing: 2) {
                // Tags
                HStack(spacing: 4) {
                    ForEach(r.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 8))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(tagColor(tag), in: Capsule())
                    }
                }
                // Time
                Text(r.timestamp, style: .time)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.gray)
            }

            Spacer()

            // Mini stats
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 2) {
                    Image(systemName: "eye").font(.system(size: 7))
                    Text(String(format: "%.0f%%", ((r.eyeOpenLeft + r.eyeOpenRight) / 2) * 100))
                        .font(.system(size: 8, design: .monospaced))
                }
                .foregroundStyle(.cyan)
                HStack(spacing: 2) {
                    Image(systemName: "face.smiling").font(.system(size: 7))
                    Text(String(format: "%.0f%%", r.smileScore * 100))
                        .font(.system(size: 8, design: .monospaced))
                }
                .foregroundStyle(.yellow)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 7)).foregroundStyle(.gray)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 7 { return .green }
        if score >= 4 { return .yellow }
        return .red
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "精神饱满": return .green.opacity(0.6)
        case "心情愉快": return .yellow.opacity(0.6)
        case "状态一般", "心情平静": return .gray.opacity(0.4)
        case "有些疲惫": return .orange.opacity(0.6)
        case "非常疲惫": return .red.opacity(0.6)
        case "表情严肃": return .blue.opacity(0.4)
        case "低头": return .purple.opacity(0.5)
        default: return .gray.opacity(0.3)
        }
    }

    // MARK: - Tracking Info

    private var trackingInfoBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle().fill(camera.tracking.targetDetected ? Color.yellow : Color.red).frame(width: 6, height: 6)
                Text(camera.tracking.targetDetected ? "已检测" : "未检测")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                Text("(\(camera.tracking.source.rawValue))")
                    .font(.system(size: 8)).foregroundStyle(.gray)
            }

            if camera.tracking.targetDetected, let t = camera.targets.first {
                VStack(spacing: 1) {
                    Text("位置").font(.system(size: 7)).foregroundStyle(.gray)
                    Text(String(format: "%.2f", t.center.x))
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
                }
                VStack(spacing: 1) {
                    Text("偏差").font(.system(size: 7)).foregroundStyle(.gray)
                    Text(String(format: "%+.2f", camera.tracking.error))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(camera.tracking.inDeadZone ? .green : .orange)
                }
                VStack(spacing: 1) {
                    Text("调整").font(.system(size: 7)).foregroundStyle(.gray)
                    Text(String(format: "%+d°", camera.tracking.servoAdjustment))
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.yellow)
                }
            }

            Spacer()

            Text(camera.tracking.targetDetected
                 ? (camera.tracking.inDeadZone ? "居中" : (camera.tracking.error > 0 ? "→ 右转" : "← 左转"))
                 : "等待")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(camera.tracking.inDeadZone ? .green : .orange)
        }
        .padding(6)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - PID Controls

    private var pidControlsBar: some View {
        HStack(spacing: 10) {
            Button {
                camera.autoTrackEnabled.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: camera.autoTrackEnabled ? "target" : "pause.circle").font(.system(size: 10))
                    Text(camera.autoTrackEnabled ? "追踪中" : "已暂停").font(.system(size: 9))
                }
                .foregroundStyle(camera.autoTrackEnabled ? .green : .gray)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(camera.autoTrackEnabled ? Color.green.opacity(0.15) : Color.white.opacity(0.06), in: Capsule())
            }
            Spacer()
            HStack(spacing: 2) {
                Text("死区").font(.system(size: 8)).foregroundStyle(.gray)
                Text(String(format: "%.2f", camera.deadZone)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
            }
            HStack(spacing: 2) {
                Image(systemName: "gyroscope").font(.system(size: 8)).foregroundStyle(.cyan)
                Text("\(ServoBLEManager.shared.currentAngle)°").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
            }
        }
        .padding(6)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Record Detail Sheet

struct RecordDetailSheet: View {
    let record: FaceAnalysisRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .stroke(scoreColor(record.energyScore).opacity(0.3), lineWidth: 4)
                                    .frame(width: 60, height: 60)
                                Circle()
                                    .trim(from: 0, to: CGFloat(record.energyScore) / 10.0)
                                    .stroke(scoreColor(record.energyScore), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .frame(width: 60, height: 60)
                                    .rotationEffect(.degrees(-90))
                                Text("\(record.energyScore)")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(scoreColor(record.energyScore))
                            }
                            Text("精力评分").font(.caption).foregroundStyle(.secondary)
                            Text(record.timestamp, style: .date)
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(record.timestamp, style: .time)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                Section("标签") {
                    FlowLayout(spacing: 6) {
                        ForEach(record.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.subheadline)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color(.systemGray5), in: Capsule())
                        }
                    }
                }

                Section("分析详情") {
                    Text(record.details)
                        .font(.subheadline)
                }

                Section("详细数据") {
                    dataRow("左眼开合", value: String(format: "%.0f%%", record.eyeOpenLeft * 100))
                    dataRow("右眼开合", value: String(format: "%.0f%%", record.eyeOpenRight * 100))
                    dataRow("微笑程度", value: String(format: "%.0f%%", record.smileScore * 100))
                    dataRow("头部偏航", value: String(format: "%.1f°", record.faceYaw))
                    dataRow("头部俯仰", value: String(format: "%.1f°", record.facePitch))
                }
            }
            .navigationTitle("分析详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func dataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 7 { return .green }
        if score >= 4 { return .yellow }
        return .red
    }
}

// MARK: - Flow Layout (for tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(subviews: subviews, width: proposal.width ?? 300)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, width: bounds.width)
        for (index, pos) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func layout(subviews: Subviews, width: CGFloat) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: width, height: y + rowHeight), positions)
    }
}

// MARK: - Face Camera Panel

private struct FaceCameraPanel: View {
    let title: String
    let image: CGImage?
    let faces: [DetectedTarget]
    let tracking: TrackingState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let cgImage = image {
                    Image(decorative: cgImage, scale: 1)
                        .resizable().scaledToFit()
                        .overlay {
                            FaceOverlay(faces: faces, tracking: tracking, viewSize: geo.size,
                                        imageSize: CGSize(width: cgImage.width, height: cgImage.height))
                        }
                }
                VStack {
                    HStack {
                        Text(title).font(.caption).fontWeight(.semibold).foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.5)).cornerRadius(6)
                        Spacer()
                        Text("\(faces.count)人").font(.caption2).fontWeight(.bold).foregroundStyle(.yellow)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.5)).cornerRadius(6)
                    }.padding(8)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Face Overlay

private struct FaceOverlay: View {
    let faces: [DetectedTarget]
    let tracking: TrackingState
    let viewSize: CGSize
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            let fitRect = fitImageRect(viewSize: geo.size, imageSize: imageSize)

            Path { p in
                let cx = fitRect.origin.x + fitRect.width / 2
                p.move(to: CGPoint(x: cx, y: fitRect.origin.y))
                p.addLine(to: CGPoint(x: cx, y: fitRect.origin.y + fitRect.height))
            }
            .stroke(Color.green.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))

            ForEach(faces) { target in
                let boxColor: Color = target.source == .body ? .red : .yellow
                let center = toViewPoint(normalized: target.center, in: fitRect)

                ForEach(0..<target.joints.count, id: \.self) { i in
                    let pos = toViewPoint(normalized: target.joints[i], in: fitRect)
                    Circle().fill(Color.red.opacity(0.7)).frame(width: 5, height: 5).position(pos)
                }

                let bboxRect = toViewRect(normalized: target.boundingBox, in: fitRect)
                Rectangle().stroke(boxColor, lineWidth: 1.5)
                    .frame(width: bboxRect.width, height: bboxRect.height)
                    .position(x: bboxRect.midX, y: bboxRect.midY)

                Circle().fill(boxColor).frame(width: 10, height: 10)
                    .shadow(color: boxColor, radius: 3).position(center)

                Path { p in
                    p.move(to: CGPoint(x: center.x - 8, y: center.y))
                    p.addLine(to: CGPoint(x: center.x + 8, y: center.y))
                    p.move(to: CGPoint(x: center.x, y: center.y - 8))
                    p.addLine(to: CGPoint(x: center.x, y: center.y + 8))
                }.stroke(Color.white, lineWidth: 1.2)

                Text(target.source.rawValue)
                    .font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(boxColor.opacity(0.8)).cornerRadius(4)
                    .position(x: center.x, y: center.y - 16)
            }
        }
    }

    private func fitImageRect(viewSize: CGSize, imageSize: CGSize) -> CGRect {
        let s = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let w = imageSize.width * s, h = imageSize.height * s
        return CGRect(x: (viewSize.width - w) / 2, y: (viewSize.height - h) / 2, width: w, height: h)
    }
    private func toViewPoint(normalized: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.origin.x + normalized.x * rect.width, y: rect.origin.y + normalized.y * rect.height)
    }
    private func toViewRect(normalized: CGRect, in rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x + normalized.origin.x * rect.width, y: rect.origin.y + normalized.origin.y * rect.height,
               width: normalized.width * rect.width, height: normalized.height * rect.height)
    }
}

// MARK: - Info Sheet

private struct FaceTrackingInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("工作原理") {
                    VStack(alignment: .leading, spacing: 12) {
                        infoRow(icon: "face.smiling", text: "使用 Apple Vision 框架进行人脸和人体检测，实时追踪目标位置。")
                        infoRow(icon: "gyroscope", text: "PID 控制算法将人脸偏差转换为舵机调整角度，实现自动追踪。")
                        infoRow(icon: "brain.head.profile", text: "每分钟自动分析人脸状态：眼睛开合度、微笑程度、头部姿态，评估精神状态。")
                    }.padding(.vertical, 4)
                }
                Section("精力评分标准") {
                    VStack(alignment: .leading, spacing: 6) {
                        scoreRow("8-10 分", desc: "精神饱满，眼睛明亮，面带笑容", color: .green)
                        scoreRow("5-7 分", desc: "状态一般，表情平和", color: .yellow)
                        scoreRow("1-4 分", desc: "比较疲惫，眼睛半闭或闭合", color: .red)
                    }.padding(.vertical, 4)
                }
            }
            .navigationTitle("关于人脸追踪").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
    private func infoRow(icon: String, text: String) -> some View {
        Label { Text(text).font(.caption) } icon: { Image(systemName: icon).foregroundStyle(.yellow).frame(width: 24) }
    }
    private func scoreRow(_ range: String, desc: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(range).font(.caption).fontWeight(.medium).frame(width: 60, alignment: .leading)
            Text(desc).font(.caption).foregroundStyle(.secondary)
        }
    }
}
