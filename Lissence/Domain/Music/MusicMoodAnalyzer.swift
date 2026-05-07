/// 마이크 window, feature 추출, CoreML 분류를 조합해 음악 무드 분석 파이프라인을 제공합니다.

import Foundation

/// 음악 무드 분석 중 발생하는 상태 변화를 외부에 전달합니다.
protocol MusicMoodAnalyzerDelegate: AnyObject {
    /// 분석 상태 문구가 변경되었을 때 호출됩니다.
    func musicMoodAnalyzer(_ analyzer: MusicMoodAnalyzer, didUpdateStatus status: String)

    /// 새로운 무드 분석 결과가 도출되었을 때 호출됩니다.
    func musicMoodAnalyzer(_ analyzer: MusicMoodAnalyzer, didUpdatePrediction prediction: MusicMoodPrediction)

    /// 분석 중 복구 불가능한 오류가 발생했을 때 호출됩니다.
    func musicMoodAnalyzer(_ analyzer: MusicMoodAnalyzer, didFail error: Error)
}

/// 음악 모드에서 사용하는 CoreML 기반 실시간 무드 분석기입니다.
final class MusicMoodAnalyzer {
    // MARK: - 속성

    /// 분석 결과를 전달받는 delegate입니다.
    weak var delegate: MusicMoodAnalyzerDelegate?

    /// 마이크 window recorder입니다.
    private let recorder: MusicAudioWindowRecorder

    /// 오디오 feature extractor입니다.
    private let extractor: AudioFeatureExtractor

    /// CoreML classifier입니다.
    private var classifier: MusicMoodModelClassifier?

    /// 최근 window 확률을 평균내기 위한 저장소입니다.
    private var windows: [[MusicMood: Double]] = []

    /// 파이프라인 실행 식별자입니다.
    private var runId = UUID()

    /// 현재 window 분석 중인지 여부입니다.
    private var isProcessingWindow = false

    /// 현재 파이프라인 실행 여부입니다.
    private var isRunning = false

    /// 분석 window 길이입니다.
    private let windowSeconds = 3.0

    /// 분석 window 방출 간격입니다.
    private let stepSeconds = 1.0

    /// 평균에 사용할 최근 window 개수입니다.
    private let maxWindowCount = 3

    // MARK: - 초기화

    /// 의존성을 주입해 분석기를 생성합니다.
    init(
        recorder: MusicAudioWindowRecorder = MusicAudioWindowRecorder(),
        extractor: AudioFeatureExtractor = AudioFeatureExtractor()
    ) {
        self.recorder = recorder
        self.extractor = extractor
    }

    // MARK: - 시작 제어

    /// 마이크 입력과 CoreML 분석 파이프라인을 시작합니다.
    func start() {
        do {
            _ = try getClassifier()
        } catch {
            delegate?.musicMoodAnalyzer(self, didFail: error)
            return
        }

        windows.removeAll()
        isProcessingWindow = false
        isRunning = true
        runId = UUID()

        let currentRunId = runId
        delegate?.musicMoodAnalyzer(self, didUpdateStatus: "음악 무드 분석 준비 중")

        recorder.start(
            windowSeconds: windowSeconds,
            stepSeconds: stepSeconds,
            onWindow: { [weak self] samples, sampleRate in
                self?.analyzeWindow(samples: samples, sampleRate: sampleRate, runId: currentRunId)
            },
            onError: { [weak self] error in
                guard let self else { return }

                DispatchQueue.main.async {
                    guard self.runId == currentRunId else { return }

                    self.isRunning = false
                    self.isProcessingWindow = false
                    self.delegate?.musicMoodAnalyzer(self, didFail: error)
                }
            }
        )

        delegate?.musicMoodAnalyzer(self, didUpdateStatus: "마이크 입력 수집 중")
    }

    /// 분석 파이프라인을 중지합니다.
    func stop() {
        runId = UUID()
        recorder.stop()
        isRunning = false
        isProcessingWindow = false
        delegate?.musicMoodAnalyzer(self, didUpdateStatus: "음악 무드 분석 중지됨")
    }

    // MARK: - 분석 처리

