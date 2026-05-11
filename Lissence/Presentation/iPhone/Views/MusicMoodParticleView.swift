/// 음악 모드의 무드, 에너지, 비트 펄스에 반응하는 파티클 배경입니다.

import SwiftUI

/// 파티클 하나의 시뮬레이션 상태입니다.
private struct MusicParticle: Identifiable {
    /// SwiftUI 식별자입니다.
    let id = UUID()

    /// 파티클 시작 위치입니다.
    var origin: CGPoint

    /// 파티클 이동 속도입니다.
    var velocity: CGVector

    /// 파티클에 적용할 중력 계수입니다.
    var gravity: CGFloat

    /// 파티클 크기입니다.
    var size: CGFloat

    /// 파티클 색상입니다.
    var color: Color

    /// 파티클 생성 시각입니다.
    var spawnTime: TimeInterval

    /// 파티클 수명입니다.
    var lifetime: TimeInterval

    /// 파티클 블러 반경입니다.
    var blur: CGFloat
}

/// 충격파 원형 이펙트 상태입니다.
private struct MusicWave: Identifiable {
    /// SwiftUI 식별자입니다.
    let id = UUID()

    /// 충격파 중심입니다.
    var center: CGPoint

    /// 충격파 색상입니다.
    var color: Color

    /// 충격파 생성 시각입니다.
    var spawnTime: TimeInterval

    /// 충격파 수명입니다.
    var lifetime: TimeInterval

    /// 충격파 최대 반경입니다.
    var maxRadius: CGFloat

    /// 충격파 선 두께입니다.
    var lineWidth: CGFloat
}

/// Canvas 밖에서 유지되는 파티클 시뮬레이션 상태입니다.
private final class MusicParticleState {
    // MARK: - 입력 상태

    /// 현재 음악 무드입니다.
    var mood: MusicMood?

    /// 0...1 범위의 음악 에너지입니다.
    var intensity: Double = 0

    /// peak 기반 선명도입니다.
    var sharpness: Double = 0

    /// bass band 기반 충격파 강도입니다.
    var bass: Double = 0

    /// treble band 기반 sparkle 강도입니다.
    var treble: Double = 0

    /// 충격파 중심 보정값입니다.
    var burstCenterOffset: CGSize = .zero

    /// Canvas 크기입니다.
    var canvasSize: CGSize = .zero

    /// 마지막으로 처리한 beat pulse입니다.
    var seenBeatPulse = 0

    /// 마지막으로 처리한 bass pulse입니다.
    var seenBassPulse = 0

    // MARK: - 시뮬레이션 상태

    /// 상시 배경 파티클입니다.
    var ambient: [MusicParticle] = []

    /// 밝은 sparkle 파티클입니다.
    var sparkles: [MusicParticle] = []

    /// 비트 순간 burst 파티클입니다.
    var bursts: [MusicParticle] = []

    /// 강한 입력의 원형 충격파입니다.
    var waves: [MusicWave] = []

    /// ambient 생성 누적값입니다.
    var ambientAccumulator: Double = 0

    /// sparkle 생성 누적값입니다.
    var sparkleAccumulator: Double = 0

    /// 마지막 프레임 시각입니다.
    var lastTick: TimeInterval = 0

    /// 처리 대기 중인 beat 수입니다.
    var pendingBeats = 0

    /// 처리 대기 중인 강한 beat 수입니다.
    var pendingBassBeats = 0

    /// 자동 radial burst를 마지막으로 예약한 시각입니다.
    var lastAutoBeatTime: TimeInterval = 0

    /// 자동 shockwave를 마지막으로 예약한 시각입니다.
    var lastAutoBassTime: TimeInterval = 0

    // MARK: - 상태 업데이트

    /// 한 프레임의 파티클 시뮬레이션을 진행합니다.
    func tick(now: TimeInterval) {
        guard canvasSize.width > 1, canvasSize.height > 1 else {
            return
        }

        let delta = lastTick > 0 ? max(0, min(0.05, now - lastTick)) : 1.0 / 60.0
        lastTick = now

        while pendingBeats > 0 {
            spawnBeatBurst(now: now)
            pendingBeats -= 1
        }

        while pendingBassBeats > 0 {
            spawnShockwave(now: now)
            pendingBassBeats -= 1
        }

        spawnAmbient(delta: delta, now: now)
        spawnSparkles(delta: delta, now: now)
        removeExpiredParticles(now: now)
    }

