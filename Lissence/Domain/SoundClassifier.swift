/// 애플워치용 소리 분석 엔진
/// 소리 분석 핵심 엔진 (가장 중요)
/// - 상태 체크와 충돌 방지 지연 추가
/// - 저전력 솔루션
///     - A : 임계값 조절(데시벨)
///     - C : 저전력 모드일때 2번에 한번 분석 + 임계값 더 높게 설정 (마이너스라 0이 가장 큰 소리에요!)
///         - 저전력 : - 35dB (큰 소리)부터 감지
///         - 일반: -45dB (작은 소리)부터 감지

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

    /// 가장 최근에 분류된 위험 소리가 실제 마이크에 도달한 시각입니다.
    @Published var detectedAt: Date?

    /// 첫 오디오 버퍼의 sampleTime 기준점입니다.
    private var firstSampleTime: AVAudioFramePosition?
    /// 첫 오디오 버퍼가 들어온 실제 시각(Unix epoch ms)입니다.
    private var firstSampleTimestampMs: Double = 0
    
    // [솔루션 C 관련 설정값]
    private var isLowPowerMode: Bool {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    // [설정 임계값]
    private let confidenceThreshold: Double = 0.6
    
    // 상황별 데시벨 임계값 (솔루션 A + C)
    private var dbThreshold: Float {
        // 일반: -45dB (냉장고 소음 수준), 저전력: -35dB (일반 대화 수준)
        return isLowPowerMode ? -35.0 : -45.0
    }
    
    // 분석 스킵 주기 (저전력 모드 시 2번에 1번만 분석)
    private var analysisCounter = 0

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
    firstSampleTime = nil
    firstSampleTimestampMs = 0

    do {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try analyzer?.add(request, withObserver: self)
            
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, time in
                guard let self = self else { return }

                if self.firstSampleTime == nil {
                    self.firstSampleTime = time.sampleTime
                    self.firstSampleTimestampMs = Date().timeIntervalSince1970 * 1000
                }
                
                // 1. [솔루션 A] 데시벨 계산
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameLength = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frameLength { sum += channelData[i] * channelData[i] }
                let rms = sqrt(sum / Float(frameLength))
                let decibels = 20 * log10(max(rms, 0.000001))

                // 2. [솔루션 A + C 결합 로직]
                if decibels > self.dbThreshold {
                    if self.isLowPowerMode {
                        // 저전력 모드일 때 2번에 1번 분석 (솔루션 C)
                        self.analysisCounter += 1
                        if self.analysisCounter % 2 == 0 {
                            self.runAnalysis(buffer: buffer, time: time)
                        }
                    } else {
                        // 일반 모드일 때는 모든 유의미한 소리 분석
                        self.runAnalysis(buffer: buffer, time: time)
                    }
                }
            }
                    
            audioEngine.prepare()
            try audioEngine.start()
            DispatchQueue.main.async { self.isRunning = true }
    } catch {
        print("엔진 시작 에러: \(error)")
        stop() // 실패 시 자원 정리
    }
}
    
    // MARK: - 분석 함수
    private func runAnalysis(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        self.analysisQueue.async {
            // 분석 실행
            self.analyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
        }
    }
    
    // MARK: - 중지 제어 (자원 해제 필수)
    func stop() {
        if audioEngine.isRunning { audioEngine.stop()}
        audioEngine.inputNode.removeTap(onBus: 0)
        analyzer?.removeAllRequests()
        // 세션 비활성화로 자원 반납
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        extendedSession?.invalidate()
        DispatchQueue.main.async {
            self.isRunning = false
            self.detectedSound = .unknown
            self.detectedAt = nil
        }
        firstSampleTime = nil
        firstSampleTimestampMs = 0
    }
}

// MARK: - SNResultsObserving 채택
extension SoundClassifier: SNResultsObserving {
    
    /// 소리 분석 결과가 나올 때마다 호출되는 함수
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }

        let sourceTimeRange = result.timeRange
        let startSamplePosition = sourceTimeRange.start.value
        let timescale = Double(sourceTimeRange.start.timescale)
        var preciseTimestampMs = Date().timeIntervalSince1970 * 1000

        if let firstSample = firstSampleTime,
           firstSampleTimestampMs > 0,
           timescale > 0 {
            let sampleOffset = Double(startSamplePosition - firstSample)
            let audioOffsetInMs = sampleOffset / timescale * 1000
            preciseTimestampMs = firstSampleTimestampMs + audioOffsetInMs
        }
        
        // 신뢰도 순으로 순회하며 앱에서 허용하는 위험 감지 항목을 채택합니다.
        let sorted = result.classifications.sorted { $0.confidence > $1.confidence }

        for classification in sorted {
            guard classification.confidence >= confidenceThreshold else { break }

            if let soundType = DangerSound.from(identifier: classification.identifier) {
                let preciseDate = Date(timeIntervalSince1970: preciseTimestampMs / 1000)
                // ViewModel이 보고 있는 변수 업데이트
                DispatchQueue.main.async {
                    self.detectedAt = preciseDate
                    self.detectedSound = soundType
                    print("🎯 오차 없는 물리 타임스탬프 추출 성공 (ts): \(Int64(preciseTimestampMs))")
                }
                return
            }
        }

        // 감지된 소리가 없거나 앱에서 제외한 항목만 있으면 unknown으로 초기화
        DispatchQueue.main.async { self.detectedSound = .unknown }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("분류 오류: \(error.localizedDescription)")
        self.stop()
    }
    
    func requestDidComplete(_ request: SNRequest) {
        // 분석 완료 시 로직 (필요 시)
    }
}
