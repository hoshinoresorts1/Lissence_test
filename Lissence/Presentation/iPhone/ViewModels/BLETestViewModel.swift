/// iPhone BLE 테스트 화면의 상태와 버튼 액션을 관리합니다.

import Combine
import Foundation
import AVFoundation
import SoundAnalysis

/// ESP32 BLE 통신 검증 화면에서 사용할 MVVM ViewModel입니다.
final class BLETestViewModel: ObservableObject {
    // MARK: - 속성

    /// Bluetooth 권한과 전원 상태를 나타내는 문구입니다.
    @Published var bluetoothStateText = "Bluetooth 상태 확인 중"

    /// BLE 작업 진행 상태를 나타내는 문구입니다.
    @Published var statusText = "BLE 테스트 대기 중"

    /// 현재 ESP32와 연결되어 있는지 여부입니다.
    @Published var isConnected = false

    /// 최근 발견한 Peripheral 이름입니다.
    @Published var discoveredDeviceName = "-"

    /// 최근 ESP32에서 받은 문자열 메시지입니다.
    @Published var lastReceivedMessage = "-"

    /// 최근 ESP32로 보낸 문자열 메시지입니다.
    @Published var lastSentMessage = "-"

    /// ESP32에서 최근 수신한 INMP441 RMS 값입니다.
    @Published var latestMicRMS: Int?

    /// ESP32에서 최근 수신한 INMP441 peak 값입니다.
    @Published var latestMicPeak: Int?

    /// 최근 ESP32 lightweight audio candidate 종류입니다.
    @Published var latestAudioCandidateKind = "-"

    /// 최근 ESP32 lightweight audio candidate RMS 값입니다.
    @Published var latestAudioCandidateRMS: Int?

    /// 최근 ESP32 lightweight audio candidate peak 값입니다.
    @Published var latestAudioCandidatePeak: Int?

    /// ESP32 lightweight audio candidate 수신 개수입니다.
    @Published var audioCandidateReceivedCount = 0

    /// 최근 ESP32 lightweight audio candidate 수신 시각입니다.
    @Published var latestAudioCandidateDate: Date?

    /// BLE 후보 이벤트로 트리거한 iPhone 마이크 위험 분석 상태입니다.
    @Published var triggeredAnalysisStateText = "idle"

    /// BLE 후보 이벤트로 마지막 iPhone 마이크 분석을 시작한 시각입니다.
    @Published var lastTriggeredAnalysisDate: Date?

    /// BLE 후보 이벤트로 실행한 iPhone 마이크 분석의 최근 위험 소리 label입니다.
    @Published var lastTriggeredDangerLabel = "-"

    /// BLE 후보 이벤트로 실행한 iPhone 마이크 분석의 최근 confidence입니다.
    @Published var lastTriggeredDangerConfidence: Double?

    /// BLE 후보 이벤트로 실행한 iPhone 마이크 분석 요청 ID입니다.
    @Published var currentTriggeredAnalysisRequestID = 0

    /// BLE 후보 이벤트로 실행한 analyzer의 최근 최상위 classification label입니다.
    @Published var lastTriggeredAnalyzerLabel = "-"

    /// BLE 후보 이벤트로 실행한 analyzer의 최근 최상위 classification confidence입니다.
    @Published var lastTriggeredAnalyzerConfidence: Double?

    /// BLE 후보 이벤트로 실행 중인 iPhone 마이크 분석의 현재 예정 window입니다.
    @Published var currentTriggeredAnalysisWindowSeconds = 0.0

    /// 최근 RMS 값 기준의 간단한 마이크 입력 상태입니다.
    @Published var micLevelStateText = "-"

    /// PCM audio stream binary packet 수신 개수입니다.
    @Published var audioPacketsReceived = 0

    /// 재조립에 성공한 20ms PCM chunk 개수입니다.
    @Published var audioChunksReconstructed = 0

    /// sequence gap 기준으로 감지한 누락 chunk 개수입니다.
    @Published var audioDroppedChunks = 0

    /// 최근 재조립한 PCM chunk byte 크기입니다.
    @Published var latestAudioChunkSize = 0

    /// 최근 수신한 PCM audio stream sequence입니다.
    @Published var latestAudioSequence: UInt16?

    /// 최근 PCM ring buffer byte 크기입니다.
    @Published var audioRingBufferBytes = 0

    /// 최근 PCM ring buffer 길이를 초 단위로 환산한 값입니다.
    @Published var audioRingBufferDurationSeconds = 0.0

    /// SoundAnalysis 연결 전 최소 분석 window가 준비되었는지 여부입니다.
    @Published var isAudioAnalysisReady = false

    /// 재조립된 PCM chunk 기준으로 추정한 누적 수신 audio 길이입니다.
    @Published var estimatedReceivedAudioSeconds = 0.0

    /// PCM ring buffer를 Int16 little-endian으로 해석한 RMS 값입니다.
    @Published var pcmRMS: Int?

    /// PCM ring buffer를 Int16 little-endian으로 해석한 peak 값입니다.
    @Published var pcmPeak: Int?

    /// PCM ring buffer의 zero crossing rate입니다.
    @Published var pcmZeroCrossingRate: Double?

    /// PCM ring buffer에서 해석한 sample 수입니다.
    @Published var pcmSampleCount = 0

    /// PCM audio stream 테스트 상태 문구입니다.
    @Published var audioStreamingStateText = "idle"

    /// BLE PCM 기반 SoundAnalysis 실험 상태 문구입니다.
    @Published var bleAudioAnalysisStatusText = "idle"

    /// BLE PCM SoundAnalysis의 최근 classification identifier입니다.
    @Published var bleAudioLastClassification = "-"

    /// BLE PCM SoundAnalysis의 최근 confidence입니다.
    @Published var bleAudioLastConfidence: Double?

    /// BLE PCM SoundAnalysis를 실행한 최근 sequence입니다.
    @Published var bleAudioLastAnalysisSequence: UInt16?

    /// 테스트 write 버튼 활성화 여부입니다.
    var canSendTestCommand: Bool {
        isConnected
    }

    /// PCM audio stream 버튼 활성화 여부입니다.
    var canControlAudioStream: Bool {
        isConnected
    }

    /// 화면에 표시할 최근 RMS 값 문자열입니다.
    var latestMicRMSText: String {
        latestMicRMS.map(String.init) ?? "-"
    }

    /// 화면에 표시할 최근 peak 값 문자열입니다.
    var latestMicPeakText: String {
        latestMicPeak.map(String.init) ?? "-"
    }

    /// 화면에 표시할 최근 audio candidate RMS 문자열입니다.
    var latestAudioCandidateRMSText: String {
        latestAudioCandidateRMS.map(String.init) ?? "-"
    }