    /// beat burst 생성을 예약합니다.
    func enqueueBeat() {
        pendingBeats = min(pendingBeats + 1, 4)
    }

    /// bass shockwave 생성을 예약합니다.
    func enqueueBassBeat() {
        pendingBassBeats = min(pendingBassBeats + 1, 2)
    }

    // MARK: - 파티클 생성

    /// 상시 배경 파티클을 생성합니다.
    private func spawnAmbient(delta: TimeInterval, now: TimeInterval) {
        let safeIntensity = max(0.40, min(1.0, intensity))
        let rate: Double

        switch mood {
        case .happy:
            rate = 60
        case .angry:
            rate = 80
        case .sad:
            rate = 35
        case .relaxed:
            rate = 25
        case nil:
            rate = 36
        }

        ambientAccumulator += delta * rate * safeIntensity
        let spawnCount = min(Int(ambientAccumulator), 5)
        ambientAccumulator -= Double(spawnCount)

        for _ in 0..<spawnCount {
            ambient.append(makeAmbient(now: now))
        }
    }

    /// 고음/peak 느낌의 sparkle을 생성합니다.
    private func spawnSparkles(delta: TimeInterval, now: TimeInterval) {
        sparkleAccumulator += delta * 90 * max(0, treble) * (0.4 + max(0, sharpness))
        let spawnCount = min(Int(sparkleAccumulator), 8)
        sparkleAccumulator -= Double(spawnCount)

        for _ in 0..<spawnCount {
            sparkles.append(makeSparkle(now: now))
        }
    }

    /// 무드별 ambient 파티클을 만듭니다.
    private func makeAmbient(now: TimeInterval) -> MusicParticle {
        let size = canvasSize
        let bassValue = CGFloat(max(0, min(1, bass)))

        let origin: CGPoint
        let velocity: CGVector
        let gravity: CGFloat
        let lifetime: TimeInterval
        let blur: CGFloat
        let baseSize: CGFloat

        switch mood {
        case .happy:
            origin = CGPoint(x: .random(in: 0...size.width), y: size.height + 6)
            velocity = CGVector(dx: .random(in: -50...50), dy: -130 + .random(in: -40...40))
            gravity = 18
            lifetime = .random(in: 1.4...2.5)
            blur = 1.0
            baseSize = .random(in: 6...12)
        case .angry:
            origin = CGPoint(x: size.width / 2 + burstCenterOffset.width, y: size.height / 2 + burstCenterOffset.height)
            velocity = CGVector(dx: .random(in: -260...260), dy: .random(in: -260...260))
            gravity = 0
            lifetime = .random(in: 0.45...1.0)
            blur = 0.5
            baseSize = .random(in: 6...14)
        case .sad:
            origin = CGPoint(x: .random(in: 0...size.width), y: -8)
            velocity = CGVector(dx: .random(in: -10...10), dy: 70 + .random(in: -15...15))
            gravity = 25
            lifetime = .random(in: 2.6...4.2)
            blur = 1.4
            baseSize = .random(in: 3...7)
        case .relaxed:
            origin = CGPoint(x: .random(in: 0...size.width), y: .random(in: 0...size.height))
            velocity = CGVector(dx: .random(in: -25...25), dy: -25 + .random(in: -15...15))
            gravity = -8
            lifetime = .random(in: 3.0...5.2)
            blur = 2.0
            baseSize = .random(in: 8...16)
        case nil:
            lifetime = .random(in: 1.8...3.0)
            blur = 1.3
            baseSize = .random(in: 5...10)
            origin = CGPoint(x: .random(in: 0...size.width), y: size.height + 6)
            velocity = CGVector(dx: .random(in: -34...34), dy: -95 + .random(in: -30...30))
            gravity = 12
        }

        return MusicParticle(
            origin: origin,
            velocity: velocity,
            gravity: gravity,
            size: baseSize + bassValue * 6,
            color: palette.randomElement() ?? .white,
            spawnTime: now,
            lifetime: lifetime,
            blur: blur
        )
    }

    /// sparkle 파티클을 만듭니다.
    private func makeSparkle(now: TimeInterval) -> MusicParticle {
        return MusicParticle(
            origin: CGPoint(x: .random(in: 0...canvasSize.width), y: .random(in: 0...canvasSize.height)),
            velocity: CGVector(dx: .random(in: -30...30), dy: .random(in: -30...30)),
            gravity: 0,
            size: .random(in: 1.5...3.5),
            color: .white.opacity(0.92),
            spawnTime: now,
            lifetime: .random(in: 0.3...0.7),
            blur: 0.3
        )
    }

