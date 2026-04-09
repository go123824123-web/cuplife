//
//  OnboardingView.swift
//  wave
//

import SwiftUI
import AVKit

// MARK: - Pet data

struct PetOption: Identifiable {
    let id: String
    let ext: String
    let quietID: String
    let quietExt: String
    let name: String
    let description: String
    let available: Bool
}

private let petOptions: [PetOption] = [
    PetOption(id: "fox_greeting", ext: "mov", quietID: "dream_pet", quietExt: "mov",
              name: "小狐狸", description: "机灵可爱的小狐狸，总是第一个跑来跟你打招呼", available: false),
    PetOption(id: "elf_greeting", ext: "mov", quietID: "dream_pet", quietExt: "mov",
              name: "小精灵", description: "神秘的森林精灵，拥有治愈人心的温柔力量", available: false),
    PetOption(id: "cat_greeting", ext: "mov", quietID: "dream_pet", quietExt: "mov",
              name: "小猫咪", description: "软萌的布偶猫，最喜欢安静地陪在你身边", available: true),
]

private let randomNames = [
    "团子", "麻薯", "年糕", "豆沙", "芋圆",
    "布丁", "奶茶", "可乐", "芒果", "西瓜",
    "小白", "大橘", "花花", "咪咪", "球球",
    "饺子", "汤圆", "月饼", "糯米", "栗子",
]