    /// 화면에 표시할 최근 audio candidate peak 문자열입니다.
    var latestAudioCandidatePeakText: String {
        latestAudioCandidatePeak.map(String.init) ?? "-"
    }

    /// 화면에 표시할 최근 audio candidate 수신 시각 문자열입니다.
    var latestAudioCandidateTimeText: String {
        guard let latestAudioCandidateDate else {
            return "-"
        }

        return Self.audioCandidateDateFormatter.string(from: latestAudioCandidateDate)
    }

    /// 화면에 표시할 최근 iPhone 마이크 분석 트리거 시각 문자열입니다.
    var lastTriggeredAnalysisTimeText: String {
        guard let lastTriggeredAnalysisDate else {
            return "-"
        }

        return Self.audioCandidateDateFormatter.string(from: lastTriggeredAnalysisDate)
    }

    /// 화면에 표시할 최근 iPhone 마이크 분석 confidence 문자열입니다.
    var lastTriggeredDangerConfidenceText: String {
        guard let lastTriggeredDangerConfidence else {
            return "-"
        }

        return String(format: "%.3f", lastTriggeredDangerConfidence)
    }

    /// 화면에 표시할 BLE 후보 기반 iPhone 마이크 분석 window 길이입니다.
    var triggeredAnalysisWindowSecondsText: String {
        let windowSeconds = currentTriggeredAnalysisWindowSeconds > 0
            ? currentTriggeredAnalysisWindowSeconds
            : Self.triggeredAnalysisConfiguration.baseWindowSeconds

        return String(format: "%.1f sec", windowSeconds)
    }

    /// 화면에 표시할 BLE 후보 기반 iPhone 마이크 분석 요청 ID입니다.
    var currentTriggeredAnalysisRequestIDText: String {
        currentTriggeredAnalysisRequestID == 0 ? "-" : String(currentTriggeredAnalysisRequestID)
    }

    /// 화면에 표시할 최근 analyzer 최상위 classification confidence 문자열입니다.
    var lastTriggeredAnalyzerConfidenceText: String {
        guard let lastTriggeredAnalyzerConfidence else {
            return "-"
        }

        return String(format: "%.3f", lastTriggeredAnalyzerConfidence)
    }

    /// 화면에 표시할 최근 PCM audio stream sequence 문자열입니다.
    var latestAudioSequenceText: String {
        latestAudioSequence.map(String.init) ?? "-"
    }

    /// 화면에 표시할 PCM ring buffer 길이 문자열입니다.
    var audioRingBufferDurationText: String {
        String(format: "%.2f sec", audioRingBufferDurationSeconds)
    }

    /// 화면에 표시할 분석 준비 상태 문자열입니다.
    var audioAnalysisReadyText: String {
        isAudioAnalysisReady ? "true" : "false"
    }

    /// 화면에 표시할 추정 수신 audio 길이 문자열입니다.
    var estimatedReceivedAudioText: String {
        String(format: "%.2f sec", estimatedReceivedAudioSeconds)
    }

    /// 화면에 표시할 PCM RMS 문자열입니다.
    var pcmRMSText: String {
        pcmRMS.map(String.init) ?? "-"
    }

    /// 화면에 표시할 PCM peak 문자열입니다.
    var pcmPeakText: String {
        pcmPeak.map(String.init) ?? "-"
    }

    /// 화면에 표시할 PCM zero crossing rate 문자열입니다.
    var pcmZeroCrossingRateText: String {
        guard let pcmZeroCrossingRate else {
            return "-"
        }

        return String(format: "%.3f", pcmZeroCrossingRate)
    }

    /// 화면에 표시할 BLE PCM sample rate 문자열입니다.
    var bleAudioSampleRateText: String {
        "\(Int(BLEAudioAnalysisFormat.sampleRate)) Hz"
    }

    /// 화면에 표시할 BLE PCM SoundAnalysis confidence 문자열입니다.
    var bleAudioConfidenceText: String {
        guard let bleAudioLastConfidence else {
            return "-"
        }

        return String(format: "%.3f", bleAudioLastConfidence)
    }

    /// 화면에 표시할 BLE PCM SoundAnalysis sequence 문자열입니다.
    var bleAudioLastAnalysisSequenceText: String {
        bleAudioLastAnalysisSequence.map(String.init) ?? "-"
    }

    /// BLE 통신을 담당하는 서비스 객체입니다.
    private let bleManager: LissenceBLEManager

    /// BLE 후보 이벤트 수신 시 짧게 실행하는 기존 iPhone 마이크 기반 위험 감지기입니다.
    private let triggeredSoundDetector = SoundDetector()

    /// BLE 후보 이벤트 기반 위험 분석 상태 구독을 보관합니다.
    private var triggeredAnalysisCancellables = Set<AnyCancellable>()

    /// Audio candidate 수신 시각 표시용 formatter입니다.
    private static let audioCandidateDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// BLE 후보 기반 iPhone 마이크 분석 정책 모드입니다.
    private static let triggeredAnalysisMode: TriggeredAnalysisMode = .demo

    /// BLE 후보 기반 iPhone 마이크 분석 정책입니다.
    private static var triggeredAnalysisConfiguration: TriggeredAnalysisConfiguration {
        TriggeredAnalysisConfiguration(mode: triggeredAnalysisMode)
    }

    /// SoundAnalysis callback을 받을 수 있도록 보장하는 최소 분석 워밍업 시간입니다.
    private static let minAnalysisWarmupSeconds = 0.7

    /// BLE PCM SoundAnalysis 실험을 실행하는 전용 queue입니다.
    private let bleAudioAnalysisQueue = DispatchQueue(label: "com.lissence.ble.audio.analysis")

    /// sequence별 미완성 PCM chunk 조립 버퍼입니다.
    private var audioChunkBuffers: [UInt16: AudioChunkBuffer] = [:]

    /// SoundAnalysis 연결 전 누적 안정성 확인용 PCM ring buffer입니다.
    private var audioRingBuffer = Data()

    /// 현재 실행 중인 BLE PCM SoundAnalysis analyzer입니다.
    private var bleAudioAnalyzer: SNAudioStreamAnalyzer?

    /// 현재 실행 중인 BLE PCM SoundAnalysis observer입니다.
    private var bleAudioAnalysisObserver: BLEAudioAnalysisObserver?

    /// BLE PCM SoundAnalysis가 너무 자주 실행되지 않도록 제한하는 최근 실행 시각입니다.
    private var lastBLEAudioAnalysisDate = Date.distantPast

    /// BLE PCM SoundAnalysis 요청 ID입니다.
    private var bleAudioAnalysisRequestID = 0

