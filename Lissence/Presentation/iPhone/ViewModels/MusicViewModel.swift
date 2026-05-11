/// iPhone 음악 모드 화면의 상태와 사용자 액션을 관리합니다.

import Combine
import Foundation
import QuartzCore

/// 음악 모드 화면에서 사용할 MVVM ViewModel입니다.
final class MusicViewModel: ObservableObject {
    // MARK: - 속성

    /// 마이크 기반 음악 무드 분석 실행 여부입니다.
    @Published var isRunning = false

    /// 화면에 표시할 현재 상태 문구입니다.
    @Published var statusText = "음악 모드 대기 중"

    /// 최근 분석된 음악 무드입니다.
    @Published var currentMood: MusicMood?

    /// 최근 분석 결과의 신뢰도입니다.
    @Published var confidence: Double = 0

    /// 무드별 최근 평균 확률입니다.
    @Published var probabilities: [MusicMood: Double] = Dictionary(
        uniqueKeysWithValues: MusicMood.allCases.map { ($0, 0.0) }
    )

    /// 실시간 마이크 에너지입니다.
    @Published var audioEnergy: Double = 0

    /// 실시간 마이크 peak 값입니다.
    @Published var audioPeak: Double = 0

    /// 파티클과 캐릭터 애니메이션에 사용할 보정된 강도입니다.
    @Published var visualIntensity: Double = 0

    /// 파티클과 캐릭터 애니메이션에 사용할 선명도입니다.
    @Published var visualSharpness: Double = 0

    /// 파티클 충격파에 사용할 bass 강도입니다.
    @Published var visualBass: Double = 0

    /// sparkle에 사용할 treble 강도입니다.
    @Published var visualTreble: Double = 0

    /// 마지막 오디오 레벨 갱신 시각입니다.
    @Published var lastAudioLevelUpdatedAt: Date?

    /// Rive와 파티클의 순간 반응을 위한 볼륨 스파이크 카운터입니다.
    @Published var beatPulse = 0

    /// 강한 입력에서 배경 충격파를 만들기 위한 카운터입니다.
    @Published var bassPulse = 0

    /// iPhone 햅틱 상태를 디버그용으로 짧게 표시합니다.
    @Published var hapticStatusText = "햅틱 대기 중"

    /// 음악 무드 분석 파이프라인입니다.
    private let analyzer: MusicMoodAnalyzer

    /// 음악 모드 전용 iPhone 햅틱 컨트롤러입니다.
    private let hapticController: MusicHapticController

    /// 직전 오디오 에너지입니다.
    private var previousAudioEnergy: Double = 0

    /// 레퍼런스 beat detector의 RMS EMA입니다.
    private var energyEMA: Double = 0

    /// 레퍼런스 beat detector의 peak EMA입니다.
    private var peakEMA: Double = 0

    /// 레퍼런스 beat detector의 low band EMA입니다.
    private var lowEMA: Double = 0

    /// 레퍼런스 beat detector의 mid band EMA입니다.
    private var midEMA: Double = 0

    /// 레퍼런스 beat detector의 high band EMA입니다.
    private var highEMA: Double = 0

    /// 레퍼런스 beat detector의 centroid EMA입니다.
    private var centroidEMA: Double = 0

    /// 마지막 beat 시각입니다.
    private var lastBeatTime: TimeInterval = 0

    /// 마지막 micro tap 시각입니다.
    private var lastMicroTrigger: TimeInterval = 0

    /// 마지막 rising trigger 시각입니다.
    private var lastRisingTrigger: TimeInterval = 0

    /// 디버그 로그 출력 간격 제어 시각입니다.
    private var lastDebugLogTime: TimeInterval = 0

    /// beat 사이 최소 간격입니다.
    private let minBeatInterval: TimeInterval = 0.08

    /// micro tap 사이 최소 간격입니다.
    private let microCooldown: TimeInterval = 0.075

    /// rising pattern 사이 최소 간격입니다.
    private let risingCooldown: TimeInterval = 0.40

    // MARK: - 초기화

