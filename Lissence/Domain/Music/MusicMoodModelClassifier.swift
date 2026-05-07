/// CoreML 음악 무드 분류 모델을 로드하고 예측을 수행합니다.

import CoreML
import Foundation

/// MusicMoodClassifier.mlpackage 또는 컴파일된 mlmodelc를 감싼 앱 전용 classifier입니다.
final class MusicMoodModelClassifier {
    // MARK: - 속성

    /// 로드된 CoreML 모델입니다.
    private let model: MLModel

    /// 모델 입력 feature 이름입니다.
    private let inputName = "input_layer"

    /// MultiArray 출력만 존재할 때 사용할 fallback 라벨 순서입니다.
    private let fallbackLabels = ["Q1", "Q2", "Q3", "Q4"]

    // MARK: - 초기화

    /// 앱 번들에서 음악 무드 모델을 찾아 로드합니다.
    init() throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        if let compiledURL = Bundle.main.url(forResource: "MusicMoodClassifier", withExtension: "mlmodelc") {
            model = try MLModel(contentsOf: compiledURL, configuration: configuration)
        } else if let packageURL = Bundle.main.url(forResource: "MusicMoodClassifier", withExtension: "mlpackage") {
            let compiledURL = try MLModel.compileModel(at: packageURL)
            model = try MLModel(contentsOf: compiledURL, configuration: configuration)
        } else {
            throw NSError(
                domain: "MusicMoodModelClassifier",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "MusicMoodClassifier 모델을 찾지 못했습니다."]
            )
        }
    }

    // MARK: - 예측

    /// 전처리된 모델 입력을 사용해 원시 무드 예측 결과를 반환합니다.
    func predict(input: MLMultiArray) throws -> MusicMoodClassifierResult {
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(multiArray: input)
        ])

        let output = try model.prediction(from: provider)

        if let label = output.featureValue(for: "classLabel")?.stringValue {
            return MusicMoodClassifierResult(
                label: label,
                probabilities: readProbabilityDictionary(output) ?? [:]
            )
        }

        if let result = readMultiArrayOutput(output) {
            return result
        }

        throw NSError(
            domain: "MusicMoodModelClassifier",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey: "모델 출력 classLabel 또는 MultiArray를 찾지 못했습니다. 출력 이름: \(output.featureNames.joined(separator: ", "))"
            ]
        )
    }

    // MARK: - 내부 유틸리티

    /// 모델 출력에서 확률 딕셔너리를 찾아 Swift 딕셔너리로 변환합니다.
    private func readProbabilityDictionary(_ output: MLFeatureProvider) -> [String: Double]? {
        for name in output.featureNames {
            guard let value = output.featureValue(for: name), value.type == .dictionary else {
                continue
            }

            var result: [String: Double] = [:]

            for (key, val) in value.dictionaryValue {
                if let label = key as? String {
                    result[label] = val.doubleValue
                } else if let labelNumber = key as? NSNumber {
                    result[labelNumber.stringValue] = val.doubleValue
                }
            }

            if !result.isEmpty {
                return result
            }
        }

        return nil
    }

    /// 모델 출력이 MultiArray일 때 Q1~Q4 확률로 해석합니다.
    private func readMultiArrayOutput(_ output: MLFeatureProvider) -> MusicMoodClassifierResult? {
        for name in output.featureNames {
            guard let array = output.featureValue(for: name)?.multiArrayValue else {
                continue
            }

            let count = min(4, array.count)
            guard count == 4 else {
                continue
            }

            var probabilities: [String: Double] = [:]
            var bestIndex = 0
            var bestValue = -Double.infinity

            for index in 0..<count {
                let value = array[index].doubleValue
                probabilities[fallbackLabels[index]] = value

                if value > bestValue {
                    bestValue = value
                    bestIndex = index
                }
            }

            return MusicMoodClassifierResult(
                label: fallbackLabels[bestIndex],
                probabilities: probabilities
            )
        }

        return nil
    }
}