    /// BLE PCM SoundAnalysis 요청이 진행 중인지 나타냅니다.
    private var isBLEAudioAnalysisInProgress = false

    /// 다음에 완성될 것으로 기대하는 sequence입니다.
    private var expectedAudioSequence: UInt16?

    /// 오래된 자동 종료 타이머가 최신 stream 상태를 덮어쓰지 않도록 구분하는 ID입니다.
    private var audioStreamRequestID = 0

    /// BLE 후보 이벤트로 실행한 iPhone 마이크 분석 요청 ID입니다.
    private var triggeredAnalysisRequestID = 0

    /// BLE 후보 이벤트로 iPhone 마이크 분석이 진행 중인지 나타냅니다.
    private var isTriggeredAnalysisRunning = false

    /// 현재 request에서 햅틱 write를 이미 전송했는지 확인하는 ID입니다.
    private var hapticSentTriggeredAnalysisRequestID: Int?

    /// BLE 후보 이벤트 기반 분석 시작 시각입니다.
    private var triggeredAnalysisStartedAt: Date?

    /// BLE 후보 이벤트 기반 분석 종료 예정 시각입니다.
    private var triggeredAnalysisStopDeadline: Date?

    /// BLE 후보 이벤트 기반 분석 종료 예약 작업입니다.
    private var triggeredAnalysisStopWorkItem: DispatchWorkItem?

    /// BLE 후보 이벤트 기반 분석 cooldown 종료 예정 시각입니다.
    private var triggeredAnalysisCooldownUntil: Date?

    // MARK: - 초기화

    /// BLE manager를 주입받아 ViewModel을 생성합니다.
    init(bleManager: LissenceBLEManager = .shared) {
        self.bleManager = bleManager
        self.bleManager.delegate = self
        bindTriggeredSoundDetector()
    }

    // MARK: - 시작 제어

    /// ESP32 BLE Peripheral 스캔을 시작합니다.
    func startScan() {
        statusText = "BLE 스캔 시작"
        bleManager.startScan()
    }

    /// BLE 스캔 또는 연결을 중지합니다.
    func stop() {
        stopTriggeredCandidateAnalysis(reason: "BLE test stopped")
        bleManager.stop()
    }

    /// ESP32로 햅틱 테스트 명령을 전송합니다.
    func sendWarningHapticCommand() {
        bleManager.writeWarningHapticCommand()
    }

