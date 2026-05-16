/// 마이크 오디오 샘플을 음악 무드 CoreML 모델 입력 feature로 변환합니다.

import Accelerate
import CoreML
import Foundation

/// 3초 오디오 샘플에서 spectrogram, MFCC, Mel feature를 생성합니다.
final class AudioFeatureExtractor {
    // MARK: - 속성

    /// 모델 학습에 사용한 목표 sample rate입니다.
    private let targetSampleRate: Double = 22050

    /// 모델 입력으로 사용할 오디오 길이입니다.
    private let duration: Double = 3.0

    /// STFT FFT 크기입니다.
    private let nFFT = 2048

    /// STFT hop length입니다.
    private let hopLength = 512

    /// Mel filter bank 개수입니다.
    private let melBins = 128

    /// 유지할 MFCC 계수 개수입니다.
    private let mfccBins = 20

    /// 모델 입력 높이입니다.
    private let targetHeight = 128

    /// 모델 입력 너비입니다.
    private let targetWidth = 128

    /// 채널별 정규화 평균입니다.
    private let means: [Float]

    /// 채널별 정규화 표준편차입니다.
    private let stds: [Float]

    /// feature 채널 순서입니다.
    private let featureOrder: [String]

    // MARK: - 초기화

    /// 학습 통계를 로드해 feature extractor를 준비합니다.
    init() {
        let stats = TrainingStats.load()
        means = stats.means
        stds = stats.stds
        featureOrder = stats.featureOrder

        debugLog("stats means=\(means), stds=\(stds), featureOrder=\(featureOrder), labels=\(stats.labelNames)")
    }

    // MARK: - 입력 생성

    /// 원본 오디오 샘플을 CoreML 모델 입력 MultiArray로 변환합니다.
    func makeInput(samples: [Float], sampleRate: Double) throws -> MLMultiArray {
        let audio = prepareAudio(samples: samples, sampleRate: sampleRate)
        let magnitude = stftMagnitude(audio)
        let power = magnitude.map { row in row.map { $0 * $0 } }

        let spec = amplitudeToDB(magnitude)
        let melPower = applyMelFilter(power)
        let mel = powerToDB(melPower)
        let mfcc = dctType2Ortho(mel, keep: mfccBins)

        let spec128 = resizeArea(spec, newRows: targetHeight, newCols: targetWidth)
        let mfcc128 = resizeArea(mfcc, newRows: targetHeight, newCols: targetWidth)
        let mel128 = resizeArea(mel, newRows: targetHeight, newCols: targetWidth)
        let featureMaps = [
            "spec": spec128,
            "spectrogram": spec128,
            "mfcc": mfcc128,
            "mel": mel128,
            "mel_spectrogram": mel128
        ]

        let array = try MLMultiArray(
            shape: [1, NSNumber(value: targetHeight), NSNumber(value: targetWidth), 3],
            dataType: .float32
        )

        var preview: [Float] = []

        for row in 0..<targetHeight {
            for column in 0..<targetWidth {
                for channel in 0..<3 {
                    let key = channel < featureOrder.count ? featureOrder[channel].lowercased() : ""
                    let feature = featureMaps[key] ?? [spec128, mfcc128, mel128][channel]
                    let value = (feature[row][column] - means[channel]) / max(stds[channel], 1e-8)
                    let index = row * targetWidth * 3 + column * 3 + channel
                    array[index] = NSNumber(value: value)

                    if preview.count < 8 {
                        preview.append(value)
                    }
                }
            }
        }

        debugLog("extracted feature vector size=\(array.count), shape=\(array.shape)")
        debugLog("normalized feature preview=\(preview.map { String(format: "%.4f", $0) }.joined(separator: ", "))")

        return array
    }

    // MARK: - 오디오 전처리

    /// 입력 샘플을 목표 sample rate와 길이에 맞춥니다.
    private func prepareAudio(samples: [Float], sampleRate: Double) -> [Float] {
        let resampled = resampleLinear(samples: samples, from: sampleRate, to: targetSampleRate)
        let targetCount = Int(targetSampleRate * duration)

        if resampled.count >= targetCount {
            return Array(resampled.prefix(targetCount))
        }

        return resampled + [Float](repeating: 0, count: targetCount - resampled.count)
    }

    /// 선형 보간으로 sample rate를 변환합니다.
    private func resampleLinear(samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard !samples.isEmpty else {
            return []
        }

        if abs(sourceRate - targetRate) < 1 {
            return samples
        }

        let ratio = targetRate / sourceRate
        let newCount = max(1, Int(Double(samples.count) * ratio))
        var output = [Float](repeating: 0, count: newCount)

        for index in 0..<newCount {
            let sourceIndex = Double(index) / ratio
            let left = Int(floor(sourceIndex))
            let right = min(left + 1, samples.count - 1)
            let fraction = Float(sourceIndex - Double(left))
            output[index] = samples[left] * (1 - fraction) + samples[right] * fraction
        }

        return output
    }

