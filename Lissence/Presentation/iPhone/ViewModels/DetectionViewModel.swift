/// 감지모드의 **로직** 코드입니다.

import Foundation
import SwiftUI
import Combine
import AVFoundation
import UIKit

class DetectionViewModel: NSObject, ObservableObject {
    // MARK: - 의존성 주입 (Services)
    private let soundDetector = SoundDetector()
    private let speechManager = SpeechManager()
    private let attentionCallAnalyzer = AttentionCallAnalyzer()
    private let connectivity = ConnectivityManager.shared
    private let bleManager = LissenceBLEManager.shared
    private let dangerHapticController = DangerHapticController()

    // MARK: - Published Properties (View에서 관찰)
    @Published var lastDetectedSound: String = ""
    @Published var transcript: String = ""
    @Published var isVoiceOn: Bool = false {
        didSet {
            // Sheet를 손으로 내리거나 X 버튼을 눌러서 false가 되었을 때도 대응
            if oldValue == true && isVoiceOn == false {
                speechManager.stopRecording()
                attentionCallAnalyzer.reset()
                resetConversationState()
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

    /// 자막 시트 표시 모드입니다.
    @Published var conversationMode: ConversationMode = .subtitle

    /// 대화 모드 메시지 기록입니다.
    @Published var messages: [ChatMessage] = []

    /// 사용자가 TTS로 출력할 문장입니다.
    @Published var inputText: String = ""

    let quickPhrases = QuickPhrase.defaults
    let inputCharLimit = 200
    let defaultTTSGuide = "저는 청각장애인입니다. 아이폰 마이크에 대고 천천히 이야기해주세요."

    private var cancellables = Set<AnyCancellable>()
    private var resetTimer: Timer?
    private var commitTimer: Timer?
    private var ttsWatchdog: Timer?
    private var lastCommittedTranscript = ""
    private var isMicSuspendedForTTS = false
    private var lastAttentionAlertTime: Date = .distantPast
    private var lastAttentionAlertSignature = ""
    private let attentionAlertCooldown: TimeInterval = 1.5
    private var lastDangerHapticTime: Date = .distantPast
    private var lastDangerHapticSound: DangerSound = .unknown
    private let dangerHapticCooldown: TimeInterval = 1.0

    override init() {
        super.init()
        setupBindings()
        bleManager.delegate = self
        TTSManager.shared.delegate = self
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
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcript in
                guard let self else { return }

                self.transcript = transcript
                self.handleAttentionCallTranscript(transcript)
                self.schedulePartnerCommit(for: transcript)
            }
            .store(in: &cancellables)
    }

    // MARK: - 핵심 로직: 오디오 세션 제어 (2순위 문제 해결)
    func toggleVoiceMode() {
        isVoiceOn.toggle()

        if isVoiceOn {
            attentionCallAnalyzer.reset()
            lastAttentionAlertSignature = ""
            lastAttentionAlertTime = .distantPast
            lastCommittedTranscript = ""

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
            attentionCallAnalyzer.reset()
            resetConversationState()
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
            playDangerHapticIfNeeded(for: sound)

            // 5초 후 UI 초기화 타이머
            resetTimer?.invalidate()
            resetTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.lastDetectedSound = ""
                }
            }
        }
    }

    /// 위험 소리 종류별 iPhone 햅틱을 출력합니다.
    private func playDangerHapticIfNeeded(for sound: DangerSound) {
        guard sound.isDanger else {
            return
        }

        let now = Date()
        guard sound != lastDangerHapticSound ||
                now.timeIntervalSince(lastDangerHapticTime) >= dangerHapticCooldown else {
            print("📳 [iPhoneHaptic] skipped cooldown")
            return
        }

        lastDangerHapticSound = sound
        lastDangerHapticTime = now
        dangerHapticController.play(for: sound)
    }

    /// Speech transcript를 조건 기반 호출 감지로 변환합니다.
    private func handleAttentionCallTranscript(_ transcript: String) {
        let analysis = attentionCallAnalyzer.analyze(transcript: transcript)

        guard analysis.alertLevel != .none else {
            return
        }

        // 기존 위험음 감지 화면을 display/soft 호출 후보가 덮어쓰지 않도록 유지합니다.
        if isDanger && analysis.alertLevel != .strongAlert {
            return
        }

        switch analysis.alertLevel {
        case .none:
            break
        case .displayOnly:
            showAttentionCall(title: "호출어 후보 감지", isDanger: false)
        case .softAlert:
            showAttentionCall(title: "호출 감지", isDanger: false)
            if shouldEmitAttentionAlert(level: .softAlert, analysis: analysis) {
                playAttentionHaptic(level: .softAlert)
            }
            // TODO: Watch softAlert 별도 햅틱은 MessageData alertLevel 확장 후 연결합니다.
        case .strongAlert:
            showAttentionCall(title: "긴급 호출 감지!", isDanger: true)
            if shouldEmitAttentionAlert(level: .strongAlert, analysis: analysis) {
                playAttentionHaptic(level: .strongAlert)
                sendStrongAttentionAlertToWatch(transcript: analysis.transcript)
            }
        }
    }