    /// ESP32에 3초 PCM audio stream 시작을 요청합니다.
    func startAudioStream() {
        resetAudioStreamStats()
        audioStreamingStateText = "requested"
        audioStreamRequestID += 1
        let requestID = audioStreamRequestID
        bleManager.writeStartAudioStreamCommand()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard let self,
                  self.audioStreamRequestID == requestID,
                  self.audioStreamingStateText != "stop requested" else {
                return
            }

            self.audioStreamingStateText = "completed"
        }
    }

    /// ESP32에 PCM audio stream 중지를 요청합니다.
    func stopAudioStream() {
        audioStreamRequestID += 1
        audioStreamingStateText = "stop requested"
        bleManager.writeStopAudioStreamCommand()
    }

    // MARK: - 수신 메시지 처리

    /// BLE notify 문자열에서 mic_level payload를 파싱해 마이크 레벨 상태를 갱신합니다.
    private func updateMicLevelIfNeeded(from text: String) {
        guard let data = text.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["type"] as? String == "mic_level",
              let rms = payload["rms"] as? Int,
              let peak = payload["peak"] as? Int else {
            return
        }

        latestMicRMS = rms
        latestMicPeak = peak
        micLevelStateText = micLevelState(for: rms)
    }

    /// BLE notify 문자열에서 audio_candidate payload를 파싱해 후보 이벤트 상태를 갱신합니다.
    private func updateAudioCandidateIfNeeded(from text: String) {
        guard let data = text.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["type"] as? String == "audio_candidate",
              let kind = payload["kind"] as? String,
              let rms = payload["rms"] as? Int,
              let peak = payload["peak"] as? Int else {
            return
        }

        latestAudioCandidateKind = kind
        latestAudioCandidateRMS = rms
        latestAudioCandidatePeak = peak
        audioCandidateReceivedCount += 1
        latestAudioCandidateDate = Date()

        print("[BLE Candidate] kind=\(kind), rms=\(rms), peak=\(peak)")
        startTriggeredCandidateAnalysisIfNeeded()
    }

    /// RMS 값 기준으로 BLE 테스트 화면에 표시할 간단한 상태값을 반환합니다.
    private func micLevelState(for rms: Int) -> String {
        switch rms {
        case ..<8_000:
            return "quiet"
        case 8_000..<50_000:
            return "active"
        default:
            return "loud"
        }
    }

    // MARK: - Candidate triggered analysis

    /// BLE 후보 이벤트로 실행하는 iPhone 마이크 기반 위험 감지 결과를 UI 상태에 연결합니다.
    private func bindTriggeredSoundDetector() {
        triggeredSoundDetector.$lastDetectedSound
            .receive(on: DispatchQueue.main)
            .sink { [weak self] label in
                guard let self, !label.isEmpty else {
                    return
                }

                self.lastTriggeredDangerLabel = label
                self.triggeredAnalysisStateText = "detected"
            }
            .store(in: &triggeredAnalysisCancellables)

        triggeredSoundDetector.$lastDetectedDangerSound
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sound in
                guard let self, let sound else {
                    return
                }

                self.handleTriggeredDangerSound(sound)
            }
            .store(in: &triggeredAnalysisCancellables)

        triggeredSoundDetector.$lastDetectionConfidence
            .receive(on: DispatchQueue.main)
            .sink { [weak self] confidence in
                self?.lastTriggeredDangerConfidence = confidence
            }
            .store(in: &triggeredAnalysisCancellables)

        triggeredSoundDetector.$lastAnalyzerClassificationIdentifier
            .receive(on: DispatchQueue.main)
            .sink { [weak self] label in
                guard let self else {
                    return
                }

                self.lastTriggeredAnalyzerLabel = label
                self.handleTriggeredAnalyzerLabel(label)
            }
            .store(in: &triggeredAnalysisCancellables)

        triggeredSoundDetector.$lastAnalyzerClassificationConfidence
            .receive(on: DispatchQueue.main)
            .sink { [weak self] confidence in
                self?.lastTriggeredAnalyzerConfidence = confidence
            }
            .store(in: &triggeredAnalysisCancellables)
    }

    /// BLE audio_candidate 수신 시 iPhone 마이크 기반 위험 감지를 짧게 실행합니다.
    private func startTriggeredCandidateAnalysisIfNeeded() {
        let now = Date()

        if isTriggeredAnalysisRunning {
            extendTriggeredCandidateAnalysisIfNeeded(now: now)
            return
        }

        if let triggeredAnalysisCooldownUntil,
           now < triggeredAnalysisCooldownUntil {
            print("[BLE Candidate Trigger] cooldown active, skip")
            return
        }

        let configuration = Self.triggeredAnalysisConfiguration
        isTriggeredAnalysisRunning = true
        triggeredAnalysisRequestID += 1
        let requestID = triggeredAnalysisRequestID
        currentTriggeredAnalysisRequestID = requestID
        lastTriggeredAnalysisDate = now
        triggeredAnalysisStateText = "candidate received"
        lastTriggeredDangerLabel = "-"
        lastTriggeredDangerConfidence = nil
        lastTriggeredAnalyzerLabel = "-"
        lastTriggeredAnalyzerConfidence = nil
        hapticSentTriggeredAnalysisRequestID = nil
        currentTriggeredAnalysisWindowSeconds = configuration.baseWindowSeconds
        triggeredAnalysisStartedAt = now
        triggeredAnalysisStopDeadline = now.addingTimeInterval(configuration.baseWindowSeconds)

        print("[BLE Candidate Trigger] start iPhone mic danger analysis requestID=\(requestID), mode=\(configuration.mode), window=\(configuration.baseWindowSeconds)")
        triggeredSoundDetector.startDetection()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self,
                  self.triggeredAnalysisRequestID == requestID,
                  self.isTriggeredAnalysisRunning else {
                return
            }

            guard self.triggeredSoundDetector.isRunning else {
                print("[BLE Candidate Trigger] failed to start iPhone mic danger analysis")
                self.isTriggeredAnalysisRunning = false
                self.triggeredAnalysisStateText = "failed to start"
                return
            }

            if self.triggeredAnalysisStateText == "starting" {
                self.triggeredAnalysisStateText = "running"
            } else if self.triggeredAnalysisStateText == "candidate received" {
                self.triggeredAnalysisStateText = "running"
            }
        }

        scheduleTriggeredAnalysisStop(requestID: requestID)
    }

    /// BLE 후보 이벤트로 실행한 iPhone 마이크 기반 위험 감지를 종료합니다.
    private func stopTriggeredCandidateAnalysis(reason: String) {
        guard isTriggeredAnalysisRunning else {
            return
        }

        if let startedAt = triggeredAnalysisStartedAt {
            let elapsedSeconds = Date().timeIntervalSince(startedAt)
            if elapsedSeconds < Self.minAnalysisWarmupSeconds {
                let remainingSeconds = Self.minAnalysisWarmupSeconds - elapsedSeconds
                let requestID = triggeredAnalysisRequestID
                print("[BLE Candidate Trigger] min warmup active, delay stop remaining=\(String(format: "%.2f", remainingSeconds))")
                triggeredAnalysisStopWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self,
                          self.triggeredAnalysisRequestID == requestID else {
                        return
                    }

                    self.stopTriggeredCandidateAnalysis(reason: reason)
                }

                triggeredAnalysisStopWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + remainingSeconds, execute: workItem)
                return
            }
        }

        logTriggeredAnalysisStop(reason: reason)
        triggeredAnalysisStopWorkItem?.cancel()
        triggeredAnalysisStopWorkItem = nil
        triggeredSoundDetector.stopDetection()
        isTriggeredAnalysisRunning = false
        triggeredAnalysisStartedAt = nil
        triggeredAnalysisStopDeadline = nil
        triggeredAnalysisCooldownUntil = Date().addingTimeInterval(Self.triggeredAnalysisConfiguration.cooldownSeconds)

        if lastTriggeredDangerLabel == "-" {
            if lastTriggeredAnalyzerLabel == "-" {
                triggeredAnalysisStateText = "completed without analyzer result"
            } else {
                triggeredAnalysisStateText = "completed without detection"
            }
        } else {
            triggeredAnalysisStateText = "completed"
        }
    }

    /// BLE 후보 기반 iPhone 마이크 분석에서 위험 감지가 확정되면 ESP32 햅틱 command를 1회 전송합니다.
    private func handleTriggeredDangerSound(_ sound: DangerSound) {
        guard isTriggeredAnalysisRunning else {
            return
        }

        guard let pattern = sound.hapticPattern else {
            print("[BLE Candidate Trigger] detected danger=\(sound.label), pattern=nil")
            return
        }

        print("[BLE Candidate Trigger] detected danger=\(sound.label), pattern=\(pattern)")

        guard hapticSentTriggeredAnalysisRequestID != currentTriggeredAnalysisRequestID else {
            print("[BLE Candidate Trigger] haptic already sent, skip")
            return
        }

        hapticSentTriggeredAnalysisRequestID = currentTriggeredAnalysisRequestID
        print("[BLE Candidate Trigger] haptic write pattern=\(pattern), requestID=\(currentTriggeredAnalysisRequestID)")
        bleManager.writeHapticPattern(pattern)
    }

    /// 분석 중 추가 candidate가 들어오면 현재 예정된 분석 window를 연장합니다.
    private func extendTriggeredCandidateAnalysisIfNeeded(now: Date) {
        let configuration = Self.triggeredAnalysisConfiguration

        guard canExtendTriggeredAnalysis(for: lastTriggeredAnalyzerLabel) else {
            print("[BLE Candidate Trigger] already running, skip")
            return
        }

        guard let startedAt = triggeredAnalysisStartedAt else {
            return
        }

        let elapsedSeconds = now.timeIntervalSince(startedAt)
        let nextWindowSeconds = min(
            max(currentTriggeredAnalysisWindowSeconds, elapsedSeconds) + configuration.extensionSeconds,
            configuration.maxWindowSeconds
        )

        guard nextWindowSeconds > currentTriggeredAnalysisWindowSeconds else {
            print("[BLE Candidate Trigger] extend skipped, already at max window \(currentTriggeredAnalysisWindowSeconds)")
            return
        }

        currentTriggeredAnalysisWindowSeconds = nextWindowSeconds
        triggeredAnalysisStopDeadline = startedAt.addingTimeInterval(nextWindowSeconds)
        print("[BLE Candidate Trigger] extend analysis window requestID=\(currentTriggeredAnalysisRequestID), window=\(String(format: "%.1f", nextWindowSeconds)), analyzer=\(lastTriggeredAnalyzerLabel)")
        scheduleTriggeredAnalysisStop(requestID: triggeredAnalysisRequestID)
    }

    /// 현재 설정된 종료 예정 시각에 맞춰 분석 종료 작업을 예약합니다.
    private func scheduleTriggeredAnalysisStop(requestID: Int) {
        triggeredAnalysisStopWorkItem?.cancel()

        guard let deadline = triggeredAnalysisStopDeadline else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.triggeredAnalysisRequestID == requestID else {
                return
            }

            self.stopTriggeredCandidateAnalysis(reason: "\(String(format: "%.1f", self.currentTriggeredAnalysisWindowSeconds)) second window completed")
        }

        triggeredAnalysisStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + max(deadline.timeIntervalSinceNow, 0), execute: workItem)
    }

    /// analyzer의 최근 label을 보고 BLE 후보 기반 분석 window 정책을 반영합니다.
    private func handleTriggeredAnalyzerLabel(_ label: String) {
        guard isTriggeredAnalysisRunning else {
            return
        }

        // 디버깅 단계에서는 car_horn 같은 짧은 소리도 window 끝까지 관찰합니다.
        print("[BLE Candidate Trigger] analyzer label observed: \(label)")
    }

    /// BLE 후보 기반 분석 종료 시점의 핵심 디버그 상태를 출력합니다.
    private func logTriggeredAnalysisStop(reason: String) {
        let elapsedSeconds = triggeredAnalysisStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let analyzerConfidenceText = lastTriggeredAnalyzerConfidence.map { String(format: "%.3f", $0) } ?? "-"
        let detectionConfidenceText = lastTriggeredDangerConfidence.map { String(format: "%.3f", $0) } ?? "-"

        print(
            "[BLE Candidate Trigger] stop iPhone mic danger analysis: \(reason), " +
            "requestID=\(currentTriggeredAnalysisRequestID), " +
            "elapsed=\(String(format: "%.2f", elapsedSeconds)), " +
            "lastAnalyzerLabel=\(lastTriggeredAnalyzerLabel), " +
            "lastAnalyzerConfidence=\(analyzerConfidenceText), " +
            "lastDetectedDanger=\(lastTriggeredDangerLabel), " +
            "lastDetectionConfidence=\(detectionConfidenceText)"
        )
    }

    /// 짧은 위험 소리로 간주해 즉시 종료할 analyzer label인지 판단합니다.
    private func isShortDangerAnalyzerLabel(_ label: String) -> Bool {
        ["car_horn", "vehicle_horn"].contains(label)
    }

    /// 긴 위험 소리 계열로 간주해 window 연장을 허용할 analyzer label인지 판단합니다.
    private func isLongDangerAnalyzerLabel(_ label: String) -> Bool {
        ["siren", "emergency_vehicle", "fire_alarm", "smoke_detector"].contains(label)
    }

    /// 현재 analyzer label에서 window 연장이 가능한지 판단합니다.
    private func canExtendTriggeredAnalysis(for label: String) -> Bool {
        if label == "-" || isLongDangerAnalyzerLabel(label) {
            return true
        }

        return !isShortDangerAnalyzerLabel(label)
    }

    /// analyzer identifier를 BLE 테스트 화면에 표시할 위험 label로 변환합니다.
    private func dangerDisplayLabel(for analyzerLabel: String) -> String {
        switch analyzerLabel {
        case "car_horn", "vehicle_horn":
            return "자동차 경적"
        case "siren", "emergency_vehicle":
            return "사이렌"
        case "fire_alarm", "smoke_detector":
            return "화재 경보"
        default:
            return analyzerLabel
        }
    }

    // MARK: - Audio stream 처리

    /// PCM audio stream 통계와 조립 버퍼를 초기화합니다.
    private func resetAudioStreamStats() {
        audioPacketsReceived = 0
        audioChunksReconstructed = 0
        audioDroppedChunks = 0
        latestAudioChunkSize = 0
        latestAudioSequence = nil
        resetAudioRingBuffer()
        resetBLEAudioAnalysisState()
        audioChunkBuffers.removeAll()
        expectedAudioSequence = nil
    }

    /// binary notify packet을 20ms PCM chunk 단위로 재조립합니다.
    private func handleAudioPacket(_ data: Data) {
        guard let packet = AudioStreamPacket(data: data) else {
            return
        }

        audioPacketsReceived += 1
        latestAudioSequence = packet.sequence
        audioStreamingStateText = "receiving"

        var buffer = audioChunkBuffers[packet.sequence] ?? AudioChunkBuffer(packetCount: packet.packetCount)
        buffer.append(packet)
        audioChunkBuffers[packet.sequence] = buffer

        pruneIncompleteAudioChunks(currentSequence: packet.sequence)

        guard buffer.isComplete, let chunk = buffer.reconstructedData else {
            return
        }

        audioChunkBuffers.removeValue(forKey: packet.sequence)
        updateSequenceGapIfNeeded(completedSequence: packet.sequence)
        audioChunksReconstructed += 1
        latestAudioChunkSize = chunk.count
        appendToAudioRingBuffer(chunk)
    }

    /// 완성된 PCM chunk를 ring buffer에 누적하고 최신 통계를 갱신합니다.
    private func appendToAudioRingBuffer(_ chunk: Data) {
        audioRingBuffer.append(chunk)

        if audioRingBuffer.count > AudioRingBufferFormat.maxBufferBytes {
            audioRingBuffer.removeFirst(audioRingBuffer.count - AudioRingBufferFormat.maxBufferBytes)
        }

        updateAudioRingBufferStats()
        runBLEAudioAnalysisIfNeeded()
    }

    /// PCM ring buffer와 관련 UI 상태를 초기화합니다.
    private func resetAudioRingBuffer() {
        audioRingBuffer.removeAll()
        updateAudioRingBufferStats()
    }

    /// PCM ring buffer 상태를 화면 표시용 값으로 변환합니다.
    private func updateAudioRingBufferStats() {
        audioRingBufferBytes = audioRingBuffer.count
        audioRingBufferDurationSeconds = Double(audioRingBuffer.count) / Double(AudioRingBufferFormat.bytesPerSecond)
        isAudioAnalysisReady = audioRingBuffer.count >= AudioRingBufferFormat.analysisReadyBytes
        estimatedReceivedAudioSeconds = Double(audioChunksReconstructed) * AudioRingBufferFormat.chunkDurationSeconds

        guard isAudioAnalysisReady else {
            resetPCMStatsToZero()
            return
        }

        updatePCMStats()
    }

    /// PCM 통계 표시값을 0으로 초기화합니다.
    private func resetPCMStatsToZero() {
        pcmRMS = 0
        pcmPeak = 0
        pcmZeroCrossingRate = 0
        pcmSampleCount = 0
    }

    /// ring buffer를 Int16 little-endian PCM으로 해석해 lightweight 통계를 갱신합니다.
    private func updatePCMStats() {
        guard audioRingBuffer.count >= AudioRingBufferFormat.analysisReadyBytes else {
            resetPCMStatsToZero()
            return
        }

        let bytes = [UInt8](audioRingBuffer)
        let availableSampleCount = bytes.count / AudioRingBufferFormat.bytesPerSample
        guard availableSampleCount > 0 else {
            resetPCMStatsToZero()
            return
        }

        var sumSquares = 0.0
        var peak = 0
        var zeroCrossingCount = 0
        var previousSample: Int16?

        for sampleIndex in 0..<availableSampleCount {
            guard let sample = pcmInt16Sample(in: bytes, at: sampleIndex) else {
                continue
            }

            let magnitude = abs(Int(sample))

            peak = max(peak, magnitude)
            sumSquares += Double(sample) * Double(sample)

            if let previousSample,
               (previousSample < 0 && sample >= 0) || (previousSample >= 0 && sample < 0) {
                zeroCrossingCount += 1
            }

            previousSample = sample
        }

        pcmSampleCount = availableSampleCount
        pcmPeak = peak
        pcmRMS = Int(sqrt(sumSquares / Double(availableSampleCount)))
        pcmZeroCrossingRate = Double(zeroCrossingCount) / Double(max(availableSampleCount - 1, 1))
    }

    // MARK: - BLE PCM SoundAnalysis 처리

    /// BLE PCM SoundAnalysis 표시 상태를 초기화합니다.
    private func resetBLEAudioAnalysisState() {
        bleAudioAnalysisStatusText = "waiting"
        bleAudioLastClassification = "-"
        bleAudioLastConfidence = nil
        bleAudioLastAnalysisSequence = nil
        bleAudioAnalyzer = nil
        bleAudioAnalysisObserver = nil
        lastBLEAudioAnalysisDate = .distantPast
        bleAudioAnalysisRequestID = 0
        isBLEAudioAnalysisInProgress = false
    }

    /// ring buffer가 충분히 쌓이면 일정 간격으로 SoundAnalysis 실험 분석을 실행합니다.
    private func runBLEAudioAnalysisIfNeeded() {
        guard audioRingBuffer.count >= BLEAudioAnalysisFormat.minimumAnalysisBytes else {
            bleAudioAnalysisStatusText = "waiting for 1.0 sec audio"
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastBLEAudioAnalysisDate) >= BLEAudioAnalysisFormat.analysisIntervalSeconds else {
            return
        }

        guard !isBLEAudioAnalysisInProgress else {
            return
        }

        lastBLEAudioAnalysisDate = now
        bleAudioAnalysisRequestID += 1
        isBLEAudioAnalysisInProgress = true
        let requestID = bleAudioAnalysisRequestID
        bleAudioAnalysisStatusText = "analyzing"

        let bytes = [UInt8](audioRingBuffer)
        let sequence = latestAudioSequence
        let sampleCount = bytes.count / AudioRingBufferFormat.bytesPerSample
        let sequenceText = sequence.map(String.init) ?? "-"
        print("[BLE Audio Analysis] start requestID=\(requestID), bytes=\(bytes.count), samples=\(sampleCount), sampleRate=\(BLEAudioAnalysisFormat.sampleRate), sequence=\(sequenceText)")

        DispatchQueue.main.asyncAfter(deadline: .now() + BLEAudioAnalysisFormat.analysisTimeoutSeconds) { [weak self] in
            guard let self,
                  self.bleAudioAnalysisRequestID == requestID,
                  self.isBLEAudioAnalysisInProgress else {
                return
            }

            print("[BLE Audio Analysis] timeout requestID=\(requestID)")
            self.isBLEAudioAnalysisInProgress = false
            self.bleAudioAnalyzer = nil
            self.bleAudioAnalysisObserver = nil
            self.bleAudioAnalysisStatusText = "timeout waiting for result"
            self.bleAudioLastClassification = "-"
            self.bleAudioLastConfidence = nil
            self.bleAudioLastAnalysisSequence = sequence
        }

        bleAudioAnalysisQueue.async { [weak self] in
            self?.analyzeBLEAudioSnapshot(bytes: bytes, sequence: sequence, requestID: requestID)
        }
    }

    /// BLE PCM ring buffer snapshot을 SoundAnalysis에 전달합니다.
    private func analyzeBLEAudioSnapshot(bytes: [UInt8], sequence: UInt16?, requestID: Int) {
        guard let buffer = makeFloatPCMBuffer(from: bytes) else {
            DispatchQueue.main.async { [weak self] in
                print("[BLE Audio Analysis] buffer conversion failed requestID=\(requestID), bytes=\(bytes.count)")
                self?.isBLEAudioAnalysisInProgress = false
                self?.bleAudioAnalysisStatusText = "buffer conversion failed"
            }
            return
        }

        guard let format = buffer.format as AVAudioFormat? else {
            DispatchQueue.main.async { [weak self] in
                print("[BLE Audio Analysis] invalid buffer format requestID=\(requestID)")
                self?.isBLEAudioAnalysisInProgress = false
                self?.bleAudioAnalysisStatusText = "invalid buffer format"
            }
            return
        }

        do {
            let analyzer = SNAudioStreamAnalyzer(format: format)
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            let observer = BLEAudioAnalysisObserver { [weak self] result in
                DispatchQueue.main.async {
                    self?.applyBLEAudioAnalysisResult(result, sequence: sequence, requestID: requestID)
                }
            }

            try analyzer.add(request, withObserver: observer)
            bleAudioAnalyzer = analyzer
            bleAudioAnalysisObserver = observer
            print("[BLE Audio Analysis] analyzer submitted requestID=\(requestID), formatSampleRate=\(format.sampleRate), channels=\(format.channelCount), frames=\(buffer.frameLength)")
            analyzer.analyze(buffer, atAudioFramePosition: 0)
            analyzer.completeAnalysis()
            print("[BLE Audio Analysis] completeAnalysis called requestID=\(requestID)")
        } catch {
            DispatchQueue.main.async { [weak self] in
                print("[BLE Audio Analysis] setup failed requestID=\(requestID), error=\(error.localizedDescription)")
                self?.isBLEAudioAnalysisInProgress = false
                self?.bleAudioAnalysisStatusText = "analysis setup failed: \(error.localizedDescription)"
            }
        }
    }

    /// Int16 little-endian PCM byte 배열을 SoundAnalysis 입력용 Float32 mono buffer로 변환합니다.
    private func makeFloatPCMBuffer(from bytes: [UInt8]) -> AVAudioPCMBuffer? {
        let sampleCount = bytes.count / AudioRingBufferFormat.bytesPerSample
        guard sampleCount >= BLEAudioAnalysisFormat.minimumAnalysisSampleCount,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: BLEAudioAnalysisFormat.sampleRate,
                channels: 1,
                interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(sampleCount)
              ),
              let channelData = buffer.floatChannelData?[0] else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(sampleCount)

        for sampleIndex in 0..<sampleCount {
            guard let sample = pcmInt16Sample(in: bytes, at: sampleIndex) else {
                continue
            }

            channelData[sampleIndex] = Float(sample) / Float(Int16.max)
        }

        return buffer
    }

    /// SoundAnalysis 실험 결과를 BLE 테스트 화면 상태로 반영합니다.
    private func applyBLEAudioAnalysisResult(_ result: BLEAudioAnalysisResult, sequence: UInt16?, requestID: Int) {
        guard requestID == bleAudioAnalysisRequestID else {
            print("[BLE Audio Analysis] ignore stale result requestID=\(requestID), current=\(bleAudioAnalysisRequestID)")
            return
        }

        let confidenceText: String
        if let confidence = result.confidence {
            confidenceText = String(confidence)
        } else {
            confidenceText = "-"
        }
        print("[BLE Audio Analysis] result requestID=\(requestID), status=\(result.statusText), classification=\(result.classificationIdentifier), confidence=\(confidenceText)")
        isBLEAudioAnalysisInProgress = false
        bleAudioAnalysisStatusText = result.statusText
        bleAudioLastClassification = result.classificationIdentifier
        bleAudioLastConfidence = result.confidence
        bleAudioLastAnalysisSequence = sequence
        bleAudioAnalyzer = nil
        bleAudioAnalysisObserver = nil
    }

    /// byte 배열에서 특정 sample index의 Int16 little-endian 값을 안전하게 읽습니다.
    private func pcmInt16Sample(in bytes: [UInt8], at sampleIndex: Int) -> Int16? {
        let byteIndex = sampleIndex * AudioRingBufferFormat.bytesPerSample
        guard byteIndex >= 0,
              byteIndex + 1 < bytes.count else {
            return nil
        }

        let lowByte = UInt16(bytes[byteIndex])
        let highByte = UInt16(bytes[byteIndex + 1]) << 8
        return Int16(bitPattern: lowByte | highByte)
    }

    /// 오래 남은 미완성 chunk를 누락으로 계산하고 버퍼에서 제거합니다.
    private func pruneIncompleteAudioChunks(currentSequence: UInt16) {
        let staleSequences = audioChunkBuffers.keys.filter { sequence in
            currentSequence > sequence && currentSequence - sequence > 2
        }

        audioDroppedChunks += staleSequences.count
        staleSequences.forEach { audioChunkBuffers.removeValue(forKey: $0) }
    }

    /// 완성된 sequence 사이의 gap을 dropped chunk로 계산합니다.
    private func updateSequenceGapIfNeeded(completedSequence: UInt16) {
        guard let expectedAudioSequence else {
            self.expectedAudioSequence = completedSequence &+ 1
            return
        }

        if completedSequence > expectedAudioSequence {
            audioDroppedChunks += Int(completedSequence - expectedAudioSequence)
        }

        self.expectedAudioSequence = completedSequence &+ 1
    }
}