    // MARK: - Feature 계산

    /// SciPy 방식에 맞춘 STFT magnitude 행렬을 계산합니다.
    private func stftMagnitude(_ samples: [Float]) -> [[Float]] {
        let boundaryPad = nFFT / 2
        var padded = [Float](repeating: 0, count: boundaryPad)
        padded.append(contentsOf: samples)
        padded.append(contentsOf: [Float](repeating: 0, count: boundaryPad))

        let remainder = (padded.count - nFFT) % hopLength
        if remainder != 0 {
            padded.append(contentsOf: [Float](repeating: 0, count: hopLength - remainder))
        }

        let frameCount = max(1, 1 + (padded.count - nFFT) / hopLength)
        let binCount = nFFT / 2 + 1
        let window = hannWindow(nFFT)
        let windowSum = max(window.reduce(0, +), 1e-10)
        let log2n = vDSP_Length(log2(Float(nFFT)))

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return Array(repeating: [Float](repeating: 0, count: frameCount), count: binCount)
        }

        var result = Array(repeating: [Float](repeating: 0, count: frameCount), count: binCount)

        for frameIndex in 0..<frameCount {
            let start = frameIndex * hopLength
            var frame = Array(padded[start..<start + nFFT])
            vDSP.multiply(frame, window, result: &frame)

            var real = [Float](repeating: 0, count: nFFT / 2)
            var imag = [Float](repeating: 0, count: nFFT / 2)

            real.withUnsafeMutableBufferPointer { realPointer in
                imag.withUnsafeMutableBufferPointer { imagPointer in
                    var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imagPointer.baseAddress!)

                    frame.withUnsafeBufferPointer { framePointer in
                        framePointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: nFFT / 2) { complexPointer in
                            vDSP_ctoz(complexPointer, 2, &split, 1, vDSP_Length(nFFT / 2))
                        }
                    }

                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }

            result[0][frameIndex] = abs(real[0]) / windowSum
            result[binCount - 1][frameIndex] = abs(imag[0]) / windowSum

