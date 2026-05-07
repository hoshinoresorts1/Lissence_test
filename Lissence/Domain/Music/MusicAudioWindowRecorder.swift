/// 마이크 입력을 일정 길이의 오디오 window로 나누어 음악 무드 분석에 전달합니다.

import AVFoundation
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

    // MARK: - 시작 제어

    /// 마이크 입력을 시작하고 window가 준비될 때마다 콜백을 호출합니다.
    func start(
        windowSeconds: Double,
        stepSeconds: Double,
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

                    try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
                    try session.setActive(true)

                    let input = self.engine.inputNode
                    let format = input.outputFormat(forBus: 0)

                    self.sampleRate = format.sampleRate
                    self.windowSamples = Int(format.sampleRate * windowSeconds)
                    self.stepSamples = Int(format.sampleRate * stepSeconds)
                    self.totalSamples = 0
                    self.lastEmittedSample = 0
                    self.ringBuffer.removeAll()
                    self.isRunning = true

                    input.removeTap(onBus: 0)
                    input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                        self?.handle(buffer: buffer, onWindow: onWindow)
                    }

                    self.engine.prepare()
                    try self.engine.start()
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
        }

        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 분석 처리

    /// 입력 buffer를 mono 샘플로 변환하고 준비된 window를 방출합니다.
    private func handle(buffer: AVAudioPCMBuffer, onWindow: @escaping ([Float], Double) -> Void) {
        queue.async {
            self.appendBuffer(buffer)

            guard self.isRunning else {
                return
            }

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
    private func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else {
            return
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

        ringBuffer.append(contentsOf: chunk)
        totalSamples += chunk.count

        let maxBufferSize = max(windowSamples * 2, windowSamples + stepSamples)

        if ringBuffer.count > maxBufferSize {
            ringBuffer.removeFirst(ringBuffer.count - maxBufferSize)
        }
    }
}