// MARK: - LissenceBLEManagerDelegate

extension BLETestViewModel: LissenceBLEManagerDelegate {
    /// Bluetooth 권한과 전원 상태를 ViewModel 상태로 반영합니다.
    func bleManager(_ manager: LissenceBLEManager, didUpdateBluetoothState stateText: String) {
        bluetoothStateText = stateText
    }

    /// BLE 작업 진행 상태를 ViewModel 상태로 반영합니다.
    func bleManager(_ manager: LissenceBLEManager, didUpdateStatus statusText: String) {
        self.statusText = statusText
    }

    /// ESP32 연결 상태를 ViewModel 상태로 반영합니다.
    func bleManager(_ manager: LissenceBLEManager, didUpdateConnection isConnected: Bool) {
        self.isConnected = isConnected
    }

    /// 발견한 Peripheral 이름을 ViewModel 상태로 반영합니다.
    func bleManager(_ manager: LissenceBLEManager, didDiscoverDeviceName deviceName: String) {
        discoveredDeviceName = deviceName
    }

    /// ESP32에서 받은 notify/read 메시지를 ViewModel 상태로 반영합니다.
    func bleManager(_ manager: LissenceBLEManager, didReceive message: LissenceBLEMessage) {
        lastReceivedMessage = message.text
        updateMicLevelIfNeeded(from: message.text)
        updateAudioCandidateIfNeeded(from: message.text)
    }

