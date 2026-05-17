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

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        delegate?.ttsManagerWillStartSpeaking(self)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }

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
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

extension TTSManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        delegate?.ttsManagerDidFinishSpeaking(self)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        delegate?.ttsManagerDidFinishSpeaking(self)
    }
}
