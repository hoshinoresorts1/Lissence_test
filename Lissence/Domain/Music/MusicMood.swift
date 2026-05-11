/// 음악 무드 분석에서 사용하는 도메인 무드 타입을 정의합니다.

import Foundation

/// CoreML 모델의 Q1~Q4 라벨을 앱에서 쓰는 음악 무드로 매핑합니다.
enum MusicMood: String, CaseIterable, Identifiable {
    /// 밝고 에너지 있는 무드입니다.
    case happy

    /// 강하고 날카로운 무드입니다.
    case angry

    /// 낮고 차분한 슬픔 계열 무드입니다.
    case sad

    /// 안정적이고 편안한 무드입니다.
    case relaxed

    /// SwiftUI 목록 및 식별에 사용하는 값입니다.
    var id: String { rawValue }

    /// CoreML 모델이 반환하는 라벨입니다.
    var modelLabel: String {
        switch self {
        case .happy:
            return "Q1"
        case .angry:
            return "Q2"
        case .sad:
            return "Q3"
        case .relaxed:
            return "Q4"
        }
    }

    /// 화면에 표시할 한글 이름입니다.
    var displayName: String {
        switch self {
        case .happy:
            return "행복"
        case .angry:
            return "분노"
        case .sad:
            return "슬픔"
        case .relaxed:
            return "편안함"
        }
    }

    /// 화면 표시용 SF Symbol 이름입니다.
    var iconName: String {
        switch self {
        case .happy:
            return "sun.max.fill"
        case .angry:
            return "flame.fill"
        case .sad:
            return "cloud.rain.fill"
        case .relaxed:
            return "leaf.fill"
        }
    }

    /// Rive state machine의 mood 입력값입니다.
    var riveValue: Double {
        switch self {
        case .happy:
            return 0.0
        case .angry:
            return 1.0
        case .sad:
            return 2.0
        case .relaxed:
            return 3.0
        }
    }

    /// CoreML 라벨을 앱 도메인 무드로 변환합니다.
    init?(modelLabel: String) {
        guard let mood = Self.allCases.first(where: { $0.modelLabel == modelLabel }) else {
            return nil
        }

        self = mood
    }
}