    /// ESP32에서 받은 PCM audio stream binary packet을 재조립 통계에 반영합니다.
    func bleManager(_ manager: LissenceBLEManager, didReceiveAudioPacket data: Data) {
        handleAudioPacket(data)
    }

    /// ESP32로 보낸 메시지를 ViewModel 상태로 반영합니다.
    func bleManager(_ manager: LissenceBLEManager, didSend message: LissenceBLEMessage) {
        lastSentMessage = message.text
    }
}

// MARK: - Candidate triggered analysis configuration

/// BLE 후보 기반 iPhone 마이크 분석 정책 모드입니다.
private enum TriggeredAnalysisMode {
    /// 데모 중 짧은 반복 트리거를 확인하기 위한 설정입니다.
    case demo

    /// 실사용에 가까운 긴 분석 window와 cooldown 설정입니다.
    case production
}

/// BLE 후보 기반 iPhone 마이크 분석 window와 cooldown 설정입니다.
private struct TriggeredAnalysisConfiguration {
    /// 현재 적용된 정책 모드입니다.
    let mode: TriggeredAnalysisMode

    /// 후보 수신 후 최초 분석 window입니다.
    let baseWindowSeconds: Double

    /// 분석 중 추가 후보 수신 시 연장할 window입니다.
    let extensionSeconds: Double

