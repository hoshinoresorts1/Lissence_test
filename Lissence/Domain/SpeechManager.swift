/// 아이폰용 음성 인식 엔진
/// 감지모드의 음성인식기능
/// - 애플의 Speech와 SoundAnalysis를 이용하여 음성인식을 수행합니다.

import Foundation
import Speech
import AVFoundation
import Combine

// NSObject를 상속받아야 음성 인식 델리게이트를 사용할 수 있습니다.
class SpeechManager: NSObject, ObservableObject {
    // MARK: - 속성

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")) // 한국어 설정
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine() // 마이크 입력용 엔진
    private var isStartingRecognition = false
    private var readyLogAfterStart: String?

    // MARK: - Published Properties

    /// 화면(SwiftUI)에서 관찰하는 실시간 자막입니다.
    @Published var transcript: String = ""
    /// 현재 음성 인식 녹음 상태입니다.
    @Published var isRecording: Bool = false

    // MARK: - 공개 메서드

    /// 다음 인식 세션을 새 문장으로 시작하기 위해 누적 transcript를 비웁니다.
    func resetTranscript() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.resetTranscript()
            }
            return
        }

        transcript = ""
    }

    /// Speech 권한과 마이크 권한을 확인한 뒤 음성 인식을 시작합니다.
    func startRecording(reason: String = "unspecified", readyLogAfterStart: String? = nil) {
        print("[SpeechManager] startRecording requested reason=\(reason)")

        guard !isStartingRecognition, !isRecording, !audioEngine.isRunning, recognitionTask == nil else {
            print("[SpeechManager] startRecording skipped reason=already-running-or-starting")
            return
        }

        self.readyLogAfterStart = readyLogAfterStart
        isStartingRecognition = true

        requestSpeechAuthorization { [weak self] speechGranted in
            guard let self else { return }

            guard speechGranted else {
                DispatchQueue.main.async {
                    print("[SpeechManager] speech authorization denied or restricted")
                    self.transcript = "음성 인식 권한이 필요합니다."
                    self.readyLogAfterStart = nil
                    self.isStartingRecognition = false
                    self.isRecording = false
                }
                return
            }

            self.requestMicrophonePermission { [weak self] microphoneGranted in
                guard let self else { return }

                guard microphoneGranted else {
                    DispatchQueue.main.async {
                        print("[SpeechManager] microphone permission denied")
                        self.transcript = "마이크 권한이 필요합니다."
                        self.readyLogAfterStart = nil
                        self.isStartingRecognition = false
                        self.isRecording = false
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.beginRecognition()
                }
            }
        }
    }

    /// 음성 인식과 오디오 엔진을 정지합니다.
    func stopRecording() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.stopRecording()
            }
            return
        }

        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioEngine.reset()
        recognitionTask = nil
        recognitionRequest = nil
        isStartingRecognition = false
        isRecording = false
        readyLogAfterStart = nil
    }

    // MARK: - 권한 처리

    /// Speech 프레임워크 권한 상태를 확인하고 필요 시 요청합니다.
    private func requestSpeechAuthorization(completion: @escaping (Bool) -> Void) {
        let status = SFSpeechRecognizer.authorizationStatus()

        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                completion(status == .authorized)
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    /// 마이크 권한 상태를 확인하고 필요 시 요청합니다.
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            completion(granted)
        }
    }

    // MARK: - 내부 로직

    /// 권한이 확보된 상태에서 실제 Speech 인식 파이프라인을 시작합니다.
    private func beginRecognition() {
        guard !isRecording, !audioEngine.isRunning, recognitionTask == nil else {
            isStartingRecognition = false
            return
        }

        // 이전 tap이 남아 있으면 CreateRecordingTap 충돌이 발생할 수 있으므로 시작 전에 방어적으로 정리합니다.
        audioEngine.inputNode.removeTap(onBus: 0)

        // 오디오 세션 설정 (말소리 듣기 모드)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            print("[SpeechManager] configure audio session for recording")
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            transcript = "오디오 세션 설정에 실패했습니다."
            readyLogAfterStart = nil
            isStartingRecognition = false
            print("[SpeechManager] audio session setup failed: \(error.localizedDescription)")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            isStartingRecognition = false
            return
        }
        recognitionRequest.shouldReportPartialResults = true // 말하는 도중에도 결과 보여주기

        // 음성 인식 시작
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result = result {
                // 실시간으로 변환된 텍스트를 transcript에 저장
                DispatchQueue.main.async {
                    self.transcript = result.bestTranscription.formattedString
                }
            }

            if let error {
                print("[SpeechManager] recognitionTask error: \(error.localizedDescription)")
            }

            if error != nil || result?.isFinal == true {
                self.stopRecording()
            }
        }

        guard recognitionTask != nil else {
            transcript = "음성 인식을 시작할 수 없습니다."
            stopRecording()
            return
        }

        // 마이크 입력 연결
        let recordingFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, _) in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isStartingRecognition = false
            isRecording = true
            print("[SpeechManager] audio engine started")
            if let readyLogAfterStart {
                print(readyLogAfterStart)
                self.readyLogAfterStart = nil
            }
        } catch {
            transcript = "오디오 엔진 시작에 실패했습니다."
            readyLogAfterStart = nil
            isStartingRecognition = false
            print("[SpeechManager] audioEngine.start failed: \(error.localizedDescription)")
        }
    }
}