    /// beat 순간 burst를 생성합니다.
    private func spawnBeatBurst(now: TimeInterval) {
        let center = CGPoint(
            x: canvasSize.width / 2 + burstCenterOffset.width,
            y: canvasSize.height / 2 + burstCenterOffset.height
        )
        let count = 18 + Int(intensity * 26)
        let baseSpeed = 220.0 + intensity * 280.0
        let bassExtra = CGFloat(max(0, min(1, bass))) * 4

        print("[MusicParticle] burst count=\(count), radius=0.000, intensity=\(String(format: "%.3f", intensity))")

        for index in 0..<count {
            let angle = Double(index) / Double(count) * 2 * .pi + .random(in: -0.06...0.06)
            let speed = baseSpeed * .random(in: 0.7...1.1)
            let velocity = CGVector(dx: CGFloat(cos(angle) * speed), dy: CGFloat(sin(angle) * speed))

            bursts.append(MusicParticle(
                origin: center,
                velocity: velocity,
                gravity: 60,
                size: .random(in: 3...8) + bassExtra,
                color: palette.randomElement() ?? .white,
                spawnTime: now,
                lifetime: .random(in: 0.5...0.9),
                blur: 0.6
            ))
        }
    }

    /// 강한 입력의 shockwave를 생성합니다.
    private func spawnShockwave(now: TimeInterval) {
        let radius = max(canvasSize.width, canvasSize.height) * 0.7

        print("[MusicParticle] shockwave count=1, radius=\(String(format: "%.3f", radius)), intensity=\(String(format: "%.3f", intensity))")

        waves.append(MusicWave(
            center: CGPoint(
                x: canvasSize.width / 2 + burstCenterOffset.width,
                y: canvasSize.height / 2 + burstCenterOffset.height
            ),
            color: palette.first ?? .white,
            spawnTime: now,
            lifetime: 0.8,
            maxRadius: radius,
            lineWidth: 6
        ))
    }

    /// 만료된 파티클을 제거하고 개수를 제한합니다.
    private func removeExpiredParticles(now: TimeInterval) {
        ambient.removeAll { now - $0.spawnTime >= $0.lifetime }
        sparkles.removeAll { now - $0.spawnTime >= $0.lifetime }
        bursts.removeAll { now - $0.spawnTime >= $0.lifetime }
        waves.removeAll { now - $0.spawnTime >= $0.lifetime }

        if ambient.count > 300 { ambient.removeFirst(ambient.count - 300) }
        if sparkles.count > 250 { sparkles.removeFirst(sparkles.count - 250) }
        if bursts.count > 500 { bursts.removeFirst(bursts.count - 500) }
        if waves.count > 8 { waves.removeFirst(waves.count - 8) }
    }

    // MARK: - 내부 유틸리티

    /// 무드별 파티클 색상 팔레트입니다.
    private var palette: [Color] {
        switch mood {
        case .happy:
            return [
                Color(red: 1.00, green: 0.85, blue: 0.30),
                Color(red: 1.00, green: 0.55, blue: 0.30),
                Color(red: 1.00, green: 0.40, blue: 0.65)
            ]
        case .angry:
            return [
                Color(red: 1.00, green: 0.20, blue: 0.20),
                Color(red: 1.00, green: 0.40, blue: 0.10),
                Color(red: 0.85, green: 0.10, blue: 0.30)
            ]
        case .sad:
            return [
                Color(red: 0.40, green: 0.55, blue: 1.00),
                Color(red: 0.30, green: 0.40, blue: 0.85),
                Color(red: 0.55, green: 0.65, blue: 0.95)
            ]
        case .relaxed:
            return [
                Color(red: 0.50, green: 0.95, blue: 0.75),
                Color(red: 0.45, green: 0.85, blue: 0.95),
                Color(red: 0.70, green: 0.95, blue: 0.55)
            ]
        case nil:
            return [
                Color(red: 0.62, green: 0.38, blue: 0.95),
                Color(red: 0.35, green: 0.60, blue: 1.00),
                Color(red: 0.35, green: 0.95, blue: 0.80)
            ]
        }
    }
}