    /// 분석 window 최대값입니다.
    let maxWindowSeconds: Double

    /// 분석 종료 후 다음 후보를 무시할 시간입니다.
    let cooldownSeconds: Double

    /// 정책 모드에 맞는 설정을 생성합니다.
    init(mode: TriggeredAnalysisMode) {
        self.mode = mode

        switch mode {
        case .demo:
            baseWindowSeconds = 4.0
            extensionSeconds = 1.0
            maxWindowSeconds = 4.0
            cooldownSeconds = 1.0
        case .production:
            baseWindowSeconds = 3.0
            extensionSeconds = 1.0
            maxWindowSeconds = 5.0
            cooldownSeconds = 6.0
        }
    }
}

// MARK: - Audio stream packet

/// ESP32 PCM audio stream binary packet 규격입니다.
private enum AudioStreamPacketFormat {
    /// ESP32 firmware의 audio packet payload 최대 byte 크기입니다.
    static let maxAudioPacketPayloadSize = 160
}

/// 16kHz / 16-bit mono PCM ring buffer 규격입니다.
private enum AudioRingBufferFormat {
    /// 16-bit PCM sample 하나의 byte 수입니다.
    static let bytesPerSample = 2

    /// 16kHz, 16-bit mono 기준 1초 PCM byte 수입니다.
    static let bytesPerSecond = 32_000

