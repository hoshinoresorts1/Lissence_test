/// 감지모드

import SwiftUI
import UserNotifications

struct WatchDetectionView: View {
    
    /// ViewModel로 통합
    @StateObject private var viewModel = WatchDetectionViewModel()
    
    var body: some View {
        VStack {
            // 2. 뷰모델에서 정제된 상태(hasData)만 판단합니다.
            if viewModel.hasData {
                displayInfo(
                    title: viewModel.displayTitle,
                    icon: viewModel.displayIcon,
                    isDanger: viewModel.isDanger,
                    source: viewModel.sourceText
                )
           } else {
               // 데이터가 없을 때 보여줄 기본 화면
               ProgressView()
               Text("소리 대기 중...")
                   .font(.footnote)
                   .padding(.top, 5)
           }
        }
        .navigationTitle("감지 모드")
            .onAppear() {
                // 3. 엔진 제어권을 뷰모델에 넘깁니다.
                viewModel.startDetection()
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if granted { print("알림 권한 승인됨") }
                }
        }
            .onDisappear {
                viewModel.stopDetection()            }
        }
    
    // 공통 UI 컴포넌트
    @ViewBuilder
    /// 아이폰에서 수신된 데이터 표시 (자막이나 상세 정보)
    /// - Parameters:
    ///   - title: 위험이름
    ///   - icon: 위험 종류별 아이콘
    ///   - isDanger: 위험한지 여부
    ///   - source: 아이폰 또는 워치
    /// - Returns: 뷰로 반환
    func displayInfo(title: String, icon: String, isDanger: Bool, source: String) -> some View {
        Image(systemName: icon)
            .resizable()
            .scaledToFit()
            .frame(width: 50, height: 50)
            .foregroundColor(isDanger ? .red : .green)
        
        Text(title)
            .font(.headline)
            .multilineTextAlignment(.center)
        
        Text("\(source)에서 감지됨!")
            .font(.caption2)
            .foregroundColor(.gray)
    }
}

