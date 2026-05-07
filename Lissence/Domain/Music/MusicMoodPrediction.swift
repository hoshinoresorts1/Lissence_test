/// 음악 무드 분석 결과와 확률 값을 표현하는 모델을 정의합니다.

import Foundation

/// CoreML 단일 예측 결과입니다.
struct MusicMoodPrediction {
    /// 가장 가능성이 높은 음악 무드입니다.
    let mood: MusicMood

    /// 선택된 무드의 확률 값입니다.
    let confidence: Double

    /// 무드별 정규화 확률입니다.
    let probabilities: [MusicMood: Double]

    /// 상태 표시용 백분율 문자열입니다.
    var confidenceText: String {
        String(format: "%.1f%%", confidence * 100.0)
    }
}

/// CoreML 원시 라벨과 확률 딕셔너리를 담는 내부 결과입니다.
struct MusicMoodClassifierResult {
    /// 모델이 선택한 원시 라벨입니다.
    let label: String

    /// 모델이 반환한 원시 확률 딕셔너리입니다.
    let probabilities: [String: Double]
}
