/// BLE 테스트 화면에서 송수신 문자열 메시지를 표현합니다.

import Foundation

/// BLE Characteristic을 통해 주고받은 UTF-8 문자열 메시지입니다.
struct LissenceBLEMessage: Identifiable, Equatable {
    /// SwiftUI 목록과 상태 갱신에 사용할 고유 식별자입니다.
    let id = UUID()

    /// BLE로 송수신한 UTF-8 문자열입니다.
    let text: String

    /// 메시지가 생성된 시각입니다.
    let date: Date

    // MARK: - 초기화

    /// 표시할 문자열과 생성 시각으로 메시지를 생성합니다.
    init(text: String, date: Date = Date()) {
        self.text = text
        self.date = date
    }
}
