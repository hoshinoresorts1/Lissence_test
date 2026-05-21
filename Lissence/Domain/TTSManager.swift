/// Text-to-speech output for detection mode communication.

import AVFoundation
import Foundation

protocol TTSManagerDelegate: AnyObject {
    func ttsManagerWillStartSpeaking(_ manager: TTSManager)
    func ttsManagerDidFinishSpeaking(_ manager: TTSManager)
}

final class TTSManager: NSObject {
    static let shared = TTSManager()

    weak var delegate: TTSManagerDelegate?

    private let synthesizer = AVSpeechSynthesizer()
    private var pendingSpeakWorkItem: DispatchWorkItem?
    private var isPreparingSpeech = false
    private var currentUtteranceID: UUID?
    private var currentTextPrefix = ""
    private var currentSource = "unknown"
    private var lastFinishedAt: Date = .distantPast
    private let postFinishSpeakCooldown: TimeInterval = 1.5

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    @discardableResult
    func speak(_ text: String, source: String = "unknown") -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return false
        }

        let now = Date()
        guard now.timeIntervalSince(lastFinishedAt) >= postFinishSpeakCooldown else {
            print("[TTS] ignored source=\(source) reason=cooldown text=\(textPrefix(trimmedText))")
            return false
        }

        guard !isPreparingSpeech, !synthesizer.isSpeaking else {
            print("[TTS] ignored source=\(source) reason=busy text=\(textPrefix(trimmedText))")
            return false
        }

        let utteranceID = UUID()
        currentUtteranceID = utteranceID
        currentTextPrefix = textPrefix(trimmedText)
        currentSource = source
        isPreparingSpeech = true
        delegate?.ttsManagerWillStartSpeaking(self)
        print("[TTS] didStart id=\(utteranceID.uuidString) source=\(source) text=\(currentTextPrefix)")

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSpeakWorkItem = nil

            do {
                let session = AVAudioSession.sharedInstance()
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                try session.setCategory(
                    .playback,
                    mode: .spokenAudio,
                    options: [.duckOthers, .mixWithOthers]
                )
                try session.setActive(true)
            } catch {
                print("[TTSManager] audio session setup failed: \(error.localizedDescription)")
            }

            let utterance = AVSpeechUtterance(string: trimmedText)
            utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.volume = 1.0
            self.synthesizer.speak(utterance)
        }

        pendingSpeakWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
        return true
    }

    func stop() {
        pendingSpeakWorkItem?.cancel()
        pendingSpeakWorkItem = nil
        isPreparingSpeech = false
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func finishCurrentSpeech(reason: String) {
        let idText = currentUtteranceID?.uuidString ?? "-"
        print("[TTS] didFinish id=\(idText) source=\(currentSource) reason=\(reason) text=\(currentTextPrefix)")

        isPreparingSpeech = false
        currentUtteranceID = nil
        currentTextPrefix = ""
        currentSource = "unknown"
        lastFinishedAt = Date()
        delegate?.ttsManagerDidFinishSpeaking(self)
    }

    private func textPrefix(_ text: String) -> String {
        String(text.prefix(20))
    }
}

extension TTSManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isPreparingSpeech = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishCurrentSpeech(reason: "finish")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishCurrentSpeech(reason: "cancel")
    }
}
