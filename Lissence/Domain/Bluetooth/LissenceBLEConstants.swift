/// ESP32 BLE 테스트에 사용하는 고정 식별자와 테스트 payload를 정의합니다.

import CoreBluetooth
import Foundation

/// Lissence ESP32 BLE Peripheral과 통신하기 위한 상수 모음입니다.
enum LissenceBLEConstants {
    // MARK: - Peripheral 식별자

    /// ESP32 Peripheral 광고 이름입니다.
    static let deviceName = "Lissence-ESP32"

    /// ESP32 Custom GATT Service UUID입니다.
    static let serviceUUID = CBUUID(string: "7d2f3a10-3b7a-4f9f-9b37-6b6a0f4f7c10")

    /// ESP32와 문자열을 주고받는 Characteristic UUID입니다.
    static let characteristicUUID = CBUUID(string: "7d2f3a11-3b7a-4f9f-9b37-6b6a0f4f7c10")

    // MARK: - 테스트 메시지

    /// iPhone에서 ESP32로 전송할 햅틱 테스트 명령입니다.
    static let warningHapticPayload = #"{"type":"haptic","pattern":"warning"}"#

    // MARK: - 스캔 설정

    /// Service UUID 스캔에서 장치를 찾지 못했을 때 이름 기반 fallback으로 전환하기까지 기다리는 시간입니다.
    static let serviceScanTimeout: TimeInterval = 5
}
