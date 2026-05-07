/// 음악 무드 모델 학습 시 사용한 채널별 정규화 통계를 로드합니다.

import Foundation

/// 오디오 feature 채널별 평균과 표준편차입니다.
struct TrainingStats {
    /// 스펙트로그램, MFCC, Mel 채널의 평균입니다.
    let means: [Float]

    /// 스펙트로그램, MFCC, Mel 채널의 표준편차입니다.
    let stds: [Float]

    // MARK: - 로드

    /// 앱 번들에서 학습 통계 json을 읽어옵니다.
    static func load() -> TrainingStats {
        guard let url = Bundle.main.url(forResource: "train_stats_segments_improved", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return TrainingStats(means: [0, 0, 0], stds: [1, 1, 1])
        }

        let means = readArray(object, keys: ["channel_mean", "channel_means", "means", "mean"]) ?? [0, 0, 0]
        let stds = readArray(object, keys: ["channel_std", "channel_stds", "stds", "std"]) ?? [1, 1, 1]

        return TrainingStats(
            means: fit3(means, fallback: [0, 0, 0]),
            stds: fit3(stds, fallback: [1, 1, 1])
        )
    }

    // MARK: - 내부 유틸리티

    /// 여러 가능한 key 이름 중 첫 번째 배열 값을 읽습니다.
    private static func readArray(_ object: [String: Any], keys: [String]) -> [Float]? {
        for key in keys {
            if let array = object[key] as? [Double] {
                return array.map { Float($0) }
            }

            if let array = object[key] as? [Float] {
                return array
            }

            if let array = object[key] as? [NSNumber] {
                return array.map { $0.floatValue }
            }
        }

        return nil
    }

    /// 모델 입력 채널 수에 맞춰 배열을 3개 값으로 보정합니다.
    private static func fit3(_ values: [Float], fallback: [Float]) -> [Float] {
        if values.count >= 3 {
            return Array(values.prefix(3))
        }

        if values.count == 1 {
            return [values[0], values[0], values[0]]
        }

        return fallback
    }
}
