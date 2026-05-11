/// 마이크 입력을 일정 길이의 오디오 window로 나누어 음악 무드 분석에 전달합니다.

import AVFoundation
import Accelerate
import Foundation

/// 실시간 마이크 입력에서 3초 window를 1초 간격으로 방출합니다.
final class MusicAudioWindowRecorder {
    // MARK: - 속성

    /// 마이크 입력을 수집하는 오디오 엔진입니다.
    private let engine = AVAudioEngine()

    /// ring buffer 접근을 직렬화하는 큐입니다.
    private let queue = DispatchQueue(label: "MusicAudioWindowRecorder.queue")

    /// 최근 오디오 샘플을 유지하는 ring buffer입니다.
    private var ringBuffer: [Float] = []

    /// 현재 입력 sample rate입니다.
    private var sampleRate: Double = 44100

    /// window 크기 샘플 수입니다.
    private var windowSamples = 0

    /// window 방출 간격 샘플 수입니다.
    private var stepSamples = 0

    /// recorder 시작 이후 누적 샘플 수입니다.
    private var totalSamples = 0

    /// 마지막으로 window를 방출한 누적 샘플 위치입니다.
    private var lastEmittedSample = 0

    /// 현재 녹음 중인지 여부입니다.
    private var isRunning = false

    /// 마지막으로 오디오 레벨을 방출한 시각입니다.
    private var lastLevelEmissionTime = Date.distantPast

    /// UI 업데이트 부담을 줄이기 위한 레벨 방출 최소 간격입니다.
    private let levelEmissionInterval: TimeInterval = 1.0 / 30.0

    // MARK: - 시작 제어

    /// 마이크 입력을 시작하고 window가 준비될 때마다 콜백을 호출합니다.
    func start(
        windowSeconds: Double,
        stepSeconds: Double,
        onLevel: ((MusicAudioLevel) -> Void)? = nil,
        onWindow: @escaping ([Float], Double) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        stop()

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard let self else { return }

            guard granted else {
                onError(NSError(
                    domain: "MusicAudioWindowRecorder",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "마이크 권한이 거부되었습니다."]
                ))
                return
            }

