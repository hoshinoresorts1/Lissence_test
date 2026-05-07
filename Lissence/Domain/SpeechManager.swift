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

    // MARK: - Published Properties

    /// 화면(SwiftUI)에서 관찰하는 실시간 자막입니다.
    @Published var transcript: String = ""
    /// 현재 음성 인식 녹음 상태입니다.
    @Published var isRecording: Bool = false

    // MARK: - 공개 메서드

    /// Speech 권한과 마이크 권한을 확인한 뒤 음성 인식을 시작합니다.
    func startRecording() {
        print("[SpeechManager] startRecording called")
        print("[SpeechManager] current speech authorizationStatus: \(SFSpeechRecognizer.authorizationStatus().rawValue)")

        requestSpeechAuthorization { [weak self] speechGranted in
            guard let self else { return }

            guard speechGranted else {
                DispatchQueue.main.async {
                    print("[SpeechManager] speech authorization denied or restricted")
                    self.transcript = "음성 인식 권한이 필요합니다."
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
                        self.isRecording = false
                    }
                    return
                }

                DispatchQueue.main.async {
                    print("[SpeechManager] permissions granted, beginRecognition scheduled")
                    self.beginRecognition()
                }
            }
        }
    }

    /// 음성 인식과 오디오 엔진을 정지합니다.
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        isRecording = false
    }

    // MARK: - 권한 처리

    /// Speech 프레임워크 권한 상태를 확인하고 필요 시 요청합니다.
    private func requestSpeechAuthorization(completion: @escaping (Bool) -> Void) {
        let status = SFSpeechRecognizer.authorizationStatus()
        print("[SpeechManager] requestSpeechAuthorization status before request: \(status.rawValue)")

        switch status {
        case .authorized:
            print("[SpeechManager] speech authorization already authorized")
            completion(true)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                print("[SpeechManager] requestAuthorization result: \(status.rawValue)")
                completion(status == .authorized)
            }
        case .denied, .restricted:
            print("[SpeechManager] speech authorization unavailable: \(status.rawValue)")
            completion(false)
        @unknown default:
            print("[SpeechManager] speech authorization unknown default")
            completion(false)
        }
    }

    /// 마이크 권한 상태를 확인하고 필요 시 요청합니다.
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            print("[SpeechManager] microphone permission granted: \(granted)")
            completion(granted)
        }
    }

    // MARK: - 내부 로직

    /// 권한이 확보된 상태에서 실제 Speech 인식 파이프라인을 시작합니다.
    private func beginRecognition() {
        print("[SpeechManager] beginRecognition called")
        print("[SpeechManager] speech authorization before recognitionTask: \(SFSpeechRecognizer.authorizationStatus().rawValue)")
        print("[SpeechManager] speechRecognizer available: \(speechRecognizer != nil)")

        // 기존 작업이 있다면 취소
        if recognitionTask != nil {
            print("[SpeechManager] cancel existing recognitionTask before restart")
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        // 오디오 세션 설정 (말소리 듣기 모드)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            print("[SpeechManager] AVAudioSession.setCategory success")
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("[SpeechManager] AVAudioSession.setActive(true) success")
        } catch {
            transcript = "오디오 세션 설정에 실패했습니다."
            print("[SpeechManager] audio session setup failed: \(error.localizedDescription)")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        print("[SpeechManager] recognitionRequest created: \(recognitionRequest != nil)")

        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true // 말하는 도중에도 결과 보여주기
        print("[SpeechManager] recognitionRequest.shouldReportPartialResults = true")

        // 음성 인식 시작
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                // 실시간으로 변환된 텍스트를 transcript에 저장
                DispatchQueue.main.async {
                    print("[SpeechManager] recognitionTask transcript: \(result.bestTranscription.formattedString)")
                    self.transcript = result.bestTranscription.formattedString

                    // 만약 특정 단어가 포함되어 있다면? (감지 모드 테스트)
                    if self.transcript.contains("저기요") || self.transcript.contains("안녕하세요") {
                        let speechLevel = DangerSound.speech // 공통 모델 활용
                        let message = MessageData(
                            title: "누군가 말을 걸었습니다!",
                            iconName: speechLevel.icon,
                            isDanger: speechLevel.isDanger
                        )
                        ConnectivityManager.shared.send(message: message)
                    }
                }
            }

            if let error {
                print("[SpeechManager] recognitionTask error: \(error.localizedDescription)")
            }

            if let result {
                print("[SpeechManager] recognitionTask isFinal: \(result.isFinal)")
            }

            if error != nil || result?.isFinal == true {
                print("[SpeechManager] recognitionTask stopping recording")
                self.stopRecording()
            }
        }
        print("[SpeechManager] recognitionTask created: \(recognitionTask != nil)")

        // 마이크 입력 연결
        let recordingFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        print("[SpeechManager] input format sampleRate: \(recordingFormat.sampleRate), channels: \(recordingFormat.channelCount)")
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, _) in
            self.recognitionRequest?.append(buffer)
        }
        print("[SpeechManager] inputNode tap installed")

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            print("[SpeechManager] audioEngine.start success")
        } catch {
            transcript = "오디오 엔진 시작에 실패했습니다."
            print("[SpeechManager] audioEngine.start failed: \(error.localizedDescription)")
        }
    }
}
