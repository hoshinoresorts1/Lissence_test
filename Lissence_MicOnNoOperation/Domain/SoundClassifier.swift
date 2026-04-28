/// 애플워치용 소리 분석 엔진
/// 소리 분석 핵심 엔진 (가장 중요)
/// - 상태 체크와 충돌 방지 지연 추가

import SoundAnalysis
import WatchKit
import Foundation
import Combine
import AVFoundation


class SoundClassifier: NSObject, ObservableObject {

    private var audioEngine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private var request: SNClassifySoundRequest?
    private let analysisQueue = DispatchQueue(label: "com.Lissence.AnalysisQueue")
    private var extendedSession: WKExtendedRuntimeSession?

    @Published var isRunning = false
    @Published var detectedSound: DangerSound = .unknown

    // 신뢰도 임계값은 내부에서 상수로 관리하거나 설정 가능하게 유지
    var confidenceThreshold: Double = 0.6

    // MARK: - 시작 제어
    func start() {
        // 이미 실행 중이면 중복 실행 방지
        guard !audioEngine.isRunning else { return }
        
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard granted else {
                print("마이크 권한 거부됨")
                return
            }
            
            // 오디오 엔진 시작 전 세션 설정
            self?.configureAudioSession()
            
            DispatchQueue.main.async {
                // Extended Runtime Session 시작 (watchOS 백그라운드 유지)
                self?.extendedSession = WKExtendedRuntimeSession()
                self?.extendedSession?.start()
                
                // 엔진 시작 시점에 0.1초의 짧은 지연을 주어 시스템 자원 확보
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.startEngine()
                }
            }
        }
    }
    
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // watchOS에 최적화된 카테고리 설정
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("오디오 세션 활성화 실패: \(error)")
        }
    }

    private func startEngine() {
    // 탭(Tap) 중복 방지를 위한 사전 제거
    audioEngine.inputNode.removeTap(onBus: 0)
            
    let inputNode = audioEngine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)
    analyzer = SNAudioStreamAnalyzer(format: recordingFormat)

    do {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try analyzer?.add(request, withObserver: self)
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, time in
                self?.analysisQueue.async {
                    self?.analyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
                }
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            DispatchQueue.main.async {
                self.isRunning = true
            }
    } catch {
        print("엔진 시작 에러: \(error)")
        stop() // 실패 시 자원 정리
    }
}

    // MARK: - 중지 제어 (자원 해제 필수)
    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        analyzer?.removeAllRequests()
        
        // 세션 비활성화로 자원 반납
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        
        extendedSession?.invalidate()
        
        DispatchQueue.main.async {
            self.isRunning = false
            self.detectedSound = .unknown
        }
    }
}

// MARK: - SNResultsObserving 채택
extension SoundClassifier: SNResultsObserving {
    
    /// 소리 분석 결과가 나올 때마다 호출되는 함수 (삭제되었던 request 함수 복구)
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        
        // 가장 신뢰도가 높은 결과 추출
        if let classification = result.classifications.sorted(by: { $0.confidence > $1.confidence }).first {
            
            // 임계값보다 높고, 정의된 위험 소리인 경우
            if classification.confidence >= confidenceThreshold,
               let soundType = DangerSound.from(identifier: classification.identifier) {
                
                DispatchQueue.main.async {
                    // ViewModel이 보고 있는 변수 업데이트
                    self.detectedSound = soundType
                }
            } else {
                // 감지된 소리가 없거나 신뢰도가 낮으면 unknown으로 초기화
                DispatchQueue.main.async {
                    self.detectedSound = .unknown
                }
            }
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("분류 오류: \(error.localizedDescription)")
        self.stop()
    }
    
    func requestDidComplete(_ request: SNRequest) {
        // 분석 완료 시 로직 (필요 시)
    }
}
