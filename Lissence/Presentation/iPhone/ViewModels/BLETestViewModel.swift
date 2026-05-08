/// iPhone BLE 테스트 화면의 상태와 버튼 액션을 관리합니다.

import Combine
import Foundation

/// ESP32 BLE 통신 검증 화면에서 사용할 MVVM ViewModel입니다.
final class BLETestViewModel: ObservableObject {
    // MARK: - 속성

    /// Bluetooth 권한과 전원 상태를 나타내는 문구입니다.
    @Published var bluetoothStateText = "Bluetooth 상태 확인 중"

    /// BLE 작업 진행 상태를 나타내는 문구입니다.
    @Published var statusText = "BLE 테스트 대기 중"

    /// 현재 ESP32와 연결되어 있는지 여부입니다.
    @Published var isConnected = false

    /// 최근 발견한 Peripheral 이름입니다.
    @Published var discoveredDeviceName = "-"

    /// 최근 ESP32에서 받은 문자열 메시지입니다.
    @Published var lastReceivedMessage = "-"

    /// 최근 ESP32로 보낸 문자열 메시지입니다.
    @Published var lastSentMessage = "-"

    /// 테스트 write 버튼 활성화 여부입니다.
    var canSendTestCommand: Bool {
        isConnected
    }

    /// BLE 통신을 담당하는 서비스 객체입니다.
    private let bleManager: LissenceBLEManager

    // MARK: - 초기화

    /// BLE manager를 주입받아 ViewModel을 생성합니다.
    init(bleManager: LissenceBLEManager = LissenceBLEManager()) {
        self.bleManager = bleManager
        self.bleManager.delegate = self
    }

    // MARK: - 시작 제어

    /// ESP32 BLE Peripheral 스캔을 시작합니다.
    func startScan() {
        statusText = "BLE 스캔 시작"
        bleManager.startScan()
    }

    /// BLE 스캔 또는 연결을 중지합니다.
    func stop() {
        bleManager.stop()
    }

    /// ESP32로 햅틱 테스트 명령을 전송합니다.
    func sendWarningHapticCommand() {
        bleManager.writeWarningHapticCommand()
    }
}

// MARK: - LissenceBLEManagerDelegate

extension BLETestViewModel: LissenceBLEManagerDelegate {
    /// Bluetooth 권한과 전원 상태를 ViewModel 상태로 반영합니다.
    func bleManager(_ manager: LissenceBLEManager, didUpdateBluetoothState stateText: String) {
        bluetoothStateText = stateText
    }

    /// BLE 작업 진행 상태를 ViewModel 상태로 반영합니다.
    func bleManager(_ manager: LissenceBLEManager, didUpdateStatus statusText: String) {
        self.statusText = statusText
    }

    /// ESP32 연결 상태를 ViewModel 상태로 반영합니다.
    func bleManager(_ manager: LissenceBLEManager, didUpdateConnection isConnected: Bool) {
        self.isConnected = isConnected
    }

    /// 발견한 Peripheral 이름을 ViewModel 상태로 반영합니다.
    func bleManager(_ manager: LissenceBLEManager, didDiscoverDeviceName deviceName: String) {
        discoveredDeviceName = deviceName
    }

    /// ESP32에서 받은 notify/read 메시지를 ViewModel 상태로 반영합니다.
    func bleManager(_ manager: LissenceBLEManager, didReceive message: LissenceBLEMessage) {
        lastReceivedMessage = message.text
    }

    /// ESP32로 보낸 메시지를 ViewModel 상태로 반영합니다.
    func bleManager(_ manager: LissenceBLEManager, didSend message: LissenceBLEMessage) {
        lastSentMessage = message.text
    }
}
