/// 감지모드 호출어 알림 전용 iPhone CoreHaptics 컨트롤러입니다.

import AVFoundation
import CoreHaptics
import Foundation
import UIKit

final class AttentionHapticController {
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var isEngineStarted = false

    func play(level: AttentionAlertLevel) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.play(level: level)
            }
            return
        }

        switch level {
        case .softAlert:
            playSoftAlert()
        case .strongAlert:
            playStrongAlert()
        case .none, .displayOnly:
            break
        }
    }

    private func startEngineIfNeeded() -> Bool {
        guard supportsHaptics else {
            return false
        }

        do {
            try AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)

            if engine == nil {
                engine = try CHHapticEngine()
                engine?.stoppedHandler = { reason in
                    print("📳 [AttentionHaptic] engine stopped reason=\(reason.rawValue)")
                }
                engine?.resetHandler = { [weak self] in
                    print("📳 [AttentionHaptic] engine reset/restart")
                    self?.isEngineStarted = false
                    _ = self?.startEngineIfNeeded()
                }
            }

            if !isEngineStarted {
                try engine?.start()
                isEngineStarted = true
                print("📳 [AttentionHaptic] engine started")
            }

            return true
        } catch {
            return false
        }
    }

    private func playSoftAlert() {
        guard startEngineIfNeeded() else {
            print("📳 [AttentionHaptic] UIKit fallback softAlert")
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred(intensity: 0.9)
            return
        }

        print("📳 [AttentionHaptic] play CoreHaptics softAlert")
        play(events: [
            transient(time: 0.00, intensity: 0.75, sharpness: 0.75),
            transient(time: 0.12, intensity: 0.55, sharpness: 0.70)
        ])
    }

    private func playStrongAlert() {
        guard startEngineIfNeeded() else {
            print("📳 [AttentionHaptic] UIKit fallback strongAlert")
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred(intensity: 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                generator.impactOccurred(intensity: 1.0)
            }
            return
        }

        print("📳 [AttentionHaptic] play CoreHaptics strongAlert")
        play(events: [
            transient(time: 0.00, intensity: 1.0, sharpness: 1.0),
            continuous(time: 0.01, duration: 0.06, intensity: 1.0, sharpness: 0.95),
            transient(time: 0.16, intensity: 1.0, sharpness: 1.0),
            continuous(time: 0.17, duration: 0.06, intensity: 1.0, sharpness: 0.95)
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
            print("📳 [AttentionHaptic] UIKit fallback after CoreHaptics error")
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)
        }
    }
}
