/// 아이폰용 소리 분석 엔진
/// 감지 모드에서 위험 소리 분류를 수행하는 로직의 코드입니다.
/// - 애플의 SoundAnalysis를 사용하여 감지모드에서 소리의 종류를 인식합니다.

import Foundation
import SoundAnalysis
import AVFoundation
import Combine

class SoundDetector: NSObject, SNResultsObserving, ObservableObject {
    private let audioEngine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private let analysisQueue = DispatchQueue(label: "com.Lissence.AnalysisQueue")
    private var isStartingDetection = false
    
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
                self?.analysisQueue.async {
                    self?.analyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
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
    }

    /// 소리 분석 처리 함수
    func request(_ request: SNRequest, didProduce result: SNResult) {
        print("[SoundDetector] didProduce result")
        guard let result = result as? SNClassificationResult else { return }
        
        // 1. 신뢰도 순 정렬 및 임계값 체크
        let sorted = result.classifications.sorted { $0.confidence > $1.confidence }

        if let topClassification = sorted.first {
            let candidates = sorted
                .prefix(3)
                .map { "\($0.identifier)=\(String(format: "%.3f", $0.confidence))" }
                .joined(separator: ", ")
            print("[SoundDetector] classification candidates: \(candidates)")

            DispatchQueue.main.async {
                self.lastAnalyzerClassificationIdentifier = topClassification.identifier
                self.lastAnalyzerClassificationConfidence = topClassification.confidence
                print("[SoundDetector] lastAnalyzerLabel updated: \(topClassification.identifier), confidence=\(topClassification.confidence)")
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
                    self.sendDangerAlert(sound: sound)
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

    private func sendDangerAlert(sound: DangerSound) {
        let message = MessageData(
            title: sound.label, iconName: sound.icon, isDanger: sound.isDanger
        )
        ConnectivityManager.shared.send(message: message)
    }
}
