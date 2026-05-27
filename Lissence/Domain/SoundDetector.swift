/// 아이폰용 소리 분석 엔진
/// 감지 모드에서 위험 소리 분류를 수행하는 로직의 코드입니다.
/// - 애플의 SoundAnalysis를 사용하여 감지모드에서 소리의 종류를 인식합니다.
/// - SoundAnalysis window 시작 시각을 실제 마이크 도달 시각으로 환산해 ESP32에 전달합니다.

import Foundation
import SoundAnalysis
import AVFoundation
import Combine

class SoundDetector: NSObject, SNResultsObserving, ObservableObject {
    private let audioEngine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private let analysisQueue = DispatchQueue(label: "com.Lissence.AnalysisQueue")
    private var isStartingDetection = false
    /// 첫 오디오 버퍼의 sampleTime 기준점입니다.
    private var firstSampleTime: AVAudioFramePosition?
    /// 첫 오디오 버퍼가 들어온 실제 시각(Unix epoch ms)입니다.
    private var firstSampleTimestampMs: Double = 0
    private var audioBufferLogCount = 0
    private let speechActivityConfidenceThreshold = 0.50
    private var dangerEvalExpectedLabel: String? {
        let launchArgumentValue = UserDefaults.standard.string(forKey: "DangerEvalExpected")
        let environmentValue = ProcessInfo.processInfo.environment["DANGER_EVAL_EXPECTED"]
        let rawValue = launchArgumentValue ?? environmentValue
        let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }

    /// SoundAnalysis가 speech를 감지했을 때 호출어 STT 게이트를 열기 위한 이벤트입니다.
    let speechActivity = PassthroughSubject<Double, Never>()
    
    // UI에서 현재 어떤 소리가 들리는지 보여줄 변수
    @Published var statusText: String = "주변 소리 분석 중..."
    @Published var lastDetectedSound: String = ""
    /// 마지막으로 위험 소리로 채택된 DangerSound입니다.
    @Published var lastDetectedDangerSound: DangerSound?
    /// 마지막으로 위험 소리로 채택된 분류 결과의 confidence입니다.
    @Published var lastDetectionConfidence: Double?
    /// SoundAnalysis가 마지막으로 반환한 최상위 classification identifier입니다.
    @Published var lastAnalyzerClassificationIdentifier: String = "-"
    /// SoundAnalysis가 마지막으로 반환한 최상위 classification confidence입니다.
    @Published var lastAnalyzerClassificationConfidence: Double?
    @Published var isDetecting: Bool = false

    /// 소리 감지 엔진이 실행 중이거나 시작 준비 중인지 나타냅니다.
    var isRunning: Bool {
        isStartingDetection || audioEngine.isRunning || isDetecting
    }

