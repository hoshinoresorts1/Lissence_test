/// 음악 모드의 iPhone 햅틱 출력을 담당하는 컨트롤러입니다.

import AVFoundation
import CoreHaptics
import Foundation

/// 레퍼런스 음악 모드에서 사용하는 햅틱 스타일입니다.
enum MusicHapticStyle {
    /// 짧은 단일 탭입니다.
    case tap

    /// 짧은 두 번의 탭입니다.
    case doubleTap

    /// 부드러운 continuous 진동입니다.
    case softContinuous

    /// 더 진한 continuous 진동입니다.
    case buzzContinuous

    /// happy 무드에서 밝고 강한 continuous 진동입니다.
    case happyContinuous

    /// angry 무드에서 더 강하고 날카로운 continuous 진동입니다.
    case angryContinuous

    /// intensity가 올라가는 rising continuous 진동입니다.
    case rising

    /// 매우 짧은 미세 탭입니다.
    case microTap
}

/// 음악 분석 결과를 CoreHaptics 패턴으로 재생합니다.
final class MusicHapticController {
    // MARK: - 속성

    /// Core Haptics를 지원하는 기기인지 여부입니다.
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    /// 햅틱 패턴을 재생하는 Core Haptics 엔진입니다.
    private var engine: CHHapticEngine?

    /// 햅틱 컨트롤러 실행 여부입니다.
    private var isRunning = false

    /// 햅틱 상태를 화면과 로그에 전달하는 콜백입니다.
    var onStatusUpdate: ((String) -> Void)?

    // MARK: - 시작 제어

    /// Core Haptics 엔진을 준비합니다.
    func start() {
        report("supportsHaptics=\(supportsHaptics)")

        guard supportsHaptics else {
            report("이 기기는 CoreHaptics를 지원하지 않습니다.")
            return
        }

        isRunning = true
        try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)

        do {
            if engine == nil {
                engine = try CHHapticEngine()
                report("CHHapticEngine created")
                engine?.resetHandler = { [weak self] in
                    self?.report("CHHapticEngine reset; restarting")
                    try? self?.engine?.start()
                }
            }

            try engine?.start()
            report("CHHapticEngine started")
        } catch {
            report("start failed: \(error.localizedDescription)")
        }
    }

    /// 햅틱 엔진을 중지합니다.
    func stop() {
        isRunning = false
        engine?.stop()
        report("CHHapticEngine stopped")
    }

    // MARK: - 햅틱 출력

    /// 레퍼런스 음악 모드의 햅틱 스타일 구조에 맞춰 패턴을 재생합니다.
    func play(style: MusicHapticStyle, intensity: Float, sharpness: Float) {
        guard isRunning, supportsHaptics else {
            return
        }

        switch style {
        case .tap:
            playTap(intensity, sharpness)
        case .doubleTap:
            playDoubleTap(intensity, sharpness)
        case .softContinuous:
            playContinuous(intensity * 0.75, sharpness * 0.45, duration: 0.24, intensityFloor: 0.18, type: "softContinuous")
        case .buzzContinuous:
            playContinuous(intensity * 0.90, sharpness * 0.50, duration: 0.34, intensityFloor: 0.20, type: "buzzContinuous")
        case .happyContinuous:
            playContinuous(min(intensity * 1.02, 1.0), sharpness * 0.55, duration: 0.38, intensityFloor: 0.30, type: "happyContinuous")
        case .angryContinuous:
            playContinuous(min(intensity * 1.15, 1.0), sharpness * 0.70, duration: 0.42, intensityFloor: 0.35, type: "angryContinuous")
        case .rising:
            playRising(intensity, sharpness)
        case .microTap:
            playTap(max(intensity, 0.05), max(sharpness, 0.08), type: "microTap")
        }
    }

    // MARK: - 내부 유틸리티

    /// 짧은 단일 transient를 재생합니다.
    private func playTap(_ intensity: Float, _ sharpness: Float, type: String = "tap") {
        guard engine != nil else {
            return
        }

        reportHaptic(type: type, intensity: intensity, sharpness: sharpness, duration: 0)

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )

        play(events: [event], curves: [])
    }

    /// 두 번의 transient를 재생합니다.
    private func playDoubleTap(_ intensity: Float, _ sharpness: Float) {
        guard engine != nil else {
            return
        }

        reportHaptic(type: "doubleTap", intensity: intensity, sharpness: sharpness, duration: 0.09)

        let first = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )
        let second = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: max(intensity * 0.72, 0.12)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: min(sharpness * 0.95, 1.0))
            ],
            relativeTime: 0.09
        )

        play(events: [first, second], curves: [])
    }

    /// continuous 햅틱을 재생합니다.
    private func playContinuous(
        _ intensity: Float,
        _ sharpness: Float,
        duration: TimeInterval,
        intensityFloor: Float,
        type: String
    ) {
        guard engine != nil else {
            return
        }

        let finalIntensity = max(intensity, intensityFloor)
        let finalSharpness = max(sharpness, 0.05)
        reportHaptic(type: type, intensity: finalIntensity, sharpness: finalSharpness, duration: duration)

        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: finalIntensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: finalSharpness)
            ],
            relativeTime: 0,
            duration: duration
        )

        play(events: [event], curves: [])
    }

    /// intensity와 sharpness가 상승하는 continuous 햅틱을 재생합니다.
    private func playRising(_ intensity: Float, _ sharpness: Float) {
        guard engine != nil else {
            return
        }

        let baseIntensity = max(intensity * 0.35, 0.12)
        let baseSharpness = max(sharpness * 0.35, 0.08)
        let duration: TimeInterval = 0.22
        reportHaptic(type: "rising", intensity: intensity, sharpness: sharpness, duration: duration)

        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: baseIntensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: baseSharpness)
            ],
            relativeTime: 0,
            duration: duration
        )
        let intensityCurve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: baseIntensity),
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.12, value: min(intensity * 0.75, 1.0)),
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.22, value: min(intensity, 1.0))
            ],
            relativeTime: 0
        )
        let sharpnessCurve = CHHapticParameterCurve(
            parameterID: .hapticSharpnessControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: baseSharpness),
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.22, value: min(sharpness, 1.0))
            ],
            relativeTime: 0
        )

        play(events: [event], curves: [intensityCurve, sharpnessCurve])
    }

    /// CoreHaptics pattern을 생성하고 재생합니다.
    private func play(events: [CHHapticEvent], curves: [CHHapticParameterCurve]) {
        do {
            guard let engine else {
                return
            }

            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            report("play failed: \(error.localizedDescription)")
        }
    }

    /// 햅틱 상태를 로그와 UI 콜백으로 전달합니다.
    private func report(_ message: String) {
        let fullMessage = "[MusicHaptic] \(message)"
        print(fullMessage)
        onStatusUpdate?(message)
    }

    /// 레퍼런스 비교용 햅틱 재생 로그를 출력합니다.
    private func reportHaptic(type: String, intensity: Float, sharpness: Float, duration: TimeInterval) {
        report("\(type) type=\(type), intensity=\(format(Double(intensity))), sharpness=\(format(Double(sharpness))), duration=\(format(duration))")
    }

    /// 로그용 소수점 문자열을 만듭니다.
    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