            if binCount > 2 {
                for bin in 1..<(binCount - 1) {
                    result[bin][frameIndex] = sqrt(real[bin] * real[bin] + imag[bin] * imag[bin]) / windowSum
                }
            }
        }

        vDSP_destroy_fftsetup(setup)
        return result
    }

    /// amplitude 행렬을 dB 스케일로 변환합니다.
    private func amplitudeToDB(_ input: [[Float]]) -> [[Float]] {
        convertToDB(input, multiplier: 20.0)
    }

    /// power 행렬을 dB 스케일로 변환합니다.
    private func powerToDB(_ input: [[Float]]) -> [[Float]] {
        convertToDB(input, multiplier: 10.0)
    }

    /// 로그 스케일 변환과 dynamic range 제한을 적용합니다.
    private func convertToDB(_ input: [[Float]], multiplier: Float) -> [[Float]] {
        let flat = input.flatMap { $0 }
        let ref = max((flat.max() ?? 0) + 1e-10, 1e-10)
        var output = input
        var maxValue = -Float.greatestFiniteMagnitude

        for row in 0..<output.count {
            for column in 0..<output[row].count {
                let value = multiplier * log10(max(output[row][column], 1e-10)) - multiplier * log10(ref)
                output[row][column] = value
                maxValue = max(maxValue, value)
            }
        }

        let floorValue = maxValue - 80.0

        for row in 0..<output.count {
            for column in 0..<output[row].count {
                output[row][column] = max(output[row][column], floorValue)
            }
        }

        return output
    }

    /// power spectrogram에 Mel filter bank를 적용합니다.
    private func applyMelFilter(_ power: [[Float]]) -> [[Float]] {
        let filters = melFilterBank()
        let frames = power.first?.count ?? 0
        var output = Array(repeating: [Float](repeating: 0, count: frames), count: melBins)

        for melIndex in 0..<melBins {
            for frame in 0..<frames {
                var sum: Float = 0

                for bin in 0..<power.count {
                    sum += filters[melIndex][bin] * power[bin][frame]
                }

                output[melIndex][frame] = sum
            }
        }

        return output
    }

    /// SciPy와 유사한 Mel filter bank를 생성합니다.
    private func melFilterBank() -> [[Float]] {
        let fmax = Float(targetSampleRate / 2.0)
        let minMel = hzToMel(0)
        let maxMel = hzToMel(fmax)

        var hzPoints: [Float] = []
        for index in 0..<(melBins + 2) {
            let mel = minMel + (maxMel - minMel) * Float(index) / Float(melBins + 1)
            hzPoints.append(melToHz(mel))
        }

        let bins = hzPoints.map { Int(floor(Float(nFFT + 1) * $0 / Float(targetSampleRate))) }
        var filters = Array(repeating: [Float](repeating: 0, count: nFFT / 2 + 1), count: melBins)

        for index in 1...melBins {
            let left = bins[index - 1]
            var center = bins[index]
            var right = bins[index + 1]

            if center <= left {
                center = left + 1
            }
            if right <= center {
                right = center + 1
            }

            for bin in left..<center where bin >= 0 && bin < filters[index - 1].count {
                filters[index - 1][bin] = Float(bin - left) / Float(center - left)
            }

            for bin in center..<right where bin >= 0 && bin < filters[index - 1].count {
                filters[index - 1][bin] = Float(right - bin) / Float(right - center)
            }
        }

        for melIndex in 0..<melBins {
            let denominator = max(hzPoints[melIndex + 2] - hzPoints[melIndex], 1e-10)
            let enorm = 2.0 / denominator

            for bin in 0..<filters[melIndex].count {
                filters[melIndex][bin] *= enorm
            }
        }

        return filters
    }

    /// Mel spectrogram에서 DCT-II ortho 방식으로 MFCC를 계산합니다.
    private func dctType2Ortho(_ input: [[Float]], keep: Int) -> [[Float]] {
        let rows = input.count
        let columns = input.first?.count ?? 0

        guard rows > 0, columns > 0 else {
            return Array(repeating: [Float](repeating: 0, count: columns), count: keep)
        }

        var output = Array(repeating: [Float](repeating: 0, count: columns), count: keep)

        for coefficient in 0..<keep {
            let scale = coefficient == 0 ? sqrt(1.0 / Float(rows)) : sqrt(2.0 / Float(rows))

            for column in 0..<columns {
                var sum: Float = 0

                for row in 0..<rows {
                    let angle = Float.pi * Float(coefficient) * (Float(row) + 0.5) / Float(rows)
                    sum += input[row][column] * cos(angle)
                }

                output[coefficient][column] = scale * sum
            }
        }

        return output
    }

    /// 2차원 feature 행렬을 area 평균 방식으로 리사이즈합니다.
    private func resizeArea(_ input: [[Float]], newRows: Int, newCols: Int) -> [[Float]] {
        let rows = input.count
        let cols = input.first?.count ?? 0

        guard rows > 0, cols > 0 else {
            return Array(repeating: [Float](repeating: 0, count: newCols), count: newRows)
        }

        var output = Array(repeating: [Float](repeating: 0, count: newCols), count: newRows)
        let rowScale = Float(rows) / Float(newRows)
        let colScale = Float(cols) / Float(newCols)

        for row in 0..<newRows {
            let rowStart = Float(row) * rowScale
            let rowEnd = Float(row + 1) * rowScale
            let r0 = Int(floor(rowStart))
            let r1 = min(Int(ceil(rowEnd)), rows)

            for column in 0..<newCols {
                let colStart = Float(column) * colScale
                let colEnd = Float(column + 1) * colScale
                let c0 = Int(floor(colStart))
                let c1 = min(Int(ceil(colEnd)), cols)

                var sum: Float = 0
                var weightSum: Float = 0

                for sourceRow in r0..<r1 {
                    let top = max(rowStart, Float(sourceRow))
                    let bottom = min(rowEnd, Float(sourceRow + 1))
                    let rowWeight = max(0, bottom - top)

                    for sourceColumn in c0..<c1 {
                        let left = max(colStart, Float(sourceColumn))
                        let right = min(colEnd, Float(sourceColumn + 1))
                        let colWeight = max(0, right - left)
                        let weight = rowWeight * colWeight
                        sum += input[sourceRow][sourceColumn] * weight
                        weightSum += weight
                    }
                }

                output[row][column] = weightSum > 0 ? sum / weightSum : input[min(r0, rows - 1)][min(c0, cols - 1)]
            }
        }

        return output
    }

    // MARK: - 내부 유틸리티

    /// Hann window 값을 생성합니다.
    private func hannWindow(_ count: Int) -> [Float] {
        (0..<count).map { index in
            0.5 - 0.5 * cos(2 * Float.pi * Float(index) / Float(count))
        }
    }

    /// Hz를 Mel로 변환합니다.
    private func hzToMel(_ hz: Float) -> Float {
        2595.0 * log10(1.0 + hz / 700.0)
    }

    /// Mel을 Hz로 변환합니다.
    private func melToHz(_ mel: Float) -> Float {
        700.0 * (pow(10.0, mel / 2595.0) - 1.0)
    }

    /// Debug 빌드에서만 음악모드 feature 로그를 출력합니다.
    private func debugLog(_ message: String) {
        #if DEBUG
        print("[MusicAudioFeatureExtractor] \(message)")
        #endif
    }
}