    /// 분석기를 주입받아 ViewModel을 생성합니다.
    init(
        analyzer: MusicMoodAnalyzer = MusicMoodAnalyzer(),
        hapticController: MusicHapticController = MusicHapticController()
    ) {
        self.analyzer = analyzer
        self.hapticController = hapticController
        self.analyzer.delegate = self
        self.hapticController.onStatusUpdate = { [weak self] status in
            DispatchQueue.main.async {
                self?.hapticStatusText = status
            }
        }
    }

    // MARK: - 시작 제어

    /// 음악 무드 분석을 시작합니다.
    func start() {
        guard !isRunning else {
            return
        }

        isRunning = true
        statusText = "음악 무드 분석 시작 중"
        hapticController.start()
        analyzer.start()
    }

    /// 음악 무드 분석을 중지합니다.
    func stop() {
        guard isRunning else {
            return
        }

        analyzer.stop()
        hapticController.stop()
        audioEnergy = 0
        audioPeak = 0
        visualIntensity = 0
        visualSharpness = 0
        visualBass = 0
        visualTreble = 0
        previousAudioEnergy = 0
        resetBeatState()
        isRunning = false
    }

    /// 시작/중지 버튼 액션을 처리합니다.
    func toggleRunning() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }
}

// MARK: - MusicMoodAnalyzerDelegate

extension MusicViewModel: MusicMoodAnalyzerDelegate {
    /// 분석기 상태 문구를 ViewModel 상태로 반영합니다.
    func musicMoodAnalyzer(_ analyzer: MusicMoodAnalyzer, didUpdateStatus status: String) {
        statusText = status
    }

    /// 분석 결과를 ViewModel 상태로 반영합니다.
    func musicMoodAnalyzer(_ analyzer: MusicMoodAnalyzer, didUpdatePrediction prediction: MusicMoodPrediction) {
        currentMood = prediction.mood
        confidence = prediction.confidence
        probabilities = prediction.probabilities
    }

    /// 실시간 오디오 레벨을 UI 상태와 햅틱 컨트롤러에 반영합니다.
    func musicMoodAnalyzer(_ analyzer: MusicMoodAnalyzer, didUpdateAudioLevel level: MusicAudioLevel) {
        let beat = processBeat(level)

        audioEnergy = level.normalizedEnergy
        audioPeak = level.normalizedPeak
        visualIntensity = visualIntensity * 0.80 + beat.uiIntensity * 0.20
        visualSharpness = visualSharpness * 0.80 + beat.uiSharpness * 0.20
        visualBass = visualBass * 0.80 + beat.uiBass * 0.20
        visualTreble = visualTreble * 0.80 + beat.uiTreble * 0.20
        lastAudioLevelUpdatedAt = level.timestamp

        if beat.shouldTrigger {
            beatPulse &+= 1

            if beat.emitBassPulse {
                bassPulse &+= 1
            }

            hapticController.play(style: beat.style, intensity: beat.intensity, sharpness: beat.sharpness)
        } else {
            tryMicroTap(level)
        }

        logMusicDebug(level: level, beat: beat)
    }

    /// 분석 오류를 ViewModel 상태로 반영합니다.
    func musicMoodAnalyzer(_ analyzer: MusicMoodAnalyzer, didFail error: Error) {
        isRunning = false
        hapticController.stop()
        statusText = "음악 분석 실패: \(error.localizedDescription)"
    }

    // MARK: - 상태 업데이트

