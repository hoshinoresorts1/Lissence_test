/// iPhone 음악 모드 화면의 상태와 사용자 액션을 관리합니다.

import Combine
import Foundation

/// 음악 모드 화면에서 사용할 MVVM ViewModel입니다.
final class MusicViewModel: ObservableObject {
    // MARK: - 속성

    /// 마이크 기반 음악 무드 분석 실행 여부입니다.
    @Published var isRunning = false

    /// 화면에 표시할 현재 상태 문구입니다.
    @Published var statusText = "음악 모드 대기 중"

    /// 최근 분석된 음악 무드입니다.
    @Published var currentMood: MusicMood?

    /// 최근 분석 결과의 신뢰도입니다.
    @Published var confidence: Double = 0

    /// 무드별 최근 평균 확률입니다.
    @Published var probabilities: [MusicMood: Double] = Dictionary(
        uniqueKeysWithValues: MusicMood.allCases.map { ($0, 0.0) }
    )

    /// 음악 무드 분석 파이프라인입니다.
    private let analyzer: MusicMoodAnalyzer

    // MARK: - 초기화

    /// 분석기를 주입받아 ViewModel을 생성합니다.
    init(analyzer: MusicMoodAnalyzer = MusicMoodAnalyzer()) {
        self.analyzer = analyzer
        self.analyzer.delegate = self
    }

    // MARK: - 시작 제어

    /// 음악 무드 분석을 시작합니다.
    func start() {
        guard !isRunning else {
            return
        }

        isRunning = true
        statusText = "음악 무드 분석 시작 중"
        analyzer.start()

        // TODO: 다음 단계에서 분석된 currentMood를 햅틱 패턴 컨트롤러에 전달합니다.
    }

    /// 음악 무드 분석을 중지합니다.
    func stop() {
        guard isRunning else {
            return
        }

        analyzer.stop()
        isRunning = false
    }

    /// 시작/중지 버튼 액션을 처리합니다.
    func toggleRunning() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }
}

// MARK: - MusicMoodAnalyzerDelegate

extension MusicViewModel: MusicMoodAnalyzerDelegate {
    /// 분석기 상태 문구를 ViewModel 상태로 반영합니다.
    func musicMoodAnalyzer(_ analyzer: MusicMoodAnalyzer, didUpdateStatus status: String) {
        statusText = status
    }

    /// 분석 결과를 ViewModel 상태로 반영합니다.
    func musicMoodAnalyzer(_ analyzer: MusicMoodAnalyzer, didUpdatePrediction prediction: MusicMoodPrediction) {
        currentMood = prediction.mood
        confidence = prediction.confidence
        probabilities = prediction.probabilities
    }

    /// 분석 오류를 ViewModel 상태로 반영합니다.
    func musicMoodAnalyzer(_ analyzer: MusicMoodAnalyzer, didFail error: Error) {
        isRunning = false
        statusText = "음악 분석 실패: \(error.localizedDescription)"
    }
}
