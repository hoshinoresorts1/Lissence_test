/// 음악모드 

import SwiftUI

struct WatchMusicView: View {
    // 위에서 만든 연산 없는 클래스 주입
    @StateObject private var classifier = SoundOnlyClassifier()

    var body: some View {
        VStack {
            Text("테스트 1: 마이크 가동 중")
                .font(.headline)
            Spacer()
            Circle()
                .frame(width: 50, height: 50)
                .foregroundColor(classifier.isRunning ? .green : .red)
        }
        .navigationTitle("음악 모드")
        .onAppear {
            classifier.start()
        }
        .onDisappear {
            classifier.stop()
        }
    }
}