// MARK: - Onboarding View

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var step = 0
    @State private var selectedIndex = 0
    @State private var petName = ""
    @State private var currentPlayer: AVPlayer?
    @State private var playID = UUID()
    @State private var showComingSoon = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch step {
            case 0: choosePetStep
            case 1: namePetStep
            case 2: drinkGuideStep
            default: EmptyView()
            }
        }
        .statusBarHidden(true)
        .onAppear { playGreeting(for: selectedIndex) }
        .onChange(of: selectedIndex) { idx in
            playGreeting(for: idx)
        }
        .alert("即将推出", isPresented: $showComingSoon) {
            Button("好的") {}
        } message: {
            Text("\(petOptions[selectedIndex].name) 正在准备中，敬请期待！")
        }
    }

    // MARK: - Video

    private func playGreeting(for index: Int) {
        currentPlayer?.pause()
        let pet = petOptions[index]
        guard let url = Bundle.main.url(forResource: pet.id, withExtension: pet.ext) else { return }
        let player = AVPlayer(url: url)
        player.isMuted = false
        player.play()
        currentPlayer = player
        playID = UUID()
    }

    private func playQuiet(for index: Int) {
        currentPlayer?.pause()
        let pet = petOptions[index]
        guard let url = Bundle.main.url(forResource: pet.quietID, withExtension: pet.quietExt) else { return }
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.play()
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
            player.seek(to: .zero)
            player.play()
        }
        currentPlayer = player
        playID = UUID()
    }

    // MARK: - Step 0: Choose

    private var choosePetStep: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)

            Text("选择你的伙伴")
                .font(.title2).fontWeight(.bold)
                .foregroundStyle(.white)

            Spacer().frame(height: 16)

            // Video (full width)
            GeometryReader { geo in
                let side = geo.size.width - 16
                ZStack {
                    Color.white.opacity(0.03)

                    if let player = currentPlayer {
                        VideoPlayer(player: player)
                            .disabled(true)
                            .id(playID)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity)
                .onTapGesture { playGreeting(for: selectedIndex) }
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, 8)

            Spacer().frame(height: 12)

            // Pet name
            Text(petOptions[selectedIndex].name)
                .font(.title2).fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.top, 2)

            // Description with left/right arrows on sides
            HStack(spacing: 8) {
                Button {
                    if selectedIndex > 0 { selectedIndex -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(selectedIndex > 0 ? .white : .white.opacity(0.15))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(selectedIndex > 0 ? 0.12 : 0.04), in: Circle())
                }
                .disabled(selectedIndex == 0)

                Text(petOptions[selectedIndex].description)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Button {
                    if selectedIndex < petOptions.count - 1 { selectedIndex += 1 }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(selectedIndex < petOptions.count - 1 ? .white : .white.opacity(0.15))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(selectedIndex < petOptions.count - 1 ? 0.12 : 0.04), in: Circle())
                }
                .disabled(selectedIndex >= petOptions.count - 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            Spacer()

            // Select button
            Button {
                let pet = petOptions[selectedIndex]
                if pet.available {
                    petName = ""
                    playQuiet(for: selectedIndex)
                    withAnimation { step = 1 }
                } else {
                    showComingSoon = true
                }
            } label: {
                Text("选择 \(petOptions[selectedIndex].name)")
                    .font(.headline)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 24))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Step 1: Name

    private var namePetStep: some View {
        let pet = petOptions[selectedIndex]

        return VStack(spacing: 0) {
            Spacer().frame(height: 40)

            if let player = currentPlayer {
                VideoPlayer(player: player)
                    .disabled(true)
                    .id(playID)
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Text(pet.name)
                .font(.headline).foregroundStyle(.white)
                .padding(.top, 10)

            Spacer().frame(height: 28)

            Text("给它起个名字吧")
                .font(.title3).fontWeight(.bold)
                .foregroundStyle(.white)

            Spacer().frame(height: 16)

            // Name input
            TextField("输入名字...", text: $petName)
                .font(.title3)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 24)

            Spacer().frame(height: 12)

            // Random name button
            Button {
                petName = randomNames.randomElement() ?? "团子"
            } label: {
                HStack(spacing: 8) {
                    Text("🎲").font(.system(size: 22))
                    Text("随机起一个名字").font(.subheadline)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 24)

            Spacer()

            // Back + Start
            VStack(spacing: 10) {
                Button {
                    savePetChoice()
                    playThirsty()
                    withAnimation { step = 2 }
                } label: {
                    Text("下一步")
                        .font(.headline)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(petName.isEmpty ? Color.white.opacity(0.06) : Color.white.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 24))
                        .foregroundStyle(petName.isEmpty ? .gray : .white)
                }
                .disabled(petName.isEmpty)

                Button {
                    playGreeting(for: selectedIndex)
                    withAnimation { step = 0 }
                } label: {
                    Text("返回")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }

    // MARK: - Step 2: Drink guide

    private func playThirsty() {
        currentPlayer?.pause()
        guard let url = Bundle.main.url(forResource: "cat_thirsty", withExtension: "mov") else { return }
        let player = AVPlayer(url: url)
        player.isMuted = false
        // Loop
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
            player.seek(to: .zero)
            player.play()
        }
        player.play()
        currentPlayer = player
        playID = UUID()
    }

    @ObservedObject private var drinkDetector = DrinkDetector.shared
    @State private var guideDrinkDone = false
    @State private var drinkCountAtStart = 0

    private var drinkGuideStep: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)

            // Video (large)
            GeometryReader { geo in
                let side = geo.size.width - 16
                ZStack {
                    if let player = currentPlayer {
                        VideoPlayer(player: player)
                            .disabled(true)
                            .id(playID)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, 8)

            Spacer().frame(height: 16)

            if guideDrinkDone {
                VStack(spacing: 10) {
                    Text("🎉").font(.system(size: 50))
                    Text("\(petName) 喝饱啦！")
                        .font(.title).fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text("你学会照顾它了")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.5))
                }
            } else {
                VStack(spacing: 10) {
                    Text("\(petName) 渴了")
                        .font(.largeTitle).fontWeight(.bold)
                        .foregroundStyle(.white)

                    Text("拿起杯子，喝一口水")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.6))

                    if drinkDetector.phase == .tilting {
                        Text("继续倾斜...")
                            .font(.title3).fontWeight(.medium)
                            .foregroundStyle(.orange)
                    } else if drinkDetector.phase == .drinking {
                        Text("正在喝水...")
                            .font(.title3).fontWeight(.medium)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer()

            // Button
            Button {
                currentPlayer?.pause()
                currentPlayer = nil
                drinkDetector.isRunning = false
                isPresented = false
            } label: {
                Text(guideDrinkDone ? "进入主页" : "跳过")
                    .font(.headline)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(guideDrinkDone ? Color.white.opacity(0.2) : Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 24))
                    .foregroundStyle(guideDrinkDone ? .white : .white.opacity(0.4))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .onAppear {
            guideDrinkDone = false
            drinkCountAtStart = drinkDetector.drinkCount
            drinkDetector.isRunning = true
        }
        .onChange(of: drinkDetector.drinkCount) { newCount in
            if newCount > drinkCountAtStart {
                withAnimation {
                    guideDrinkDone = true
                }
            }
        }
    }

    private func savePetChoice() {
        let pet = petOptions[selectedIndex]
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        UserDefaults.standard.set(pet.id, forKey: "selectedPetID")
        UserDefaults.standard.set(petName, forKey: "petName")
    }
}
