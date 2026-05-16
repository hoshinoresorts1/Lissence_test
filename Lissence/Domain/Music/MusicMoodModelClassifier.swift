/// CoreML 음악 무드 분류 모델을 로드하고 예측을 수행합니다.

import CoreML
import Foundation

/// MusicMoodClassifier.mlpackage 또는 컴파일된 mlmodelc를 감싼 앱 전용 classifier입니다.
final class MusicMoodModelClassifier {
    // MARK: - 속성

    /// 로드된 CoreML 모델입니다.
    private let model: MLModel

    /// 모델 입력 feature 이름입니다.
    private let inputName: String

    /// MultiArray 출력만 존재할 때 사용할 fallback 라벨 순서입니다.
    private let fallbackLabels: [String]

    /// 모델이 반환하는 predicted label 출력 이름입니다.
    private let classLabelName: String

    // MARK: - 초기화

    /// 앱 번들에서 음악 무드 모델을 찾아 로드합니다.
    init() throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        let loadedModel: MLModel
        if let compiledURL = Bundle.main.url(forResource: "MusicMoodClassifier", withExtension: "mlmodelc") {
            loadedModel = try MLModel(contentsOf: compiledURL, configuration: configuration)
        } else if let packageURL = Bundle.main.url(forResource: "MusicMoodClassifier", withExtension: "mlpackage") {
            let compiledURL = try MLModel.compileModel(at: packageURL)
            loadedModel = try MLModel(contentsOf: compiledURL, configuration: configuration)
        } else {
            throw NSError(
                domain: "MusicMoodModelClassifier",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "MusicMoodClassifier 모델을 찾지 못했습니다."]
            )
        }

        model = loadedModel
        inputName = Self.resolveInputName(from: loadedModel)
        fallbackLabels = Self.resolveFallbackLabels()
        classLabelName = loadedModel.modelDescription.predictedFeatureName ?? "classLabel"

        try Self.validateModelDescription(loadedModel, inputName: inputName)
        debugLog(Self.modelSummary(loadedModel, inputName: inputName, labels: fallbackLabels))
    }

    // MARK: - 예측

    /// 전처리된 모델 입력을 사용해 원시 무드 예측 결과를 반환합니다.
    func predict(input: MLMultiArray) throws -> MusicMoodClassifierResult {
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(multiArray: input)
        ])

        let output = try model.prediction(from: provider)

        if let label = output.featureValue(for: classLabelName)?.stringValue
            ?? output.featureValue(for: "classLabel")?.stringValue {
            let result = MusicMoodClassifierResult(
                label: label,
                probabilities: readProbabilityDictionary(output) ?? [:]
            )
            debugLog("predicted label=\(result.label), confidence=\(Self.confidence(from: result.probabilities))")
            return result
        }

        if let result = readMultiArrayOutput(output) {
            debugLog("predicted label=\(result.label), confidence=\(Self.confidence(from: result.probabilities))")
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

    /// 모델 description에서 첫 번째 MultiArray 입력 이름을 찾습니다.
    private static func resolveInputName(from model: MLModel) -> String {
        if let name = model.modelDescription.inputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key {
            return name
        }

        return "input_layer"
    }

    /// 학습 stats의 label 순서를 fallback 라벨로 사용합니다.
    private static func resolveFallbackLabels() -> [String] {
        let labels = TrainingStats.load().labelNames
        return labels.count >= 4 ? Array(labels.prefix(4)) : ["Q1", "Q2", "Q3", "Q4"]
    }

    /// 새 모델이 음악모드 extractor 출력과 호환되는지 확인합니다.
    private static func validateModelDescription(_ model: MLModel, inputName: String) throws {
        guard let input = model.modelDescription.inputDescriptionsByName[inputName],
              input.type == .multiArray,
              let shape = input.multiArrayConstraint?.shape.map({ $0.intValue }) else {
            throw NSError(
                domain: "MusicMoodModelClassifier",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "MusicMoodClassifier 입력 MultiArray description을 찾지 못했습니다."]
            )
        }

        let expectedShape = [1, 128, 128, 3]
        guard shape == expectedShape else {
            throw NSError(
                domain: "MusicMoodModelClassifier",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey: "MusicMoodClassifier 입력 shape mismatch: expected \(expectedShape), actual \(shape)"
                ]
            )
        }
    }

    /// 모델 구조 요약 로그를 생성합니다.
    private static func modelSummary(_ model: MLModel, inputName: String, labels: [String]) -> String {
        let description = model.modelDescription
        let input = description.inputDescriptionsByName[inputName]
        let inputShape = input?.multiArrayConstraint?.shape.map { $0.stringValue }.joined(separator: "x") ?? "unknown"
        let outputs = description.outputDescriptionsByName.keys.sorted().joined(separator: ", ")
        let metadata = description.metadata
        let shortDescription = metadata[.description] as? String ?? ""
        let author = metadata[.author] as? String ?? ""
        let version = metadata[.versionString] as? String ?? ""

        return "model input=\(inputName), shape=\(inputShape), outputs=\(outputs), predictedLabel=\(description.predictedFeatureName ?? "nil"), predictedProbs=\(description.predictedProbabilitiesName ?? "nil"), labels=\(labels), description=\(shortDescription), author=\(author), version=\(version)"
    }

    /// 확률 딕셔너리에서 가장 큰 confidence를 계산합니다.
    private static func confidence(from probabilities: [String: Double]) -> Double {
        probabilities.values.max() ?? 0.0
    }

    /// Debug 빌드에서만 음악모드 CoreML 로그를 출력합니다.
    private func debugLog(_ message: String) {
        #if DEBUG
        print("[MusicMoodModelClassifier] \(message)")
        #endif
    }
}