    /// 레퍼런스 음악 엔진과 같은 EMA/beat 조건으로 오디오 레벨을 분석합니다.
    private func processBeat(_ level: MusicAudioLevel) -> (
        shouldTrigger: Bool,
        style: MusicHapticStyle,
        intensity: Float,
        sharpness: Float,
        uiIntensity: Double,
        uiSharpness: Double,
        uiBass: Double,
        uiTreble: Double,
        emitBassPulse: Bool
    ) {
        energyEMA = energyEMA * 0.90 + level.rms * 0.10
        peakEMA = peakEMA * 0.88 + level.peak * 0.12
        lowEMA = lowEMA * 0.88 + level.lowEnergy * 0.12
        midEMA = midEMA * 0.88 + level.midEnergy * 0.12
        highEMA = highEMA * 0.88 + level.highEnergy * 0.12
        centroidEMA = centroidEMA * 0.90 + level.centroid * 0.10

        let now = CACurrentMediaTime()
        let safeEnergy = max(energyEMA, 0.0001)
        let safePeak = max(peakEMA, 0.0001)
        let safeLow = max(lowEMA, 0.0001)
        let safeHigh = max(highEMA, 0.0001)
        let safeCentroid = max(centroidEMA, 1.0)

        let relativeEnergy = level.rms / safeEnergy
        let relativePeak = level.peak / safePeak
        let energyRise = max(level.rms - previousAudioEnergy, 0)
        previousAudioEnergy = level.rms

        let bassBoost = level.lowEnergy / safeLow
        let trebleBoost = level.highEnergy / safeHigh
        let centroidBoost = level.centroid / safeCentroid

        let lowVsMid = level.lowEnergy / max(level.midEnergy, 0.0001)
        let highVsMid = level.highEnergy / max(level.midEnergy, 0.0001)

        let uiIntensity = min(max(relativeEnergy * 0.35 + bassBoost * 0.08, 0), 1)
        let uiSharpness = min(max(level.zeroCrossingRate * 5.0 + highVsMid * 0.12, 0.05), 1)
        let uiBass = min(max(bassBoost * 0.5, 0), 1)
        let uiTreble = min(max(trebleBoost * 0.5, 0), 1)

        guard now - lastBeatTime >= minBeatInterval else {
            return (false, .tap, 0, 0, uiIntensity, uiSharpness, uiBass, uiTreble, false)
        }

        let isStrongEnough =
            (relativeEnergy > 1.12 && energyRise > 0.0015) ||
            (relativePeak > 1.08 && energyRise > 0.0012) ||
            (level.rms > safeEnergy * 1.05 && level.peak > safePeak * 1.03) ||
            (bassBoost > 1.15 && relativeEnergy > 1.04) ||
            (trebleBoost > 1.18 && level.zeroCrossingRate > 0.05)

        guard isStrongEnough else {
            return (false, .tap, 0, 0, uiIntensity, uiSharpness, uiBass, uiTreble, false)
        }

        lastBeatTime = now

        var sharpness = min(max(level.zeroCrossingRate * 3.0, 0.15), 0.75)
        var intensity = (relativeEnergy - 1.0) * 1.8 + (relativePeak - 1.0) * 1.0
        let sharpnessBoost = 1.0 + (sharpness - 0.15) * 0.9
        intensity *= sharpnessBoost
        intensity *= 1.0 + min(max(bassBoost - 1.0, 0), 1.0) * 0.45
        sharpness *= 1.0 + min(max(trebleBoost - 1.0, 0), 1.0) * 0.50
        sharpness *= 1.0 + min(max(centroidBoost - 1.0, 0), 1.0) * 0.18
        intensity = min(max(intensity, 0.30), 1.0)
        sharpness = min(max(sharpness, 0.08), 0.95)

        let strongBassAccent = bassBoost > 1.22 && lowVsMid > 0.78
        let strongTrebleAccent = trebleBoost > 1.16 && highVsMid > 0.84
        let veryStrongHit =
            (relativeEnergy > 1.24 && relativePeak > 1.12) ||
            (energyRise > 0.0045 && relativePeak > 1.10)
        let moderateHit =
            (relativeEnergy > 1.10 && relativePeak > 1.03) ||
            (energyRise > 0.0018)

        var style: MusicHapticStyle = .tap

        switch currentMood ?? .happy {
        case .happy:
            intensity *= 0.92
            sharpness *= 0.88
            if veryStrongHit && strongBassAccent && relativeEnergy > 1.36 && relativePeak > 1.18 {
                style = .rising
            } else if veryStrongHit && strongTrebleAccent && level.zeroCrossingRate > 0.070 {
                style = .doubleTap
                intensity *= 0.86
                sharpness *= 0.88
            } else if moderateHit {
                style = .happyContinuous
                intensity *= 1.02
                sharpness *= 0.78
            } else if strongTrebleAccent && level.zeroCrossingRate > 0.075 && relativeEnergy < 1.12 {
                style = .microTap
                intensity *= 0.70
            } else {
                style = .happyContinuous
                intensity *= 1.00
                sharpness *= 0.76
            }
        case .angry:
            intensity *= 1.08
            sharpness *= 1.02
            if veryStrongHit && strongBassAccent {
                style = .rising
                intensity *= 1.05
            } else if veryStrongHit {
                style = .doubleTap
            } else if moderateHit {
                style = .angryContinuous
                sharpness *= 0.90
            } else if strongTrebleAccent && level.zeroCrossingRate > 0.055 {
                style = .tap
            } else {
                style = .angryContinuous
                intensity *= 1.03
                sharpness *= 0.88
            }
        case .sad:
            intensity *= 0.72
            sharpness *= 0.70
            style = .softContinuous
        case .relaxed:
            intensity *= 0.65
            sharpness *= 0.60
            style = .buzzContinuous
        }

        intensity = min(max(intensity, 0.22), 1.0)
        sharpness = min(max(sharpness, 0.08), 0.95)

        let risingCondition =
            relativeEnergy > 1.22 &&
            energyRise > 0.004 &&
            bassBoost > 1.15 &&
            now - lastRisingTrigger > risingCooldown

        if risingCondition && (currentMood == .happy || currentMood == .angry) {
            lastRisingTrigger = now

            if veryStrongHit || strongBassAccent {
                style = .rising
            }
        }

        let emitBassPulse = strongBassAccent && veryStrongHit

        return (
            true,
            style,
            Float(intensity),
            Float(sharpness),
            uiIntensity,
            uiSharpness,
            uiBass,
            uiTreble,
            emitBassPulse
        )
    }

