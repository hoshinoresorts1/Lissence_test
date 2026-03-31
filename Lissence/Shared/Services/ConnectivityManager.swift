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
        guard WCSession.default.activationState == .activated else {
            print("⚠️ 세션이 활성화되지 않아 전송할 수 없습니다.")
            return
        }

        // 1. MessageData 구조체를 JSON 데이터로 변환
        guard let data = try? JSONEncoder().encode(message) else { return }
        
        // 2. 딕셔너리에 담아서 전송
        let messageDict = ["payload": data]
        
        WCSession.default.sendMessage(messageDict, replyHandler: nil) { error in
            print("❌ 전송 실패: \(error.localizedDescription)")
        }

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
                
                print("📩 메시지 수신 성공: \(decoded.title)")
                
                // 5초 후 화면 초기화 로직
                self.resetTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.receivedMessage = nil
                        print("♻️ 아이폰 메시지 표시 기한 만료 - 대기 상태 전환")
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