/// Reference_MusicMode_Animated의 Canvas 파티클 구조를 음악모드 도메인에 맞춘 뷰입니다.
struct MusicMoodParticleView: View {
    // MARK: - 속성

    /// 현재 분석된 음악 무드입니다.
    let mood: MusicMood?

    /// 0...1 범위의 실시간 오디오 에너지입니다.
    let intensity: Double

    /// peak 또는 선명도 값입니다.
    let sharpness: Double

    /// bass band 기반 shockwave 강도입니다.
    let bass: Double

    /// treble band 기반 sparkle 강도입니다.
    let treble: Double

    /// beat pulse 카운터입니다.
    let beatPulse: Int

    /// 강한 beat pulse 카운터입니다.
    let bassPulse: Int

    /// burst와 shockwave 중심 보정값입니다.
    var burstCenterOffset: CGSize = .zero

    /// 시뮬레이션 상태입니다.
    @State private var state = MusicParticleState()

    // MARK: - 본문

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                Canvas { context, size in
                    updateState(size: size, now: timeline.date.timeIntervalSinceReferenceDate)
                    drawAll(context: context, now: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
            .onAppear {
                state.canvasSize = geometry.size
                state.seenBeatPulse = beatPulse
                state.seenBassPulse = bassPulse
            }
            .onChange(of: geometry.size) { _, newSize in
                state.canvasSize = newSize
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - 상태 업데이트

    /// 외부 입력을 시뮬레이션 상태에 반영합니다.
    private func updateState(size: CGSize, now: TimeInterval) {
        state.canvasSize = size
        state.mood = mood
        state.intensity = intensity
        state.sharpness = sharpness
        state.bass = bass
        state.treble = treble
        state.burstCenterOffset = burstCenterOffset

        let beatDelta = max(0, beatPulse &- state.seenBeatPulse)
        if beatDelta > 0 {
            for _ in 0..<min(beatDelta, 3) {
                state.enqueueBeat()
            }
            state.seenBeatPulse = beatPulse
        }

        let bassDelta = max(0, bassPulse &- state.seenBassPulse)
        if bassDelta > 0 {
            for _ in 0..<min(bassDelta, 2) {
                state.enqueueBassBeat()
            }
            state.seenBassPulse = bassPulse
        }

        state.tick(now: now)
    }

    // MARK: - 렌더링

    /// 모든 파티클과 wave를 그립니다.
    private func drawAll(context: GraphicsContext, now: TimeInterval) {
        drawWaves(context: context, now: now)
        drawParticles(context: context, particles: state.ambient, now: now)
        drawParticles(context: context, particles: state.bursts, now: now)
        drawParticles(context: context, particles: state.sparkles, now: now)
    }

    /// wave 이펙트를 그립니다.
    private func drawWaves(context: GraphicsContext, now: TimeInterval) {
        for wave in state.waves {
            let age = now - wave.spawnTime
            guard age >= 0, age < wave.lifetime else {
                continue
            }

            let progress = CGFloat(age / wave.lifetime)
            let radius = wave.maxRadius * progress
            let rect = CGRect(
                x: wave.center.x - radius,
                y: wave.center.y - radius,
                width: radius * 2,
                height: radius * 2
            )

            var localContext = context
            localContext.opacity = Double((1 - progress) * 0.55)
            localContext.stroke(
                Path(ellipseIn: rect),
                with: .color(wave.color),
                lineWidth: wave.lineWidth * (1 - progress * 0.6)
            )
        }
    }

    /// 파티클 배열을 그립니다.
    private func drawParticles(context: GraphicsContext, particles: [MusicParticle], now: TimeInterval) {
        for particle in particles {
            let age = now - particle.spawnTime
            guard age >= 0, age < particle.lifetime else {
                continue
            }

            let time = CGFloat(age)
            let x = particle.origin.x + particle.velocity.dx * time
            let y = particle.origin.y + particle.velocity.dy * time + 0.5 * particle.gravity * time * time
            let progress = age / particle.lifetime
            let alpha = max(0, min(1.0, progress / 0.12) * (1.0 - progress))
            let rect = CGRect(
                x: x - particle.size / 2,
                y: y - particle.size / 2,
                width: particle.size,
                height: particle.size
            )

            var localContext = context
            localContext.opacity = alpha
            if particle.blur > 0.05 {
                localContext.addFilter(.blur(radius: particle.blur))
            }
            localContext.fill(Path(ellipseIn: rect), with: .color(particle.color))
        }
    }
}
