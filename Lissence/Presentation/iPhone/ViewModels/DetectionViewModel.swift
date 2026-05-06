/// 감지모드의 **로직** 코드입니다.

import Foundation
import SwiftUI
import Combine
import AVFoundation

class DetectionViewModel: ObservableObject {
    // MARK: - 의존성 주입 (Services)
    private let soundDetector = SoundDetector()
    private let speechManager = SpeechManager()
    private let connectivity = ConnectivityManager.shared
    
    // MARK: - Published Properties (View에서 관찰)
    @Published var lastDetectedSound: String = ""
    @Published var transcript: String = ""
    @Published var isVoiceOn: Bool = false {
        didSet {
            // Sheet를 손으로 내리거나 X 버튼을 눌러서 false가 되었을 때도 대응
            if oldValue == true && isVoiceOn == false {
                speechManager.stopRecording()
                soundDetector.startDetection()
            }
        }
    }
    @Published var currentSoundIcon: String = "waveform.circle"
    @Published var isDanger: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private var resetTimer: Timer?

    init() {
        setupBindings()
    }

    // MARK: - 데이터 흐름 연결 (Combine)
    private func setupBindings() {
        // SoundDetector에서 감지된 소리를 감시하여 뷰모델 상태 업데이트
        soundDetector.$lastDetectedSound
            .sink { [weak self] soundLabel in
                guard let self = self, !soundLabel.isEmpty else { return }
                self.updateUI(with: soundLabel)
            }
            .store(in: &cancellables)
            
        // SpeechManager에서 인식된 자막 업데이트
        speechManager.$transcript
            .assign(to: \.transcript, on: self)
            .store(in: &cancellables)
    }

    // MARK: - 핵심 로직: 오디오 세션 제어 (2순위 문제 해결)
    func toggleVoiceMode() {
        isVoiceOn.toggle()
        
        if isVoiceOn {
            // 1. 음성 인식 시작 전, 소리 감지를 잠시 중단하여 충돌 방지
            soundDetector.stopDetection()
            
            // 2. 약간의 시간차를 두어 오디오 세션이 정리될 시간을 줍니다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.speechManager.startRecording()
            }
        } else {
            // 3. 음성 인식 종료 후 다시 소리 감지 재개
            speechManager.stopRecording()
            soundDetector.startDetection()
        }
    }

    private func updateUI(with label: String) {
        // DangerSound 모델을 사용하여 아이콘과 위험 여부 판단
        if let sound = DangerSound.allCases.first(where: { $0.label == label }) {
            self.lastDetectedSound = label
            self.currentSoundIcon = sound.icon
            self.isDanger = sound.isDanger
            
            // 5초 후 UI 초기화 타이머
            resetTimer?.invalidate()
            resetTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.lastDetectedSound = ""
                }
            }
        }
    }

    // MARK: - 수명 주기 관리
    func onAppear() {
        soundDetector.startDetection()
    }

    func onDisappear() {
        soundDetector.stopDetection()
        speechManager.stopRecording()
        resetTimer?.invalidate()
    }
}
