/// 감지모드 위험 알림 전용 iPhone CoreHaptics 컨트롤러입니다.

import AVFoundation
import CoreHaptics
import Foundation
import UIKit

final class DangerHapticController {
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var isEngineStarted = false

    func play(for sound: DangerSound) {
        switch sound.alertHapticPattern {
        case .siren:
            print("📳 [DangerHaptic] play siren")
            playSiren()
        case .fireAlarm:
            print("📳 [DangerHaptic] play fireAlarm")
            playFireAlarm()
        case .carHorn:
            print("📳 [DangerHaptic] play carHorn")
            playCarHorn()
        case .genericDanger:
            print("📳 [DangerHaptic] play genericDanger")
            playGenericDanger()
        case .gentleNotice:
            print("📳 [DangerHaptic] play gentleNotice")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func startEngineIfNeeded() -> Bool {
        guard supportsHaptics else {
            print("📳 [DangerHaptic] CoreHaptics unavailable → UIKit fallback")
            return false
        }

        do {
            try AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)

            if engine == nil {
                engine = try CHHapticEngine()
                engine?.stoppedHandler = { reason in
                    print("📳 [DangerHaptic] engine stopped reason=\(reason.rawValue)")
                }
                engine?.resetHandler = { [weak self] in
                    print("📳 [DangerHaptic] engine reset/restart")
                    self?.isEngineStarted = false
                    _ = self?.startEngineIfNeeded()
                }
            }

            if !isEngineStarted {
                try engine?.start()
                isEngineStarted = true
                print("📳 [DangerHaptic] engine started")
            }

            return true
        } catch {
            print("📳 [DangerHaptic] CoreHaptics unavailable → UIKit fallback")
            return false
        }
    }

    private func playSiren() {
        guard startEngineIfNeeded() else {
            playSirenFallback()
            return
        }

        let events = [
            continuous(time: 0.00, duration: 0.20, intensity: 1.0, sharpness: 1.0),
            transient(time: 0.20, intensity: 1.0, sharpness: 1.0),
            continuous(time: 0.42, duration: 0.20, intensity: 1.0, sharpness: 1.0),
            transient(time: 0.62, intensity: 1.0, sharpness: 1.0),
            continuous(time: 0.84, duration: 0.20, intensity: 1.0, sharpness: 1.0)
        ]
        play(events: events)
    }

    private func playFireAlarm() {
        guard startEngineIfNeeded() else {
            playFireAlarmFallback()
            return
        }

        print("📳 [DangerHaptic] fireAlarm pattern: long buzz + strong final double tap")
        let events = [
            continuous(time: 0.00, duration: 0.58, intensity: 1.0, sharpness: 0.82),
            transient(time: 0.66, intensity: 1.0, sharpness: 1.0),
            continuous(time: 0.665, duration: 0.045, intensity: 1.0, sharpness: 1.0),
            transient(time: 0.70, intensity: 1.0, sharpness: 1.0)
        ]
        play(events: events)
    }

    private func playCarHorn() {
        guard startEngineIfNeeded() else {
            playCarHornFallback()
            return
        }

        let events = [
            transient(time: 0.00, intensity: 1.0, sharpness: 1.0),
            continuous(time: 0.01, duration: 0.09, intensity: 1.0, sharpness: 0.92),
            transient(time: 0.16, intensity: 1.0, sharpness: 1.0),
            continuous(time: 0.17, duration: 0.09, intensity: 1.0, sharpness: 0.92)
        ]
        play(events: events)
    }

    private func playGenericDanger() {
        guard startEngineIfNeeded() else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }

        play(events: [
            transient(time: 0, intensity: 1.0, sharpness: 0.9),
            transient(time: 0.22, intensity: 0.85, sharpness: 0.8)
        ])
    }

    private func transient(time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time
        )
    }

    private func continuous(time: TimeInterval, duration: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time,
            duration: duration
        )
    }

    private func play(events: [CHHapticEvent]) {
        do {
            guard let engine else {
                return
            }

            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("📳 [DangerHaptic] CoreHaptics unavailable → UIKit fallback")
        }
    }

    private func playSirenFallback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            generator.notificationOccurred(.warning)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) {
            generator.notificationOccurred(.warning)
        }
    }

    private func playFireAlarmFallback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred(intensity: 0.9)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
            generator.impactOccurred(intensity: 0.9)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            generator.impactOccurred(intensity: 0.9)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.39) {
            generator.impactOccurred(intensity: 0.9)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
            generator.impactOccurred(intensity: 0.9)
        }
    }

    private func playCarHornFallback() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            generator.impactOccurred(intensity: 1.0)
        }
    }
}