    /// 레퍼런스 음악 엔진의 micro tap 조건을 적용합니다.
    private func tryMicroTap(_ level: MusicAudioLevel) {
        let now = CACurrentMediaTime()
        let enoughGapFromBeat = now - lastBeatTime > 0.055
        let enoughGapFromMicro = now - lastMicroTrigger > microCooldown
        let safeEnergy = max(energyEMA, 0.0001)
        let safePeak = max(peakEMA, 0.0001)
        let safeHigh = max(highEMA, 0.0001)
        let safeMid = max(midEMA, 0.0001)
        let relativeEnergy = level.rms / safeEnergy
        let relativePeak = level.peak / safePeak
        let trebleBoost = level.highEnergy / safeHigh
        let highVsMid = level.highEnergy / safeMid

        let condition =
            relativeEnergy > 1.01 &&
            relativePeak > 1.00 &&
            level.zeroCrossingRate > 0.04 &&
            (trebleBoost > 1.05 || highVsMid > 0.85)

        guard enoughGapFromBeat && enoughGapFromMicro && condition else {
            return
        }

        lastMicroTrigger = now

        let intensity = min(max((relativeEnergy - 1.0) * 0.30 + 0.08, 0.08), 0.18)
        let sharpness = min(max(level.zeroCrossingRate * 2.0 + highVsMid * 0.08, 0.18), 0.38)

        hapticController.play(style: .microTap, intensity: Float(intensity), sharpness: Float(sharpness))
    }

    /// 분석 상태를 초기화합니다.
    private func resetBeatState() {
        energyEMA = 0
        peakEMA = 0
        lowEMA = 0
        midEMA = 0
        highEMA = 0
        centroidEMA = 0
        lastBeatTime = 0
        lastMicroTrigger = 0
        lastRisingTrigger = 0
        lastDebugLogTime = 0
    }

    /// 레퍼런스 비교용 음악 분석 로그를 출력합니다.
    private func logMusicDebug(
        level: MusicAudioLevel,
        beat: (
            shouldTrigger: Bool,
            style: MusicHapticStyle,
            intensity: Float,
            sharpness: Float,
            uiIntensity: Double,
            uiSharpness: Double,
            uiBass: Double,
            uiTreble: Double,
            emitBassPulse: Bool
        )
    ) {
        let now = CACurrentMediaTime()
        guard now - lastDebugLogTime >= 0.35 || beat.shouldTrigger else {
            return
        }

        lastDebugLogTime = now

        print(
            "[MusicDebug] energy=\(format(level.rms)), peak=\(format(level.peak)), beat=\(beat.shouldTrigger), bass=\(format(beat.uiBass)), treble=\(format(beat.uiTreble)), intensity=\(format(beat.uiIntensity)), mood=\(currentMood?.rawValue ?? "none")"
        )
    }

    /// 로그용 소수점 문자열을 만듭니다.
    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
