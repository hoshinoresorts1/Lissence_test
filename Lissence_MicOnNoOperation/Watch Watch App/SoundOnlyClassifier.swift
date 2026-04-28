/// 마이크 상시 동작 / 연산 없음
/// 테스트를 위한 파일입니다.

import Foundation
import AVFoundation
import WatchKit
import Combine

class SoundOnlyClassifier: NSObject, ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var extendedSession: WKExtendedRuntimeSession?
    @Published var isRunning = false

    func start() {
        guard !audioEngine.isRunning else { return }
        
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard granted else { return }
            
            DispatchQueue.main.async {
                // [추가] 오디오 세션 활성화
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playAndRecord, mode: .default)
                try? session.setActive(true)
                
                self?.extendedSession = WKExtendedRuntimeSession()
                self?.extendedSession?.start()
                
                self?.startEngine()
            }
        }
    }

    private func startEngine() {
        // [중요] inputNode 접근 시 안전하게 예외 처리
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, time in
            // 연산 없음
        }
        
        do {
            audioEngine.prepare() // [추가] 준비 단계 명시
            try audioEngine.start()
            DispatchQueue.main.async { self.isRunning = true }
        } catch {
            print("엔진 시작 실패: \(error)")
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        extendedSession?.invalidate()
        DispatchQueue.main.async { self.isRunning = false }
    }
}
