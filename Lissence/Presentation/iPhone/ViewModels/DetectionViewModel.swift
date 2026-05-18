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
    private let attentionHapticController = AttentionHapticController()

    // MARK: - Published Properties (View에서 관찰)
    @Published var lastDetectedSound: String = ""
    @Published var transcript: String = ""
    @Published var isVoiceOn: Bool = false {
        didSet {
            // Sheet를 손으로 내리거나 X 버튼을 눌러서 false가 되었을 때도 대응
            if oldValue == true && isVoiceOn == false {
                visibleTranscriptBaseline = latestRawSpeechTranscript
                resetConversationState()
                ensureSpeechRecognitionRunning()
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

    /// 반복 호출 softAlert에서 대화 UI 진입을 제안하는 플로팅 팝업 표시 여부입니다.
    @Published var showAttentionPrompt: Bool = false

    /// 반복 호출 softAlert에서 표시할 플로팅 팝업 문구입니다.
    @Published var attentionPromptMessage: String = "누군가가 부릅니다. 음성 인식 기능을 켤까요?"

    let quickPhrases = QuickPhrase.defaults
    let inputCharLimit = 200
    let defaultTTSGuide = "저는 청각장애인입니다."

    private var cancellables = Set<AnyCancellable>()
    private var resetTimer: Timer?
    private var commitTimer: Timer?
    private var ttsWatchdog: Timer?
    private var lastCommittedTranscript = ""
    private var latestRawSpeechTranscript = ""
    private var visibleTranscriptBaseline = ""
    private var lastAttentionTranscript = ""
    private var isMicSuspendedForTTS = false
    private var isViewActive = false
    private var lastAttentionPromptTime: Date = .distantPast
    private let attentionPromptCooldown: TimeInterval = 6.0
    private var lastAttentionAlertTime: Date = .distantPast
    private var lastAttentionAlertSignature = ""
    private let attentionAlertCooldown: TimeInterval = 1.5
    private let maxAttentionSegmentLength = 30
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
            .sink { [weak self] rawTranscript in
                guard let self else { return }

                self.latestRawSpeechTranscript = rawTranscript
                self.handleAttentionCallTranscriptUpdate(rawTranscript)
                self.updateVisibleTranscriptIfNeeded(rawTranscript)
            }
            .store(in: &cancellables)
    }

    // MARK: - 핵심 로직: 오디오 세션 제어 (2순위 문제 해결)
    func toggleVoiceMode() {
        if isVoiceOn {
            isVoiceOn = false
        } else {
            activateVoiceMode()
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

    /// SpeechManager의 누적 transcript에서 새로 들어온 조각만 호출 감지로 변환합니다.
    private func handleAttentionCallTranscriptUpdate(_ transcript: String) {
        guard let segment = makeAttentionAnalysisSegment(from: transcript) else {
            return
        }

        handleAttentionCallTranscript(segment)
    }

    /// Speech transcript 조각을 조건 기반 호출 감지로 변환합니다.
    private func handleAttentionCallTranscript(_ transcript: String) {
        let analysis = attentionCallAnalyzer.analyzeSegment(transcript: transcript)

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
                print("📳 [AttentionHaptic] requested level=softAlert")
                playAttentionHaptic(level: .softAlert)
                presentAttentionPromptIfNeeded()
            }
            // TODO: Watch softAlert 별도 햅틱은 MessageData alertLevel 확장 후 연결합니다.
        case .strongAlert:
            showAttentionCall(title: "긴급 호출 감지!", isDanger: true)
            if shouldEmitAttentionAlert(level: .strongAlert, analysis: analysis) {
                print("📳 [AttentionHaptic] requested level=strongAlert")
                playAttentionHaptic(level: .strongAlert)
                sendStrongAttentionAlertToWatch(transcript: analysis.transcript)
                attentionCallAnalyzer.reset()
            }
        }
    }

    /// 누적 STT 문자열에서 새 조각만 뽑되, partial completion을 위해 짧은 앞쪽 겹침만 유지합니다.
    private func makeAttentionAnalysisSegment(from transcript: String) -> String? {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTranscript.isEmpty else {
            lastAttentionTranscript = ""
            attentionCallAnalyzer.reset()
            return nil
        }

        defer {
            lastAttentionTranscript = trimmedTranscript
        }

        guard !lastAttentionTranscript.isEmpty else {
            guard trimmedTranscript.count <= maxAttentionSegmentLength else {
                print("[AttentionCall] initial transcript too long -> baseline updated, skip full transcript")
                return nil
            }

            return trimmedTranscript
        }

        if trimmedTranscript.hasPrefix(lastAttentionTranscript) {
            let delta = String(trimmedTranscript.dropFirst(lastAttentionTranscript.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !delta.isEmpty else {
                return nil
            }

            let overlap = String(lastAttentionTranscript.suffix(4))
            let rawSegment = (overlap + delta)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let segment = String(rawSegment.suffix(maxAttentionSegmentLength))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !segment.isEmpty else {
                return nil
            }

            print("[AttentionCall] segment=\(segment)")
            return segment
        }

        print("[AttentionCall] transcript restarted -> baseline updated, skip full transcript")
        return nil
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
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.playAttentionHaptic(level: level)
            }
            return
        }

        switch level {
        case .softAlert:
            print("📳 [AttentionHaptic] play softAlert")
            attentionHapticController.play(level: .softAlert)
        case .strongAlert:
            print("📳 [AttentionHaptic] play strongAlert")
            attentionHapticController.play(level: .strongAlert)
        case .none, .displayOnly:
            break
        }
    }

    private func resetAttentionCallState(resetAlertCooldown: Bool = false) {
        lastAttentionTranscript = ""
        attentionCallAnalyzer.reset()

        if resetAlertCooldown {
            lastAttentionAlertSignature = ""
            lastAttentionAlertTime = .distantPast
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

    /// 반복 호출 팝업의 "네" 동작입니다. 기존 음성인식 버튼 ON과 동일하게 대화 UI를 엽니다.
    func acceptAttentionPrompt() {
        showAttentionPrompt = false
        activateVoiceMode()
    }

    /// 반복 호출 팝업의 "아니오" 동작입니다. 백그라운드 STT는 계속 유지합니다.
    func dismissAttentionPrompt() {
        showAttentionPrompt = false
    }

    /// 음성인식 UI를 열고, 이전 백그라운드 STT 누적분은 화면 표시 기준선으로만 저장합니다.
    private func activateVoiceMode() {
        prepareVisibleSpeechSession()
        isVoiceOn = true
        ensureSpeechRecognitionRunning()
    }

    /// UI 표시용 STT 상태를 새 대화 시작 기준으로 초기화합니다.
    private func prepareVisibleSpeechSession() {
        visibleTranscriptBaseline = latestRawSpeechTranscript
        transcript = ""
        lastCommittedTranscript = ""
        commitTimer?.invalidate()
        messages.removeAll()
        inputText = ""
    }

    /// 백그라운드 STT raw transcript에서 UI가 켜진 이후 새로 들어온 부분만 화면 상태에 반영합니다.
    private func updateVisibleTranscriptIfNeeded(_ rawTranscript: String) {
        guard isVoiceOn else {
            return
        }

        let visibleText = visibleSpeechText(from: rawTranscript)
        transcript = visibleText
        schedulePartnerCommit(for: visibleText)
    }

    /// 백그라운드 STT baseline 이전 텍스트를 제거하고 현재 UI 세션의 새 텍스트만 반환합니다.
    private func visibleSpeechText(from rawTranscript: String) -> String {
        guard !rawTranscript.isEmpty else {
            return ""
        }

        if !visibleTranscriptBaseline.isEmpty, rawTranscript.hasPrefix(visibleTranscriptBaseline) {
            return String(rawTranscript.dropFirst(visibleTranscriptBaseline.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if rawTranscript == visibleTranscriptBaseline {
            return ""
        }

        // Speech가 재시작되어 transcript가 짧아진 경우에는 새 세션 문장으로 간주합니다.
        if rawTranscript.count < visibleTranscriptBaseline.count {
            visibleTranscriptBaseline = ""
            return rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // baseline과 prefix가 맞지 않는 긴 누적문은 UI에 노출하지 않고 새 baseline으로만 삼습니다.
        visibleTranscriptBaseline = rawTranscript
        return ""
    }

    /// 반복 호출 softAlert에서 음성인식 UI 진입 제안 팝업을 중복 없이 표시합니다.
    private func presentAttentionPromptIfNeeded() {
        guard !isVoiceOn, !showAttentionPrompt else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastAttentionPromptTime) >= attentionPromptCooldown else {
            return
        }

        lastAttentionPromptTime = now
        showAttentionPrompt = true
    }

    /// 감지모드가 켜져 있는 동안 AttentionCallAnalyzer 분석용 백그라운드 STT를 유지합니다.
    private func ensureSpeechRecognitionRunning() {
        guard isViewActive, !isMicSuspendedForTTS, !speechManager.isRecording else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.isViewActive, !self.isMicSuspendedForTTS, !self.speechManager.isRecording else {
                return
            }

            self.speechManager.startRecording()
        }
    }

    // MARK: - 수명 주기 관리
    func onAppear() {
        print("📡 [DetectionVM] onAppear → BLE startScan() 강제 호출")
        // 가이드 §2 계층 3: 감지 모드 진입 시 SoundAnalysis와 BLE 스캔을 동시에 시작합니다.
        isViewActive = true
        bleManager.delegate = self
        TTSManager.shared.delegate = self
        resetAttentionCallState(resetAlertCooldown: true)
        soundDetector.startDetection()
        ensureSpeechRecognitionRunning()
        bleManager.startScan()
    }

    func onDisappear() {
        isViewActive = false
        soundDetector.stopDetection()
        speechManager.stopRecording()
        resetAttentionCallState(resetAlertCooldown: true)
        TTSManager.shared.stop()
        // BLE 연결은 백그라운드 위험 감지에도 사용될 수 있으므로 유지합니다.
        // 화면 떠날 때 명시적으로 끊고 싶다면 아래 줄을 활성화하세요.
        // bleManager.stop()
        resetTimer?.invalidate()
        commitTimer?.invalidate()
        ttsWatchdog?.invalidate()
        ttsWatchdog = nil
        showAttentionPrompt = false
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
        transcript = ""
        visibleTranscriptBaseline = latestRawSpeechTranscript
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
            ensureSpeechRecognitionRunning()
            return
        }

        lastCommittedTranscript = ""
        transcript = ""
        visibleTranscriptBaseline = latestRawSpeechTranscript
        commitTimer?.invalidate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.isViewActive, !self.isMicSuspendedForTTS else {
                return
            }

            self.speechManager.startRecording()
        }
    }
}
