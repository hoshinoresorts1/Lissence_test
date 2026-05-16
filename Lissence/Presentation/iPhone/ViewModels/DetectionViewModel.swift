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
    private let bleManager = LissenceBLEManager.shared

    // MARK: - Published Properties (View에서 관찰)
    @Published var lastDetectedSound: String = ""
    @Published var transcript: String = ""
    @Published var isVoiceOn: Bool = false {
        didSet {
            // Sheet를 손으로 내리거나 X 버튼을 눌러서 false가 되었을 때도 대응
            if oldValue == true && isVoiceOn == false {
                speechManager.stopRecording()
                if !soundDetector.isRunning {
                    soundDetector.startDetection()
                }
            }
        }
    }
    @Published var currentSoundIcon: String = "waveform.circle"
    @Published var isDanger: Bool = false

    /// ESP32(HearAlert) BLE 연결 여부입니다. 화면 인디케이터에서 관찰합니다.
    @Published var isBLEConnected: Bool = false

    /// BLE 진행 상태 문구입니다. 화면 인디케이터에서 관찰합니다.
    @Published var bleStatusText: String = "BLE 대기 중"

    /// 발견한 ESP32 광고 이름입니다.
    @Published var bleDeviceName: String = "-"

    private var cancellables = Set<AnyCancellable>()
    private var resetTimer: Timer?

    init() {
        setupBindings()
        bleManager.delegate = self
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
            // 실험 브랜치 전용: 음성인식 중에도 SoundAnalysis 위험 감지가 유지되는지 확인합니다.
            // 기존 안정 구조로 되돌리려면 아래 호출을 복구합니다.
            // soundDetector.stopDetection()
            
            // 2. 약간의 시간차를 두어 오디오 세션이 정리될 시간을 줍니다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.speechManager.startRecording()
            }
        } else {
            // 3. 음성 인식 종료 후 다시 소리 감지 재개
            speechManager.stopRecording()
            if !soundDetector.isRunning {
                soundDetector.startDetection()
            }
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
        print("📡 [DetectionVM] onAppear → BLE startScan() 강제 호출")
        // 가이드 §2 계층 3: 감지 모드 진입 시 SoundAnalysis와 BLE 스캔을 동시에 시작합니다.
        bleManager.delegate = self
        soundDetector.startDetection()
        bleManager.startScan()
    }

    func onDisappear() {
        soundDetector.stopDetection()
        speechManager.stopRecording()
        resetTimer?.invalidate()
    }
}

// MARK: - LissenceBLEManagerDelegate

extension DetectionViewModel: LissenceBLEManagerDelegate {
    func bleManager(_ manager: LissenceBLEManager, didUpdateBluetoothState stateText: String) {
        // 화면 인디케이터에는 status쪽을 우선 노출하되, BT 자체가 꺼진 경우만 별도로 표시합니다.
        if stateText.contains("꺼져") || stateText.contains("권한") || stateText.contains("지원하지") {
            bleStatusText = stateText
        }
    }

    func bleManager(_ manager: LissenceBLEManager, didUpdateStatus statusText: String) {
        bleStatusText = statusText
    }

    func bleManager(_ manager: LissenceBLEManager, didUpdateConnection isConnected: Bool) {
        isBLEConnected = isConnected
    }

    func bleManager(_ manager: LissenceBLEManager, didDiscoverDeviceName deviceName: String) {
        bleDeviceName = deviceName
    }
}
