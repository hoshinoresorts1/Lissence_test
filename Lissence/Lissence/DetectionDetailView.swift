import SwiftUI

struct DetectionDetailView: View {
    @Binding var currentPath: String
    @State private var isVoiceOn = false
    
    // 워치 연동을 위한 매니저 (관찰 대상)
    @StateObject var connectivity = ConnectivityManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. 헤더 영역 (상단 네비게이션 및 설정)
            headerView
            
            Spacer()
            
            // MARK: - 2. 컨텐츠 영역 (메인 로직 및 정보 표시)
            contentView
            
            Spacer()
            
            // MARK: - 3. 하단 컨트롤 영역 (버튼 및 인터랙션)
            bottomControls
        }
        // 자막창 (Sheet)
        .sheet(isPresented: $isVoiceOn) {
            SubtitleWidgetView(isShowing: $isVoiceOn, text: "실시간 대화 내용입니다...")
                .interactiveDismissDisabled()
        }
    }
}

// MARK: - Subviews (섹션별로 나누어 관리)
extension DetectionDetailView {
    
    // Header: 홈 버튼과 음성인식 토글
    private var headerView: some View {
        HStack {
            Button(action: { currentPath = "home" }) {
                Image(systemName: "house.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Toggle("음성인식", isOn: $isVoiceOn)
                .toggleStyle(.button)
                .tint(.orange)
        }
        .padding(.horizontal)
        .frame(height: 60)
        .overlay {
            Text("감지 모드")
                .font(.system(size: 40, weight: .bold))
                .offset(y: 130)
        }
    }
    
    // Content: 소리 분석 상태 표시
    private var contentView: some View {
        VStack(spacing: 25) {
            Image(systemName: "waveform")
                .font(.system(size: 90))
                .foregroundColor(.blue)
            
            Text("소리 분석 중..")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
    
    // Bottom Controls: 모드 전환 버튼 및 워치 전송 테스트
    private var bottomControls: some View {
        VStack(spacing: 15) {
            // 워치 전송 테스트 버튼
            Button("워치로 위험 신호 보내기") {
                let msg = MessageData(title: "위험 감지됨!", iconName: "exclamationmark.triangle", isDanger: true)
                connectivity.send(message: msg)
            }
            .padding(.bottom, 10)
            
            // 음악 모드 전환 버튼
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
}

// MARK: - Preview
#Preview {
    DetectionDetailView(currentPath: .constant("detection"))
}
