/// 공통 데이터 규격(Shared Group)
/// - 위험 데이터 구조체 매핑

import Foundation

enum AlertHapticPattern: String, Codable {
    case siren
    case fireAlarm
    case carHorn
    case genericDanger
    case gentleNotice
}

enum DangerSound: String, CaseIterable {
    case siren, fireAlarm, shouting, carHorn, knock, speech, unknown

    // 1. 표시용 텍스트 (라벨)
    var label: String {
        switch self {
        case .siren: return "🚨 경찰/소방차 사이렌 감지!"
        case .fireAlarm: return "🔥 화재 경보기 소리 감지!"
        case .shouting: return "🗣️ 큰 소음/비명 감지!"
        case .carHorn: return "🚘 차 경적 감지!"
        case .knock: return "🚪 노크 소리가 들려요!"
        case .speech: return "💬 사람의 말소리가 들려요~"
        case .unknown: return ""
        }
    }

    // 2. 아이콘 (getIconForSound를 대체함)
    var icon: String {
        switch self {
        case .siren: return "bell.badge.fill"
        case .fireAlarm: return "flame.fill"
        case .shouting: return "exclamationmark.bubble.fill"
        case .carHorn: return "car.fill"
        case .knock: return "door.left.hand.closed"
        case .speech: return "person.wave.2.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    // 3. 위험 여부 판단
    var isDanger: Bool {
        switch self {
        case .knock, .speech: return false
        default: return true
        }
    }

    /// ESP32 DRV2605L 햅틱 드라이버로 전송할 BLE pattern 식별자입니다.
    var hapticPattern: String? {
        switch self {
        case .siren:
            return "siren"
        case .fireAlarm:
            return "fireAlarm"
        case .carHorn:
            return "carHorn"
        case .shouting, .knock, .speech, .unknown:
            return nil
        }
    }

    /// iPhone과 Apple Watch에서 공통으로 사용하는 발표용 위험 햅틱 패턴입니다.
    var alertHapticPattern: AlertHapticPattern {
        switch self {
        case .siren:
            return .siren
        case .fireAlarm:
            return .fireAlarm
        case .carHorn:
            return .carHorn
        case .shouting:
            return .genericDanger
        case .knock, .speech, .unknown:
            return .gentleNotice
        }
    }
    
    // 4. Apple SoundAnalysis ID와 매핑
    static func from(identifier: String) -> DangerSound? {
        switch identifier {
        case "siren", "emergency_vehicle": return .siren
        case "fire_alarm", "smoke_detector": return .fireAlarm
        case "car_horn", "vehicle_horn": return .carHorn
        // 음성인식 기능과 사람 소리 관련 기능은 유지하되, SoundAnalysis 기반 위험 감지에서는 제외한다.
        case "knock",
             "speech",
             "conversation",
             "shouting",
             "screaming",
             "yelling",
             "crying_sobbing",
             "baby_crying":
            return nil
        default: return nil
        }
    }
}