    /// ring buffer에 보관할 최대 PCM byte 수입니다.
    static let maxBufferBytes = 64_000

    /// 분석 가능 상태로 볼 최소 PCM byte 수입니다.
    static let analysisReadyBytes = 16_000

    /// ESP32에서 전송하는 PCM chunk 1개의 audio 길이입니다.
    static let chunkDurationSeconds = 0.02
}

/// BLE PCM SoundAnalysis 실험 입력 규격입니다.
private enum BLEAudioAnalysisFormat {
    /// ESP32 BLE PCM stream의 현재 sample rate입니다.
    static let sampleRate = 16_000.0

    /// SoundAnalysis 실험을 시도할 최소 audio 길이입니다.
    static let minimumAnalysisSeconds = 1.0

    /// 분석 시도 간격입니다.
    static let analysisIntervalSeconds = 0.75

    /// SoundAnalysis callback을 기다릴 최대 시간입니다.
    static let analysisTimeoutSeconds = 2.0

    /// 분석을 시도할 최소 PCM byte 수입니다.
    static let minimumAnalysisBytes = Int(sampleRate * minimumAnalysisSeconds) * AudioRingBufferFormat.bytesPerSample

    /// 분석을 시도할 최소 sample 수입니다.
    static let minimumAnalysisSampleCount = Int(sampleRate * minimumAnalysisSeconds)
}

/// BLE PCM SoundAnalysis 실험 결과입니다.
private struct BLEAudioAnalysisResult {
    /// 분석 상태 문구입니다.
    let statusText: String

    /// 최근 classification identifier입니다.
    let classificationIdentifier: String

    /// 최근 classification confidence입니다.
    let confidence: Double?
}

/// BLE PCM SoundAnalysis 결과를 ViewModel에 전달하는 observer입니다.
private final class BLEAudioAnalysisObserver: NSObject, SNResultsObserving {
    /// 분석 결과를 전달할 closure입니다.
    private let onResult: (BLEAudioAnalysisResult) -> Void

    /// classification result를 받은 적이 있는지 여부입니다.
    private var didProduceResult = false

    /// observer를 생성합니다.
    init(onResult: @escaping (BLEAudioAnalysisResult) -> Void) {
        self.onResult = onResult
    }

    /// SoundAnalysis classification 결과를 처리합니다.
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult,
              let classification = result.classifications.max(by: { $0.confidence < $1.confidence }) else {
            print("[BLE Audio Analysis] didProduce without classification")
            onResult(BLEAudioAnalysisResult(
                statusText: "no classification",
                classificationIdentifier: "-",
                confidence: nil
            ))
            return
        }

        didProduceResult = true
        print("[BLE Audio Analysis] didProduce classification=\(classification.identifier), confidence=\(classification.confidence), count=\(result.classifications.count)")
        onResult(BLEAudioAnalysisResult(
            statusText: "classified",
            classificationIdentifier: classification.identifier,
            confidence: classification.confidence
        ))
    }

    /// SoundAnalysis 오류를 처리합니다.
    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("[BLE Audio Analysis] didFail error=\(error.localizedDescription)")
        onResult(BLEAudioAnalysisResult(
            statusText: "analysis failed: \(error.localizedDescription)",
            classificationIdentifier: "-",
            confidence: nil
        ))
    }

    /// SoundAnalysis 요청 완료를 처리합니다.
    func requestDidComplete(_ request: SNRequest) {
        print("[BLE Audio Analysis] requestDidComplete didProduceResult=\(didProduceResult)")
        guard !didProduceResult else {
            return
        }

        onResult(BLEAudioAnalysisResult(
            statusText: "completed without result",
            classificationIdentifier: "-",
            confidence: nil
        ))
    }
}

/// ESP32 PCM audio stream binary notify packet입니다.
private struct AudioStreamPacket {
    /// 20ms PCM chunk sequence입니다.
    let sequence: UInt16

    /// chunk 내부 packet index입니다.
    let packetIndex: Int

    /// chunk를 구성하는 전체 packet 수입니다.
    let packetCount: Int

    /// packet에 포함된 PCM payload입니다.
    let payload: Data

    /// binary packet header를 해석해 audio stream packet을 생성합니다.
    init?(data: Data) {
        guard data.count >= 7,
              data[0] == 0xA1 else {
            return nil
        }

        let payloadSize = Int(data[5]) | (Int(data[6]) << 8)
        guard payloadSize > 0,
              payloadSize <= AudioStreamPacketFormat.maxAudioPacketPayloadSize,
              data.count == 7 + payloadSize else {
            return nil
        }

        self.sequence = UInt16(data[1]) | (UInt16(data[2]) << 8)
        self.packetIndex = Int(data[3])
        self.packetCount = Int(data[4])
        self.payload = data.subdata(in: 7..<data.count)

        guard packetCount > 0,
              packetIndex >= 0,
              packetIndex < packetCount else {
            return nil
        }
    }
}

/// sequence 하나에 속한 여러 binary packet을 PCM chunk로 조립하는 버퍼입니다.
private struct AudioChunkBuffer {
    /// chunk를 구성하는 전체 packet 수입니다.
    let packetCount: Int

    /// packet index별 PCM payload입니다.
    private var payloads: [Int: Data] = [:]

    /// 필요한 packet 수로 빈 chunk 조립 버퍼를 생성합니다.
    init(packetCount: Int) {
        self.packetCount = packetCount
    }

    /// 모든 packet을 수신했는지 여부입니다.
    var isComplete: Bool {
        payloads.count == packetCount
    }

    /// packet index 순서대로 결합한 PCM chunk입니다.
    var reconstructedData: Data? {
        guard isComplete else {
            return nil
        }

        return (0..<packetCount).reduce(into: Data()) { result, index in
            if let payload = payloads[index] {
                result.append(payload)
            }
        }
    }

    /// 수신한 packet을 버퍼에 저장합니다.
    mutating func append(_ packet: AudioStreamPacket) {
        guard packet.packetCount == packetCount else {
            return
        }

        payloads[packet.packetIndex] = packet.payload
    }
}
