/// 아이폰과 워치 사이를 연결하는 무전기

import Foundation
import WatchConnectivity
import Combine

/// 아이폰과 애플워치 간의 데이터를 송수신하는 통신 매니저
final class ConnectivityManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    static let shared = ConnectivityManager() // 어디서든 접근 가능한 싱글톤
    
    // MARK: - Published Properties
    /// 워치로부터 전달받은 최신 메시지 (뷰에서 관찰 대상)
    @Published var receivedMessage: MessageData?
    
    /// 위험 감지상태의 자동 초기화를 위한 타이머 변수 추가
    private var resetTimer: Timer?

    /// 같은 WatchConnectivity 전송 불가 사유가 반복 출력되지 않도록 저장하는 값입니다.
    private var lastSendUnavailableReason: String?
    
    // MARK: - Initialization
    override private init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
    
    // MARK: - Sending Logic (구조체 직접 전달)
    /// MessageData 규격을 사용하여 상대 기기로 데이터를 전송합니다
    func send(message: MessageData) {
        guard WCSession.isSupported() else {
            logSendUnavailableOnce("WatchConnectivity를 지원하지 않아 전송하지 않습니다.")
            return
        }

        let session = WCSession.default

        guard canSendMessage(using: session) else {
            return
        }

        // 1. MessageData 구조체를 JSON 데이터로 변환
        guard let data = try? JSONEncoder().encode(message) else { return }
        
        // 2. 딕셔너리에 담아서 전송
        let messageDict = ["payload": data]
        
        session.sendMessage(messageDict, replyHandler: nil) { [weak self] error in
            self?.logSendUnavailableOnce("WatchConnectivity 전송 실패: \(error.localizedDescription)")
        }

    }

    /// 현재 WCSession 상태가 즉시 메시지 전송 가능한 상태인지 확인합니다.
    private func canSendMessage(using session: WCSession) -> Bool {
        guard session.activationState == .activated else {
            logSendUnavailableOnce("WCSession이 활성화되지 않아 전송하지 않습니다.")
            return false
        }

        #if os(iOS)
        guard session.isPaired else {
            logSendUnavailableOnce("Apple Watch가 페어링되어 있지 않아 전송하지 않습니다.")
            return false
        }

        guard session.isWatchAppInstalled else {
            logSendUnavailableOnce("Watch 앱이 설치되어 있지 않아 전송하지 않습니다.")
            return false
        }
        #endif

        guard session.isReachable else {
            logSendUnavailableOnce("상대 기기가 reachable 상태가 아니어서 전송하지 않습니다.")
            return false
        }

        lastSendUnavailableReason = nil
        return true
    }

    /// 같은 전송 불가 사유는 최초 1회만 출력합니다.
    private func logSendUnavailableOnce(_ reason: String) {
        guard lastSendUnavailableReason != reason else {
            return
        }

        lastSendUnavailableReason = reason
        print("⚠️ \(reason)")
    }
}

// MARK: - WCSessionDelegate
extension ConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
            if let error = error {
                print("세션 활성화 오류: \(error.localizedDescription)")
            }
        }
    
    /// 메시지 수신 시 실행되는 콜백 함수
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            // 1. "payload" 키로 담긴 데이터를 꺼내서 MessageData로 복원(디코딩)
            if let data = message["payload"] as? Data,
               let decoded = try? JSONDecoder().decode(MessageData.self, from: data) {
                
                self.resetTimer?.invalidate()
                self.receivedMessage = decoded
                
                // 5초 후 화면 초기화 로직
                self.resetTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.receivedMessage = nil
                    }
                }
            }
        }
    }
    
    // iOS 필수 구현 메서드
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate() // 세션이 끊기면 다시 살려내기
    }
    #endif
}
