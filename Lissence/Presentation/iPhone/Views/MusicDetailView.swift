/// 음악 모드입니다.
/// - 기능
///     - 음악 시각화
///     - 햅틱 출력

import SwiftUI

struct MusicDetailView: View {
    /// 화면 전환 상태입니다.
    @Binding var currentPath: String

    /// 음악 모드의 상태와 액션을 관리하는 ViewModel입니다.
    @StateObject private var viewModel = MusicViewModel()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // MARK: - 상단 컨트롤 바
                HStack {
                    Button(action: { currentPath = "home" }) {
                        Image(systemName: "house.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                }.padding(.horizontal)
                    .frame(height: 60)
                    
                    .overlay {
                        Text("음악 모드")
                            .font(.system(size: 40, weight: .bold))
                            .offset(y:130)
                    }
                    
                    Spacer()
                
                // MARK: - 중앙 핵심 콘텐츠
                VStack(spacing: 22) {
                    Image(systemName: viewModel.currentMood?.iconName ?? "music.quarternote.3")
                        .font(.system(size: 90))
                        .foregroundColor(.purple)
                    
                    Text(viewModel.currentMood?.displayName ?? "음악 분석 대기 중")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text(viewModel.statusText)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)

                    if viewModel.currentMood != nil {
                        Text("신뢰도 \(String(format: "%.1f%%", viewModel.confidence * 100.0))")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)
                    }

                    VStack(spacing: 8) {
                        ForEach(MusicMood.allCases) { mood in
                            moodProbabilityRow(mood)
                        }
                    }
                    .padding(.horizontal, 30)
                }
                
                Spacer()

                // MARK: - 모드 전환 버튼
                Button(action: { viewModel.toggleRunning() }) {
                    Label(
                        viewModel.isRunning ? "음악 분석 중지" : "음악 분석 시작",
                        systemImage: viewModel.isRunning ? "stop.fill" : "mic.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(viewModel.isRunning ? Color.red : Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 12)

                Button(action: { currentPath = "detection" }) {
                    Label("감지 모드 전환", systemImage: "waveform")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    // MARK: - 상태 표시

    /// 무드별 분석 확률을 표시하는 행입니다.
    private func moodProbabilityRow(_ mood: MusicMood) -> some View {
        HStack(spacing: 10) {
            Text(mood.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 52, alignment: .leading)

            ProgressView(value: viewModel.probabilities[mood] ?? 0.0)
                .tint(.purple)

            Text(String(format: "%.1f%%", (viewModel.probabilities[mood] ?? 0.0) * 100.0))
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}