    func startDetection() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.startDetection()
            }
            return
        }

        print("SoundDetector startDetection called")

        guard !isRunning else {
            print("SoundDetector already running, skip start")
            return
        }

        isStartingDetection = true
        lastDetectedSound = ""
        lastDetectedDangerSound = nil
        lastDetectionConfidence = nil
        lastAnalyzerClassificationIdentifier = "-"
        lastAnalyzerClassificationConfidence = nil
        firstSampleTime = nil
        firstSampleTimestampMs = 0
        audioBufferLogCount = 0

        let audioSession = AVAudioSession.sharedInstance()
        do {
            // 모드를 .default 또는 .videoRecording 등으로 변경하여 더 넓은 대역폭 확보
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            isStartingDetection = false
            print("오디오 세션 설정 실패: \(error.localizedDescription)")
            return
        }

        // 2. 분석기(Analyzer) 설정
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        analyzer = SNAudioStreamAnalyzer(format: recordingFormat)
        
        do {
            // 3. Apple 제공 시스템 분류기 설정 (.version1 사용)
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try analyzer?.add(request, withObserver: self)
            print("[SoundDetector] analyzer request started")
            
            // 4. 마이크 입력을 분석기로 전달 (Tap 설치)
            inputNode.installTap(onBus: 0, bufferSize: 8000, format: recordingFormat) { [weak self] buffer, time in
                guard let self else { return }

                if self.firstSampleTime == nil {
                    self.firstSampleTime = time.sampleTime
                    self.firstSampleTimestampMs = Date().timeIntervalSince1970 * 1000
                    print("🎯 [SoundDetector] timeline anchor set: sampleTime=\(time.sampleTime), epochMs=\(self.firstSampleTimestampMs)")
                }

                self.audioBufferLogCount += 1
                if self.audioBufferLogCount == 1 || self.audioBufferLogCount % 100 == 0 {
                    print("[SoundDetector] audio buffer received count=\(self.audioBufferLogCount)")
                }

                self.analysisQueue.async {
                    self.analyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
                }
            }
            
            try audioEngine.start()
            isStartingDetection = false
            isDetecting = true
            print("[SoundDetector] audio engine started")
        } catch {
            isStartingDetection = false
            analyzer = nil
            print("감지 시작 실패: \(error)")
        }
    }

    func stopDetection() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.stopDetection()
            }
            return
        }

        print("SoundDetector stopDetection called")

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioEngine.reset()
        analyzer?.removeAllRequests()
        analyzer = nil
        isStartingDetection = false
        isDetecting = false
        firstSampleTime = nil
        firstSampleTimestampMs = 0
        audioBufferLogCount = 0
    }

    /// 소리 분석 처리 함수
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        print("[SoundDetector] analyzer callback alive")
        let classifiedAt = preciseClassificationDate(for: result)

        // 1. 신뢰도 순 정렬 및 임계값 체크
        let sorted = result.classifications.sorted { $0.confidence > $1.confidence }

        if let topClassification = sorted.first {
            let top3 = sorted
                .prefix(3)
                .map { "\($0.identifier)(\(Int($0.confidence * 100))%)" }
                .joined(separator: ", ")
            print("🎧 [SoundDetector] top3: \(top3)")

            if let speechClassification = sorted.prefix(3).first(where: { classification in
                classification.identifier.lowercased().contains("speech") &&
                    classification.confidence >= speechActivityConfidenceThreshold
            }) {
                DispatchQueue.main.async {
                    self.speechActivity.send(speechClassification.confidence)
                }
            }

            DispatchQueue.main.async {
                self.lastAnalyzerClassificationIdentifier = topClassification.identifier
                self.lastAnalyzerClassificationConfidence = topClassification.confidence
            }
        }

        for classification in sorted {
            guard classification.confidence > 0.6 else { break }

        // 2. [핵심] 공통 모델에서 소리 타입을 가져옴
            if let sound = DangerSound.from(identifier: classification.identifier) {
                // 3. 개별 인자를 넘기지 않고 sound 객체 하나만 넘김
                DispatchQueue.main.async {
                    self.lastDetectedSound = sound.label
                    self.lastDetectedDangerSound = sound
                    self.lastDetectionConfidence = classification.confidence
                    let latencyMs = Date().timeIntervalSince(classifiedAt) * 1000
                    print("🚨 [SoundDetector] DANGER detected: \(sound.label) "
                        + "(conf=\(String(format: "%.3f", classification.confidence)), "
                        + "classifier_latency=\(String(format: "%.0f", latencyMs))ms)")
                    print("🎯 [SoundDetector] precise timestamp ms=\(Int64(classifiedAt.timeIntervalSince1970 * 1000))")
                    self.logDangerEvaluation(
                        predicted: sound.rawValue,
                        confidence: classification.confidence
                    )
                    self.sendDangerAlert(sound: sound, classifiedAt: classifiedAt)
                }
                return
            }
        }
    }

    /// 소리 분석 실패를 로그로 남깁니다.
    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("[SoundDetector] didFail error=\(error.localizedDescription)")
    }

    /// 소리 분석 요청 완료를 로그로 남깁니다.
    func requestDidComplete(_ request: SNRequest) {
        print("[SoundDetector] requestDidComplete")
    }

    /// 발표/실험용 위험음 정확도 평가 로그입니다.
    /// Xcode Scheme launch argument `-DangerEvalExpected carHorn` 또는
    /// environment `DANGER_EVAL_EXPECTED=carHorn`으로 expected label을 지정합니다.
    private func logDangerEvaluation(predicted: String, confidence: Double) {
        guard let expected = dangerEvalExpectedLabel else {
            return
        }

        let result = expected == predicted ? "correct" : "wrong"
        print(
            "[DangerEval] expected=\(expected) "
            + "predicted=\(predicted) "
            + "conf=\(String(format: "%.2f", confidence)) "
            + "result=\(result)"
        )
    }

    /// SoundAnalysis 결과가 가리키는 실제 분석 window 시작 시각을 Date 기준으로 역산합니다.
    private func preciseClassificationDate(for result: SNClassificationResult) -> Date {
        guard let firstSampleTime,
              firstSampleTimestampMs > 0,
              result.timeRange.start.timescale > 0 else {
            return Date()
        }

        let sampleOffset = Double(result.timeRange.start.value - firstSampleTime)
        let audioOffsetMs = sampleOffset / Double(result.timeRange.start.timescale) * 1000
        let timestampMs = firstSampleTimestampMs + audioOffsetMs

        return Date(timeIntervalSince1970: timestampMs / 1000)
    }

    /// 위험 소리 분류 결과를 Apple Watch와 ESP32 양쪽으로 전달합니다.
    /// - Parameters:
    ///   - sound: 분류된 위험 소리 유형.
    ///   - classifiedAt: 실제 마이크에 소리가 도달한 시각. ESP32 ring buffer 매칭에 사용됩니다.
    private func sendDangerAlert(sound: DangerSound, classifiedAt: Date) {
        // 1) Apple Watch 알림 (선택 기능 — Watch 미사용 환경이라면 이 두 줄을 주석 처리)
        let message = MessageData(
            title: sound.label,
            iconName: sound.icon,
            isDanger: sound.isDanger,
            dangerSoundRawValue: sound.rawValue
        )
        print("⌚️ [WatchAlert] send danger=\(sound.rawValue)")
        ConnectivityManager.shared.send(message: message)

        // 2) ESP32 햅틱 명령 (가이드 §0 핵심 경로: 분류 시각 ts와 분석 윈도 win을 함께 전송)
        guard let pattern = sound.hapticPattern else {
            print("ℹ️ [SoundDetector] BLE write skipped: \(sound.label)에 매핑된 hapticPattern 없음")
            return
        }

        LissenceBLEManager.shared.writeHapticPattern(pattern, classifiedAt: classifiedAt)
    }
}
