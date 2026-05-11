/// 음악 모드에서 실시간 시각화와 가벼운 햅틱에 사용할 오디오 레벨 값을 정의합니다.

import Foundation

/// 마이크 입력 buffer에서 계산한 경량 오디오 레벨입니다.
struct MusicAudioLevel {
    // MARK: - 속성

    /// 입력 buffer의 RMS 에너지입니다.
    let rms: Double

    /// 입력 buffer의 peak 레벨입니다.
    let peak: Double

    /// 입력 buffer의 zero crossing rate입니다.
    let zeroCrossingRate: Double

    /// FFT low band 에너지입니다.
    let lowEnergy: Double

    /// FFT mid band 에너지입니다.
    let midEnergy: Double

    /// FFT high band 에너지입니다.
    let highEnergy: Double

    /// FFT spectral centroid입니다.
    let centroid: Double

    /// 레벨이 계산된 시각입니다.
    let timestamp: Date

    /// UI와 햅틱에 사용하기 쉽게 0...1 범위로 보정한 에너지입니다.
    var normalizedEnergy: Double {
        min(max(rms * 18.0, 0.0), 1.0)
    }

    /// UI와 햅틱에 사용하기 쉽게 0...1 범위로 보정한 peak 값입니다.
    var normalizedPeak: Double {
        min(max(peak, 0.0), 1.0)
    }

    /// 입력이 없는 상태를 나타내는 기본 레벨입니다.
    static let silent = MusicAudioLevel(
        rms: 0,
        peak: 0,
        zeroCrossingRate: 0,
        lowEnergy: 0,
        midEnergy: 0,
        highEnergy: 0,
        centroid: 0,
        timestamp: Date()
    )
}
