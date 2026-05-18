/// 음악 모드입니다.
/// - 기능
///     - Rive 캐릭터 기반 음악 시각화
///     - 파티클 배경 이펙트
///     - iPhone 햅틱 출력

import RiveRuntime
import SwiftUI

struct MusicDetailView: View {
    // MARK: - 속성

    /// 화면 전환 상태입니다.
    @Binding var currentPath: String

    /// 음악 모드의 상태와 액션을 관리하는 ViewModel입니다.
    @StateObject private var viewModel = MusicViewModel()

    /// 음악 감정 캐릭터를 표시하는 Rive 모델입니다.
    @StateObject private var riveModel = RiveViewModel(fileName: "lissence_emotion")

    // MARK: - 본문

    var body: some View {
        ZStack {
            SwiftUI.Color(.systemBackground).ignoresSafeArea()

            if viewModel.isRunning {
                MusicMoodParticleView(
                    mood: viewModel.currentMood,
                    intensity: viewModel.visualIntensity,
                    sharpness: viewModel.visualSharpness,
                    bass: viewModel.visualBass,
                    treble: viewModel.visualTreble,
                    beatPulse: viewModel.beatPulse,
                    bassPulse: viewModel.bassPulse,
                    burstCenterOffset: CGSize(width: 0, height: -86)
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }

            VStack(spacing: 0) {
                header

                Spacer()

                VStack(spacing: 30) {
                    riveModel.view()
                        .frame(width: 320, height: 320)
                        .shadow(color: moodAccentColor.opacity(0.35), radius: 28)

                    Button(action: { viewModel.toggleRunning() }) {
                        Label(
                            viewModel.isRunning ? "분석 중지" : "분석 시작",
                            systemImage: viewModel.isRunning ? "stop.fill" : "play.fill"
                        )
                        .font(.headline)
                        .frame(width: 168, height: 54)
                        .background(viewModel.isRunning ? SwiftUI.Color.red : SwiftUI.Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                }

                Spacer()

                Button(action: { currentPath = "detection" }) {
                    Label("감지 모드 전환", systemImage: "waveform")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(SwiftUI.Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            viewModel.currentMood = .neutral
            riveModel.setInput("mood", value: MusicMood.neutral.riveValue)
            riveModel.setInput("intensity", value: 0.0)
            riveModel.setInput("volume_spike", value: 0.0)
        }
        .onChange(of: viewModel.currentMood) { _, newMood in
            riveModel.setInput("mood", value: (newMood ?? .neutral).riveValue)
        }
        .onChange(of: viewModel.visualIntensity) { _, newValue in
            riveModel.setInput("intensity", value: min(max(newValue, 0), 1))
        }
        .onChange(of: viewModel.beatPulse) { _, _ in
            riveModel.setInput("volume_spike", value: 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                riveModel.setInput("volume_spike", value: 0.0)
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    // MARK: - 하위 뷰

    /// 상단 컨트롤 바입니다.
    private var header: some View {
        HStack {
            Button(action: { currentPath = "home" }) {
                Image(systemName: "house.fill")
                    .font(.title2)
                    .foregroundColor(.primary.opacity(0.72))
                    .frame(width: 44, height: 44)
            }

            Spacer()
        }
        .padding(.horizontal)
        .frame(height: 60)
        .overlay {
            Text("음악 모드")
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(.primary)
                .offset(y: 124)
        }
    }

    // MARK: - 상태 표시

    /// 현재 무드에 맞는 화면 강조 색상입니다.
    private var moodAccentColor: SwiftUI.Color {
        switch viewModel.currentMood {
        case .happy:
            return SwiftUI.Color.orange
        case .angry:
            return SwiftUI.Color.red
        case .sad:
            return SwiftUI.Color.blue
        case .relaxed:
            return SwiftUI.Color.green
        case .neutral:
            return SwiftUI.Color.gray
        case nil:
            return SwiftUI.Color.gray
        }
    }
}
