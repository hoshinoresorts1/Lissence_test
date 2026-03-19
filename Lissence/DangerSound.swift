import Foundation

enum DangerSound: String, CaseIterable {
    case siren, fireAlarm, shouting, carHorn, knock, laughter, speech, unknown

    // 1. 표시용 텍스트 (라벨)
    var label: String {
        switch self {
        case .siren: return "🚨 경찰/소방차 사이렌 감지!"
        case .fireAlarm: return "🔥 화재 경보기 소리 감지!"
        case .shouting: return "🗣️ 큰 소음/비명 감지!"
        case .carHorn: return "🚘 차 경적 감지!"
        case .knock: return "🚪 노크 소리가 들려요!"
        case .laughter: return "😊 웃음소리가 들려요!"
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
        case .laughter: return "face.smiling.fill"
        case .speech: return "person.wave.2.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    // 3. 위험 여부 판단
    var isDanger: Bool {
        switch self {
        case .knock, .laughter, .speech: return false
        default: return true
        }
    }
    
    // 4. Apple SoundAnalysis ID와 매핑
    static func from(identifier: String) -> DangerSound? {
        switch identifier {
        case "siren", "emergency_vehicle": return .siren
        case "fire_alarm", "smoke_detector": return .fireAlarm
        case "shouting", "screaming", "yelling": return .shouting
        case "car_horn", "vehicle_horn": return .carHorn
        case "knock": return .knock
        case "laughter", "giggle", "chuckle": return .laughter
        case "speech", "conversation": return .speech
        default: return nil
        }
    }
}