    /// 호출 감지 결과를 iPhone 감지 화면에 표시합니다.
    private func showAttentionCall(title: String, isDanger: Bool) {
        lastDetectedSound = title
        currentSoundIcon = "person.wave.2.fill"
        self.isDanger = isDanger

        resetTimer?.invalidate()
        resetTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.lastDetectedSound = ""
                self?.isDanger = false
            }
        }
    }

    /// 호출 감지 단계에 맞는 iPhone 햅틱을 재생합니다.
    private func playAttentionHaptic(level: AttentionAlertLevel) {
        switch level {
        case .softAlert:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .strongAlert:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .none, .displayOnly:
            break
        }
    }

    /// partial transcript 중복으로 같은 호출 알림이 반복 출력되는 것을 줄입니다.
    private func shouldEmitAttentionAlert(level: AttentionAlertLevel, analysis: AttentionCallAnalysis) -> Bool {
        let now = Date()
        let signature = "\(level.rawValue)-\(analysis.score)-\(analysis.emergencyKeywordDetected)"

        guard signature != lastAttentionAlertSignature ||
                now.timeIntervalSince(lastAttentionAlertTime) >= attentionAlertCooldown else {
            return false
        }

        lastAttentionAlertSignature = signature
        lastAttentionAlertTime = now
        return true
    }

    /// strongAlert만 기존 WatchConnectivity 위험 메시지 경로로 전달합니다.
    private func sendStrongAttentionAlertToWatch(transcript: String) {
        let message = MessageData(
            title: "긴급 호출 감지!",
            iconName: "person.wave.2.fill",
            isDanger: true,
            transcript: transcript
        )
        connectivity.send(message: message)
    }

    // MARK: - 수명 주기 관리
    func onAppear() {
        print("📡 [DetectionVM] onAppear → BLE startScan() 강제 호출")
        // 가이드 §2 계층 3: 감지 모드 진입 시 SoundAnalysis와 BLE 스캔을 동시에 시작합니다.
        bleManager.delegate = self
        TTSManager.shared.delegate = self
        soundDetector.startDetection()
        bleManager.startScan()
    }

    func onDisappear() {
        soundDetector.stopDetection()
        speechManager.stopRecording()
        attentionCallAnalyzer.reset()
        TTSManager.shared.stop()
        // BLE 연결은 백그라운드 위험 감지에도 사용될 수 있으므로 유지합니다.
        // 화면 떠날 때 명시적으로 끊고 싶다면 아래 줄을 활성화하세요.
        // bleManager.stop()
        resetTimer?.invalidate()
        commitTimer?.invalidate()
        ttsWatchdog?.invalidate()
        ttsWatchdog = nil
    }

    // MARK: - 대화 모드

    /// 상대방 STT transcript를 일정 침묵 후 대화 메시지로 저장합니다.
    private func schedulePartnerCommit(for text: String) {
        guard conversationMode == .chat else {
            return
        }

        guard !isMicSuspendedForTTS else {
            return
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, trimmedText != lastCommittedTranscript else {
            return
        }

        commitTimer?.invalidate()
        commitTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.commitPartnerMessage()
            }
        }
    }

    /// SpeechManager의 누적 transcript에서 아직 메시지화하지 않은 새 부분만 저장합니다.
    private func commitPartnerMessage() {
        let fullTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fullTranscript.isEmpty else {
            return
        }

        let newPart: String
        if !lastCommittedTranscript.isEmpty, fullTranscript.hasPrefix(lastCommittedTranscript) {
            newPart = String(fullTranscript.dropFirst(lastCommittedTranscript.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            newPart = fullTranscript
        }

        guard !newPart.isEmpty else {
            return
        }

        messages.append(ChatMessage(text: newPart, sender: .partner))
        lastCommittedTranscript = fullTranscript
    }

    func speakDefaultGuide() {
        speakText(defaultTTSGuide, appendMessage: true)
    }

    func sendMyMessage(speak: Bool = true) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }

        inputText = ""
        speakText(text, appendMessage: true, speak: speak)
    }

    func sendQuickPhrase(_ phrase: QuickPhrase) {
        speakText(phrase.text, appendMessage: true)
    }

    func replay(_ message: ChatMessage) {
        TTSManager.shared.speak(message.text)
    }

    private func speakText(_ text: String, appendMessage: Bool, speak: Bool = true) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        if appendMessage {
            messages.append(ChatMessage(text: trimmedText, sender: .me, wasSpoken: speak))
        }

        if speak {
            TTSManager.shared.speak(trimmedText)
        }
    }

    private func resetConversationState() {
        lastCommittedTranscript = ""
        commitTimer?.invalidate()
        ttsWatchdog?.invalidate()
        ttsWatchdog = nil
        isMicSuspendedForTTS = false
        messages.removeAll()
        inputText = ""
        conversationMode = .subtitle
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

// MARK: - TTSManagerDelegate

extension DetectionViewModel: TTSManagerDelegate {
    func ttsManagerWillStartSpeaking(_ manager: TTSManager) {
        guard isVoiceOn else {
            return
        }

        isMicSuspendedForTTS = true
        speechManager.stopRecording()
        commitTimer?.invalidate()

        ttsWatchdog?.invalidate()
        ttsWatchdog = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            print("[DetectionVM] TTS watchdog fired; forcing mic resume")
            self.ttsManagerDidFinishSpeaking(TTSManager.shared)
        }
    }

    func ttsManagerDidFinishSpeaking(_ manager: TTSManager) {
        ttsWatchdog?.invalidate()
        ttsWatchdog = nil

        guard isMicSuspendedForTTS else {
            return
        }

        isMicSuspendedForTTS = false

        guard isVoiceOn else {
            return
        }

        lastCommittedTranscript = ""
        transcript = ""
        commitTimer?.invalidate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.isVoiceOn, !self.isMicSuspendedForTTS else {
                return
            }

            self.speechManager.startRecording()
        }
    }
}
