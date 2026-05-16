/// 애플워치 진동 제어 로직
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

        guard sound.isDanger else {
            // 일반 상황: 가벼운 알림 진동
            WKInterfaceDevice.current().play(.notification)
            return
        }

        switch sound.alertHapticPattern {
        case .siren:
            WKInterfaceDevice.current().play(.notification)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                WKInterfaceDevice.current().play(.directionUp)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
                WKInterfaceDevice.current().play(.notification)
            }
        case .fireAlarm:
            WKInterfaceDevice.current().play(.failure)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                WKInterfaceDevice.current().play(.retry)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                WKInterfaceDevice.current().play(.failure)
            }
        case .carHorn:
            WKInterfaceDevice.current().play(.click)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                WKInterfaceDevice.current().play(.click)
            }
        case .genericDanger:
            WKInterfaceDevice.current().play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                WKInterfaceDevice.current().play(.directionUp)
            }
        case .gentleNotice:
            WKInterfaceDevice.current().play(.notification)
        }
    }
}
