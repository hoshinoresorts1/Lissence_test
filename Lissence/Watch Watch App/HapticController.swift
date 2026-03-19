/// 상황별 진동 제어기

import WatchKit
import Foundation

class HapticController {

    static let shared = HapticController()
    private var lastHapticTime: Date = .distantPast
    private let cooldown: TimeInterval = 1.0 // 생활모드는 1초 쿨다운

    func play(for sound: DangerSound) {
        let now = Date()
        guard now.timeIntervalSince(lastHapticTime) > cooldown else { return }
        lastHapticTime = now

        if sound.isDanger {
            // 위험 상황: 강하고 긴 진동 (Success 패턴 + 추가 진동)
            WKInterfaceDevice.current().play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                WKInterfaceDevice.current().play(.directionUp) // 주의를 끄는 상승 진동
            }
        } else {
            // 일반 상황: 가벼운 알림 진동
            WKInterfaceDevice.current().play(.notification)
        }
    }
}

