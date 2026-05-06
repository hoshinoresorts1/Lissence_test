/// 감지모드의 화면 코드입니다.
/// **여기에 감지모드 로직은 작성하지 않습니다.**

import SwiftUI

struct DetectionDetailView: View {
    @Binding var currentPath: String
    @StateObject private var viewModel = DetectionViewModel()

    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Spacer()
            
            contentView
            
            Spacer()
            
            bottomControls
        }
        // 자막창 시트: viewModel의 isVoiceOn 상태에 따라 자동으로 열림
        .sheet(isPresented: $viewModel.isVoiceOn) {
            SubtitleWidgetView(
                isShowing: $viewModel.isVoiceOn,
                text: viewModel.transcript.isEmpty ? "소리를 기다리고 있습니다..." : viewModel.transcript
            )
            .interactiveDismissDisabled() // 제스처로 끄기 방지 (버튼으로만 끄게 함)
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }
}

// MARK: - UI Components (Extensions)
extension DetectionDetailView {
    
    // 1. 헤더: 홈 버튼 및 음성 인식 토글
    private var headerView: some View {
        HStack {
            Button(action: { currentPath = "home" }) {
                Image(systemName: "house.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
            
            // 토글 버튼: 클릭 시 ViewModel의 오디오 세션 제어 로직 실행
            Button(action: { viewModel.toggleVoiceMode() }) {
                HStack {
                    Image(systemName: viewModel.isVoiceOn ? "mic.fill" : "mic.slash")
                    Text(viewModel.isVoiceOn ? "음성 인식 중" : "음성 인식")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(viewModel.isVoiceOn ? Color.red : Color.gray.opacity(0.2))
                .foregroundColor(viewModel.isVoiceOn ? .white : .primary)
                .cornerRadius(20)
            }
        }
        .padding()
    }
    
    // 2. 메인 컨텐츠: 소리 감지 결과 표시
    private var contentView: some View {
        VStack {
            if viewModel.lastDetectedSound.isEmpty {
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    Text("주변 소리 분석 중...")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: viewModel.currentSoundIcon)
                        .font(.system(size: 100))
                        .foregroundColor(viewModel.isDanger ? .red : .blue)
                    
                    Text(viewModel.lastDetectedSound)
                        .font(.system(size: 32, weight: .bold))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(), value: viewModel.lastDetectedSound)
    }
    
    // 3. 하단 컨트롤: 모드 전환 버튼
    private var bottomControls: some View {
        Button(action: { currentPath = "music" }) {
            Label("음악모드 전환", systemImage: "music.quarternote.3")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(15)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 30)
    }
}
