/// iPhone 수신 데이터와 Watch 자체 감지 데이터를 뷰모델에서 하나로 통합하여,
/// 뷰가 "무엇을 보여줄지" 고민하지 않게 만듬

import Foundation
import SwiftUI
import Combine

/// 워치 감지 화면의 비즈니스 로직을 담당하는 뷰모델
class WatchDetectionViewModel: ObservableObject {
    
    // MARK: - 의존성 (Services)
    private let classifier = SoundClassifier()
    private let connectivity = ConnectivityManager.shared
    private let haptic = HapticController.shared // 햅틱 컨트롤러 추가
    
    // MARK: - Published Properties (View에서 관찰)
    /// 뷰에서 보여줄 최종 데이터 상태
    @Published var displayTitle: String = "소리 대기 중..."
    @Published var displayIcon: String = "waveform.circle"
    @Published var isDanger: Bool = false
    @Published var sourceText: String = ""
    @Published var hasData: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
    }
    
    // MARK: - 데이터 흐름 통합 (Combine)
    private func setupBindings() {
        // 1. iPhone 수신 메시지와 Watch 자체 감지 결과를 결합(데이터 업데이트 바인딩)
        Publishers.CombineLatest(connectivity.$receivedMessage, classifier.$detectedSound)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] iphoneMessage, watchSound in
                self?.updateDisplayState(iphoneMessage: iphoneMessage, watchSound: watchSound)
            }
            .store(in: &cancellables)
        
        // 2. [핵심] 햅틱 실행 바인딩 (비즈니스 로직)
        // Watch 자체 감지 결과가 바뀔 때마다 햅틱 로직을 실행합니다.
        classifier.$detectedSound
            .filter { $0 != .unknown } // 알 수 없는 소리는 제외
            .sink { [weak self] sound in
                self?.haptic.play(for: sound)
            }
            .store(in: &cancellables)

        // 3. iPhone에서 메시지가 왔을 때도 햅틱을 실행하고 싶다면 아래 코드를 추가합니다.
        connectivity.$receivedMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                // MessageData로부터 DangerSound를 유추하거나 일반 알림 햅틱을 실행
                // 여기서는 일반 알림 햅틱을 실행하도록 HapticController를 활용할 수 있습니다.
                if message.isDanger {
                    self?.haptic.play(for: .siren) // 위험 상황 햅틱
                }
            }
            .store(in: &cancellables)
    }
    
    /// 데이터 우선순위에 따라 UI 상태를 업데이트합니다.
    /// 우선순위: iPhone 메시지 > Watch 감지 결과
    private func updateDisplayState(iphoneMessage: MessageData?, watchSound: DangerSound) {
        if let iphone = iphoneMessage {
            // iPhone 데이터가 있을 때
            self.displayTitle = iphone.title
            self.displayIcon = iphone.iconName
            self.isDanger = iphone.isDanger
            self.sourceText = "iPhone"
            self.hasData = true
        } else if watchSound != .unknown {
            // iPhone 데이터는 없지만 Watch가 감지했을 때
            self.displayTitle = watchSound.label
            self.displayIcon = watchSound.icon
            self.isDanger = watchSound.isDanger
            self.sourceText = "Watch"
            self.hasData = true
        } else {
            // 아무 데이터도 없을 때 (초기 상태)
            self.displayTitle = "소리 대기 중..."
            self.displayIcon = "waveform.and.mic"
            self.isDanger = false
            self.sourceText = ""
            self.hasData = false
        }
    }
    
    // MARK: - 엔진 제어
    func startDetection() {
        classifier.start()
    }
    
    func stopDetection() {
        classifier.stop()
    }
}