            DispatchQueue.main.async {
                do {
                    let session = AVAudioSession.sharedInstance()

                    try session.setCategory(
                        .playAndRecord,
                        mode: .measurement,
                        options: [.defaultToSpeaker, .mixWithOthers]
                    )
                    try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
                    try session.setActive(true)
                    self.logAudioSessionRoute(context: "configured")

                    let input = self.engine.inputNode
                    let format = input.outputFormat(forBus: 0)

                    self.sampleRate = format.sampleRate
                    self.windowSamples = Int(format.sampleRate * windowSeconds)
                    self.stepSamples = Int(format.sampleRate * stepSeconds)
                    self.totalSamples = 0
                    self.lastEmittedSample = 0
                    self.lastLevelEmissionTime = .distantPast
                    self.ringBuffer.removeAll()
                    self.isRunning = true

                    input.removeTap(onBus: 0)
                    input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                        self?.handle(buffer: buffer, onLevel: onLevel, onWindow: onWindow)
                    }

                    self.engine.prepare()
                    try self.engine.start()
                    self.logAudioSessionRoute(context: "engine started")
                } catch {
                    onError(error)
                }
            }
        }
    }

    /// 마이크 입력을 중지하고 오디오 세션을 정리합니다.
    func stop() {
        queue.sync {
            isRunning = false
            ringBuffer.removeAll()
            totalSamples = 0
            lastEmittedSample = 0
            lastLevelEmissionTime = .distantPast
        }

        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 분석 처리

    /// 입력 buffer를 mono 샘플로 변환하고 준비된 window를 방출합니다.
    private func handle(
        buffer: AVAudioPCMBuffer,
        onLevel: ((MusicAudioLevel) -> Void)?,
        onWindow: @escaping ([Float], Double) -> Void
    ) {
        queue.async {
            let chunk = self.makeMonoSamples(from: buffer)
            self.appendSamples(chunk)

            guard self.isRunning else {
                return
            }

            self.emitLevelIfNeeded(from: chunk, onLevel: onLevel)

            guard self.ringBuffer.count >= self.windowSamples else {
                return
            }

            guard self.totalSamples - self.lastEmittedSample >= self.stepSamples else {
                return
            }

            self.lastEmittedSample = self.totalSamples

            let start = max(0, self.ringBuffer.count - self.windowSamples)
            let window = Array(self.ringBuffer[start..<self.ringBuffer.count])
            let currentRate = self.sampleRate

            DispatchQueue.global(qos: .userInitiated).async {
                onWindow(window, currentRate)
            }
        }
    }

    /// AVAudioPCMBuffer의 채널을 mono Float 샘플로 합칩니다.
    private func makeMonoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var chunk: [Float] = []
        chunk.reserveCapacity(frameLength)

        if channelCount == 1 {
            let data = channelData[0]

            for index in 0..<frameLength {
                chunk.append(data[index])
            }
        } else {
            for index in 0..<frameLength {
                var value: Float = 0

                for channel in 0..<channelCount {
                    value += channelData[channel][index]
                }

                chunk.append(value / Float(channelCount))
            }
        }

        return chunk
    }

    /// mono 샘플을 ring buffer에 추가합니다.
    private func appendSamples(_ samples: [Float]) {
        guard !samples.isEmpty else {
            return
        }

        ringBuffer.append(contentsOf: samples)
        totalSamples += samples.count

        let maxBufferSize = max(windowSamples * 2, windowSamples + stepSamples)

        if ringBuffer.count > maxBufferSize {
            ringBuffer.removeFirst(ringBuffer.count - maxBufferSize)
        }
    }

    /// 실시간 UI와 햅틱에 필요한 RMS/peak 레벨을 일정 간격으로 방출합니다.
    private func emitLevelIfNeeded(from samples: [Float], onLevel: ((MusicAudioLevel) -> Void)?) {
        guard let onLevel, !samples.isEmpty else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastLevelEmissionTime) >= levelEmissionInterval else {
            return
        }

        lastLevelEmissionTime = now

        var sum: Float = 0
        var peak: Float = 0

        for sample in samples {
            sum += sample * sample
            peak = max(peak, abs(sample))
        }

        let rms = sqrt(sum / Float(samples.count))
        let zcr = calculateZeroCrossingRate(samples)
        let fft = calculateFFT(samples, sampleRate: Float(sampleRate))
        let level = MusicAudioLevel(
            rms: Double(rms),
            peak: Double(peak),
            zeroCrossingRate: Double(zcr),
            lowEnergy: Double(fft.low),
            midEnergy: Double(fft.mid),
            highEnergy: Double(fft.high),
            centroid: Double(fft.centroid),
            timestamp: now
        )

        DispatchQueue.main.async {
            onLevel(level)
        }
    }

    /// zero crossing rate를 계산합니다.
    private func calculateZeroCrossingRate(_ samples: [Float]) -> Float {
        guard samples.count > 1 else {
            return 0
        }

        var crossings = 0
        var previous = samples[0]

        for index in 1..<samples.count {
            let sample = samples[index]

            if (previous >= 0 && sample < 0) || (previous < 0 && sample >= 0) {
                crossings += 1
            }

            previous = sample
        }

        return Float(crossings) / Float(samples.count)
    }

    /// 레퍼런스 음악 엔진과 같은 low/mid/high/centroid FFT feature를 계산합니다.
    private func calculateFFT(_ samples: [Float], sampleRate: Float) -> (low: Float, mid: Float, high: Float, centroid: Float) {
        var size = 1

        while size * 2 <= samples.count {
            size *= 2
        }

        guard size >= 2 else {
            return (0, 0, 0, 0)
        }

        var windowedSamples = Array(samples.prefix(size))
        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        vDSP_vmul(windowedSamples, 1, window, 1, &windowedSamples, 1, vDSP_Length(size))

        let log2n = vDSP_Length(log2(Float(size)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return (0, 0, 0, 0)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var real = [Float](repeating: 0, count: size / 2)
        var imag = [Float](repeating: 0, count: size / 2)
        var low: Float = 0
        var mid: Float = 0
        var high: Float = 0
        var weightedSum: Float = 0
        var total: Float = 0

        real.withUnsafeMutableBufferPointer { realPointer in
            imag.withUnsafeMutableBufferPointer { imagPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imagPointer.baseAddress!)

                windowedSamples.withUnsafeBufferPointer { samplePointer in
                    samplePointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) { complexPointer in
                        vDSP_ctoz(complexPointer, 2, &split, 1, vDSP_Length(size / 2))
                    }
                }

                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                var magnitudes = [Float](repeating: 0, count: size / 2)
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(size / 2))

                let binFrequency = sampleRate / Float(size)

                for index in 1..<magnitudes.count {
                    let frequency = Float(index) * binFrequency
                    let magnitude = magnitudes[index]

                    total += magnitude
                    weightedSum += frequency * magnitude

                    if frequency < 200 {
                        low += magnitude
                    } else if frequency < 2_000 {
                        mid += magnitude
                    } else {
                        high += magnitude
                    }
                }
            }
        }

        let centroid = total > 0 ? weightedSum / total : 0
        return (low, mid, high, centroid)
    }

    /// 음악모드 마이크 입력 테스트에 필요한 현재 오디오 세션 라우트를 출력합니다.
    private func logAudioSessionRoute(context: String) {
        let session = AVAudioSession.sharedInstance()
        let inputs = session.currentRoute.inputs
            .map { "\($0.portName)(\($0.portType.rawValue))" }
            .joined(separator: ", ")
        let outputs = session.currentRoute.outputs
            .map { "\($0.portName)(\($0.portType.rawValue))" }
            .joined(separator: ", ")
        let inputDescription = inputs.isEmpty ? "none" : inputs
        let outputDescription = outputs.isEmpty ? "none" : outputs

        print(
            "[MusicAudioSession] \(context) category=\(session.category.rawValue), mode=\(session.mode.rawValue), inputs=\(inputDescription), outputs=\(outputDescription)"
        )

        if session.currentRoute.inputs.contains(where: { $0.portType == .bluetoothHFP }) ||
            session.currentRoute.outputs.contains(where: { $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP || $0.portType == .headphones }) {
            print("[MusicAudioSession] external audio route detected; speaker-to-microphone recapture may be weak or unavailable.")
        }
    }
}