    /// 오디오 window를 CoreML 입력으로 변환하고 예측 결과를 처리합니다.
    private func analyzeWindow(samples: [Float], sampleRate: Double, runId currentRunId: UUID) {
        DispatchQueue.main.async {
            guard self.isRunning, self.runId == currentRunId, !self.isProcessingWindow else {
                return
            }

            self.isProcessingWindow = true
            self.delegate?.musicMoodAnalyzer(self, didUpdateStatus: "최근 3초 음악 분석 중")

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let classifier = try self.getClassifier()
                    let input = try self.extractor.makeInput(samples: samples, sampleRate: sampleRate)
                    let result = try classifier.predict(input: input)
                    let prediction = self.makePrediction(from: result)

                    DispatchQueue.main.async {
                        guard self.isRunning, self.runId == currentRunId else {
                            return
                        }

                        self.isProcessingWindow = false
                        self.delegate?.musicMoodAnalyzer(self, didUpdatePrediction: prediction)
                        self.delegate?.musicMoodAnalyzer(self, didUpdateStatus: "음악 무드 분석 완료")
                    }
                } catch {
                    DispatchQueue.main.async {
                        guard self.runId == currentRunId else {
                            return
                        }

                        self.isProcessingWindow = false
                        self.delegate?.musicMoodAnalyzer(self, didFail: error)
                    }
                }
            }
        }
    }

    // MARK: - 상태 업데이트

    /// 원시 classifier 결과를 앱 도메인 예측 결과로 변환합니다.
    private func makePrediction(from result: MusicMoodClassifierResult) -> MusicMoodPrediction {
        let normalized = normalizeProbabilities(result.probabilities)
        windows.append(normalized)

        if windows.count > maxWindowCount {
            windows.removeFirst()
        }

        let averaged = averageProbabilities(windows)
        let selected = chooseMood(from: averaged)

        return MusicMoodPrediction(
            mood: selected.mood,
            confidence: selected.confidence,
            probabilities: averaged
        )
    }

    /// raw 확률을 합 1.0 기준으로 정규화합니다.
    private func normalizeProbabilities(_ probabilities: [String: Double]) -> [MusicMood: Double] {
        var result: [MusicMood: Double] = [:]
        var sum = 0.0

        for mood in MusicMood.allCases {
            let value = probabilities[mood.modelLabel] ?? 0.0
            result[mood] = value
            sum += value
        }

        guard sum > 0 else {
            let fallback = 1.0 / Double(MusicMood.allCases.count)
            return Dictionary(uniqueKeysWithValues: MusicMood.allCases.map { ($0, fallback) })
        }

        for mood in MusicMood.allCases {
            result[mood] = (result[mood] ?? 0.0) / sum
        }

        return result
    }

    /// 최근 window 확률의 평균을 계산합니다.
    private func averageProbabilities(_ windows: [[MusicMood: Double]]) -> [MusicMood: Double] {
        guard !windows.isEmpty else {
            return Dictionary(uniqueKeysWithValues: MusicMood.allCases.map { ($0, 0.0) })
        }

        var averages: [MusicMood: Double] = [:]

        for mood in MusicMood.allCases {
            let sum = windows.reduce(0.0) { partial, window in
                partial + (window[mood] ?? 0.0)
            }

            averages[mood] = sum / Double(windows.count)
        }

        return averages
    }

    /// 평균 확률에서 최종 무드를 선택합니다.
    private func chooseMood(from probabilities: [MusicMood: Double]) -> (mood: MusicMood, confidence: Double) {
        let happy = probabilities[.happy] ?? 0.0
        let angry = probabilities[.angry] ?? 0.0
        let sad = probabilities[.sad] ?? 0.0
        let relaxed = probabilities[.relaxed] ?? 0.0

        let rawCandidates: [(MusicMood, Double)] = [
            (.happy, happy),
            (.angry, angry),
            (.sad, sad),
            (.relaxed, relaxed)
        ]

        let rawBest = rawCandidates.max { $0.1 < $1.1 } ?? (.happy, happy)
        let relaxedMinimum = 0.20
        let relaxedTolerance = 0.07

        if rawBest.0 != .angry {
            if relaxed >= relaxedMinimum && relaxed >= rawBest.1 - relaxedTolerance {
                return (.relaxed, relaxed)
            }

            return rawBest
        }

        let nonAngryCandidates: [(MusicMood, Double)] = [
            (.happy, happy),
            (.sad, sad),
            (.relaxed, relaxed)
        ]

        let nonAngryBest = nonAngryCandidates.max { $0.1 < $1.1 } ?? (.happy, happy)
        let angryMinimum = 0.32
        let angryMargin = 0.04

        if angry >= angryMinimum && angry >= nonAngryBest.1 + angryMargin {
            return (.angry, angry)
        }

        if relaxed >= relaxedMinimum && relaxed >= nonAngryBest.1 - relaxedTolerance {
            return (.relaxed, relaxed)
        }

        return nonAngryBest
    }

    // MARK: - 내부 유틸리티

    /// classifier를 lazy load합니다.
    private func getClassifier() throws -> MusicMoodModelClassifier {
        if let classifier {
            return classifier
        }

        let newClassifier = try MusicMoodModelClassifier()
        classifier = newClassifier
        return newClassifier
    }
}
