/// 소리 분석 핵심 엔진 (가장 중요)

import SoundAnalysis
import WatchKit
import Foundation
import Combine
import AVFoundation
import CoreMedia

class SoundClassifier: NSObject, ObservableObject {

    private var audioEngine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private var request: SNClassifySoundRequest?
    private let analysisQueue = DispatchQueue(label: "SoundAnalysisQueue")
    /// 워치 화면이 꺼져도 감지를 유지
    private var extendedSession: WKExtendedRuntimeSession?

    @Published var isRunning = false
    @Published var detectedSound: DangerSound = .unknown
    @Published var confidence: Double = 0

    var onDangerDetected: ((DangerSound, Double) -> Void)?

    // 신뢰도 임계값 (이 이상일 때만 반응)
    var confidenceThreshold: Double = 0.6

    // MARK: - 시작
    func start() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard granted else {
                print("마이크 권한 거부됨")
                return
            }
            DispatchQueue.main.async {
                // Extended Runtime Session 시작 (watchOS 백그라운드 유지)
                self?.extendedSession = WKExtendedRuntimeSession()
                self?.extendedSession?.start()
                self?.startEngine()
            }
        }
    }

    private func startEngine() {
    // [수정] 기존 엔진의 실행 여부를 확인하고, 탭(Tap) 중복 연결로 인한 크래시를 방지하기 위해 정지 및 제거 로직 추가
    if audioEngine.isRunning {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    do {
        let audioSession = AVAudioSession.sharedInstance()
        // [수정] 단순 녹음(.record)에서 측정 모드(.measurement)와 타 앱 소리 감소(duckOthers) 옵션을 추가하여 오디오 분석 안정성 강화
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true)
        
        let inputNode = audioEngine.inputNode
        // [수정] 하드웨어 입력을 그대로 쓰는 대신, 분석기에 최적화된 출력 포맷(outputFormat)을 사용하여 호환성 문제 해결
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        analyzer = SNAudioStreamAnalyzer(format: recordingFormat)
        request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        try analyzer?.add(request!, withObserver: self)
        
        // [수정] 버퍼 사이즈를 8192로 확장하여 watchOS의 제한된 자원 환경에서 오버플로우 및 연산 부하로 인한 튕김 현상 방지
        inputNode.installTap(onBus: 0, bufferSize: 8192, format: recordingFormat) { [weak self] buffer, time in
            self?.analysisQueue.async {
                self?.analyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
            }
        }
        
        // [수정] 엔진 시작(start) 전 prepare()를 명시적으로 호출하여 시스템 자원을 미리 할당받음으로써 실행 시점 크래시 예방
        audioEngine.prepare()
        try audioEngine.start()
        
        DispatchQueue.main.async {
            self.isRunning = true
        }
    } catch {
        print("엔진 시작 실패: \(error.localizedDescription)")
    }
}

    // MARK: - 중지
    func stop() {
        extendedSession?.invalidate()
        extendedSession = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        analyzer?.removeAllRequests()
        try? AVAudioSession.sharedInstance().setActive(false)

        DispatchQueue.main.async {
            self.isRunning = false
            self.detectedSound = .unknown
            self.confidence = 0
        }
    }
}

// MARK: - SNResultsObserving
extension SoundClassifier: SNResultsObserving {

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let sorted = result.classifications.sorted { $0.confidence > $1.confidence }

        for classification in sorted {
            guard classification.confidence >= confidenceThreshold else { break }
            
            // [수정] 하드코딩 제거
            if let soundType = DangerSound.from(identifier: classification.identifier) {
                DispatchQueue.main.async { [weak self] in
                    self?.detectedSound = soundType
                    self?.confidence = classification.confidence
                    self?.onDangerDetected?(soundType, classification.confidence)
                }
            }
            return
        }

        // 아무것도 감지 못했을 때
        DispatchQueue.main.async { [weak self] in
            self?.detectedSound = .unknown
            self?.confidence = 0
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("분류 오류: \(error)")
    }
}
