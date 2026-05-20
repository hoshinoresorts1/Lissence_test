/// CoreBluetooth 기반으로 HearAlert ESP32 Peripheral 스캔, 연결, notify 구독, 햅틱 명령 write를 수행합니다.
/// 가이드 §0, §9 규격에 따라 connection 시 clock_ping을 보내고, 위험 소리 분류 결과는
/// {"type":"haptic","pattern":<id>,"ts":<ms>,"win":<ms>} JSON 으로 ESP32 에 전달합니다.

import CoreBluetooth
import Foundation

/// BLE manager가 ViewModel에 전달하는 상태 변경 이벤트입니다.
protocol LissenceBLEManagerDelegate: AnyObject {
    /// Bluetooth 전원 또는 권한 상태 문구가 변경되었을 때 호출됩니다.
    func bleManager(_ manager: LissenceBLEManager, didUpdateBluetoothState stateText: String)

    /// BLE 작업 진행 상태 문구가 변경되었을 때 호출됩니다.
    func bleManager(_ manager: LissenceBLEManager, didUpdateStatus statusText: String)

    /// ESP32 연결 상태가 변경되었을 때 호출됩니다.
    func bleManager(_ manager: LissenceBLEManager, didUpdateConnection isConnected: Bool)

    /// 스캔 중 발견한 Peripheral 이름이 변경되었을 때 호출됩니다.
    func bleManager(_ manager: LissenceBLEManager, didDiscoverDeviceName deviceName: String)

    /// ESP32에서 notify 또는 read로 문자열 메시지를 받았을 때 호출됩니다.
    func bleManager(_ manager: LissenceBLEManager, didReceive message: LissenceBLEMessage)

    /// ESP32로 문자열 메시지 전송이 완료되었거나 전송 요청이 큐에 들어갔을 때 호출됩니다.
    func bleManager(_ manager: LissenceBLEManager, didSend message: LissenceBLEMessage)
}

extension LissenceBLEManagerDelegate {
    func bleManager(_ manager: LissenceBLEManager, didUpdateBluetoothState stateText: String) {}
    func bleManager(_ manager: LissenceBLEManager, didUpdateStatus statusText: String) {}
    func bleManager(_ manager: LissenceBLEManager, didUpdateConnection isConnected: Bool) {}
    func bleManager(_ manager: LissenceBLEManager, didDiscoverDeviceName deviceName: String) {}
    func bleManager(_ manager: LissenceBLEManager, didReceive message: LissenceBLEMessage) {}
    func bleManager(_ manager: LissenceBLEManager, didSend message: LissenceBLEMessage) {}
}

/// HearAlert ESP32 BLE Peripheral과 통신하는 CoreBluetooth 서비스 객체입니다.
final class LissenceBLEManager: NSObject {
    // MARK: - 속성

    /// 앱 전체에서 공유하는 ESP32 BLE manager 싱글톤입니다.
    static let shared = LissenceBLEManager()

    /// BLE 상태 변경을 받을 delegate입니다.
    weak var delegate: LissenceBLEManagerDelegate?

    /// CoreBluetooth 작업을 처리하는 전용 queue입니다.
    private let bluetoothQueue = DispatchQueue(label: "com.lissence.ble.manager")

    /// iPhone BLE Central 역할을 수행하는 객체입니다.
    private lazy var centralManager = CBCentralManager(delegate: self, queue: bluetoothQueue)

    /// 현재 연결 또는 연결 시도 중인 ESP32 Peripheral입니다.
    private var connectedPeripheral: CBPeripheral?

    /// 문자열 송수신에 사용하는 ESP32 Characteristic입니다.
    private var messageCharacteristic: CBCharacteristic?

    /// Service UUID 스캔 후 이름 기반 fallback 스캔으로 전환했는지 여부입니다.
    private var isNameFallbackScan = false

    /// 응답이 필요한 write 요청의 최근 payload입니다.
    private var pendingWritePayload: String?

    /// 동일 패턴 연속 write를 방지하는 마지막 송신 시각입니다.
    private var lastHapticWriteAt: Date = .distantPast

    /// 클록 동기 ping을 보낸 시각입니다. pong 미수신 시 fallback latency를 사용합니다.
    private var lastClockPingAt: Date?

    /// 클록 동기 성공 시 iPhone Date와 ESP32 시각의 추정 차이(초)입니다. nil이면 fallback latency를 사용합니다.
    private var clockOffsetSeconds: TimeInterval?

    /// state가 아직 .poweredOn이 아닐 때 들어온 스캔 요청을 보관해 두기 위한 flag입니다.
    private var pendingScanRequest = false

    // MARK: - 시작 제어

    /// BLE 스캔을 시작합니다. 먼저 Service UUID로 스캔하고, 일정 시간 후 이름 기반 스캔으로 fallback합니다.
    /// 호출 시점에 centralManager가 아직 .poweredOn이 아니면 요청을 보관했다가 상태 전환 후 자동 재실행합니다.
    func startScan() {
        bluetoothQueue.async { [weak self] in
            guard let self else { return }

            // centralManager는 lazy var이므로 첫 접근 시점에 초기화됩니다.
            // 초기화 직후 state는 .unknown이며, 잠시 후 didUpdateState 콜백에서 .poweredOn으로 전환됩니다.
            // 그 사이 호출된 startScan은 여기서 pending으로 보관해 두고, 상태 전환 시 자동 재시도합니다.
            guard self.centralManager.state == .poweredOn else {
                self.pendingScanRequest = self.centralManager.state == .unknown ||
                    self.centralManager.state == .resetting
                let stateText = self.stateText(for: self.centralManager.state)
                self.notifyStatus("Bluetooth 준비 대기 중 (\(stateText))")
                self.notifyBluetoothState(stateText)
                print("📡 [LissenceBLE] startScan deferred: state=\(stateText), pendingScanRequest=\(self.pendingScanRequest)")
                return
            }

            self.performScan()
        }
    }

    /// 실제 service UUID 스캔을 시작합니다. centralManager가 .poweredOn 상태일 때만 호출되어야 합니다.
    private func performScan() {
        pendingScanRequest = false
        resetConnectionStateForNewScan()
        isNameFallbackScan = false
        notifyStatus("Service UUID로 HearAlert 스캔 중")
        print("📡 [LissenceBLE] startScan: service UUID 기반 스캔 시작")
        centralManager.scanForPeripherals(
            withServices: [LissenceBLEConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        bluetoothQueue.asyncAfter(deadline: .now() + LissenceBLEConstants.serviceScanTimeout) { [weak self] in
            self?.startNameFallbackScanIfNeeded()
        }
    }

    /// 진행 중인 스캔 또는 연결을 중지합니다.
    func stop() {
        bluetoothQueue.async { [weak self] in
            guard let self else { return }

            self.centralManager.stopScan()
            if let connectedPeripheral = self.connectedPeripheral {
                self.centralManager.cancelPeripheralConnection(connectedPeripheral)
            }
            self.messageCharacteristic = nil
            self.connectedPeripheral = nil
            self.notifyConnection(false)
            self.notifyStatus("BLE 연결 해제")
        }
    }

    /// ESP32로 지정된 햅틱 pattern 실행 command를 전송합니다.
    /// - Parameters:
    ///   - pattern: ESP32 펌웨어에서 매핑하는 햅틱 패턴 식별자(siren/fireAlarm/carHorn 등).
    ///   - classifiedAt: 위험 소리가 실제 마이크에 도달한 시각. ESP32 방향 윈도 매칭에 사용됩니다.
    /// - Returns: 실제로 write 요청을 보냈으면 true, 쿨다운/미연결로 건너뛰면 false.
    @discardableResult
    func writeHapticPattern(_ pattern: String, classifiedAt: Date = Date()) -> Bool {
        bluetoothQueue.async { [weak self] in
            guard let self else { return }

            guard self.centralManager.state == .poweredOn else {
                print("📡 [BLEHaptic] skip: Bluetooth not powered on")
                return
            }

            guard let connectedPeripheral = self.connectedPeripheral,
                  connectedPeripheral.state == .connected else {
                print("📡 [BLEHaptic] skip: peripheral not connected")
                return
            }

            guard let messageCharacteristic = self.messageCharacteristic else {
                print("📡 [BLEHaptic] skip: characteristic unavailable")
                return
            }

            let now = Date()
            guard now.timeIntervalSince(self.lastHapticWriteAt) >= LissenceBLEConstants.bleWriteCooldownSeconds else {
                print("📡 [BLEHaptic] skip: cooldown pattern=\(pattern)")
                return
            }

            // ESP32 ring buffer는 ESP32 millis() 좌표계의 timestamp를 기대합니다.
            // clock_pong offset이 있으면 보정값을 쓰고, 없으면 BLE latency fallback을 적용합니다.
            let ts = self.esp32TimestampMillis(for: classifiedAt)
            let win = Int(LissenceBLEConstants.analysisWindowSeconds * 1000)
            let payload = #"{"type":"haptic","pattern":"\#(pattern)","ts":\#(ts),"win":\#(win)}"#

            self.lastHapticWriteAt = now
            self.write(payload, peripheral: connectedPeripheral, characteristic: messageCharacteristic)
            print("📡 [BLEHaptic] write pattern=\(pattern)")
        }

        return true
    }

    /// ESP32로 UTF-8 문자열을 전송합니다.
    func write(_ text: String) {
        bluetoothQueue.async { [weak self] in
            guard let self else { return }

            guard self.centralManager.state == .poweredOn else {
                self.notifyStatus("BLE write skipped: Bluetooth off")
                print("📡 [BLEHaptic] skip: Bluetooth not powered on")
                return
            }

            guard let connectedPeripheral = self.connectedPeripheral,
                  connectedPeripheral.state == .connected else {
                self.notifyStatus("BLE write skipped: peripheral not connected")
                print("📡 [BLEHaptic] skip: peripheral not connected")
                return
            }

            guard let messageCharacteristic = self.messageCharacteristic else {
                self.notifyStatus("BLE write skipped: characteristic unavailable")
                print("📡 [BLEHaptic] skip: characteristic unavailable")
                return
            }

            self.write(text, peripheral: connectedPeripheral, characteristic: messageCharacteristic)
        }
    }

    private func write(_ text: String, peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard let data = text.data(using: .utf8) else {
            notifyStatus("UTF-8 변환 실패")
            return
        }

        let writeType = writeType(for: characteristic)
        if writeType == .withResponse {
            pendingWritePayload = text
        }

        peripheral.writeValue(data, for: characteristic, type: writeType)
        let typeText = writeType == .withoutResponse ? "WRITE_NR" : "WRITE_R"
        print("📤 [LissenceBLE] write → ESP32 (\(typeText)): \(text)")

        if writeType == .withoutResponse {
            notifySentMessage(text)
            notifyStatus("BLE 메시지 전송 요청 완료")
        } else {
            notifyStatus("BLE 메시지 전송 중")
        }
    }

    // MARK: - 클록 동기

    /// 연결 직후 ESP32에 clock_ping을 보내 윈도 매칭 기준을 맞춥니다.
    private func sendClockPing() {
        let now = Date()
        lastClockPingAt = now
        let ts = esp32TimestampMillis(for: now)
        write(#"{"type":"clock_ping","ts":\#(ts)}"#)

        bluetoothQueue.asyncAfter(deadline: .now() + LissenceBLEConstants.clockSyncTimeoutSeconds) { [weak self] in
            guard let self else { return }

            if self.clockOffsetSeconds == nil {
                print("⏰ [LissenceBLE] clock_ping timeout → fallback latency 모드 사용")
                self.notifyStatus("클록 동기 timeout, fallback latency 사용")
            }
        }
    }

    /// 수신 문자열이 clock_pong이면 offset을 계산해 저장합니다.
    private func handleClockPongIfNeeded(_ text: String) {
        guard let data = text.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["type"] as? String == "clock_pong",
              let espTsNumber = payload["esp_ts"] as? NSNumber else {
            return
        }

        let espTs = espTsNumber.doubleValue
        let nowTs = Date().timeIntervalSince1970 * 1000
        let offsetSeconds = (espTs - nowTs) / 1000
        clockOffsetSeconds = offsetSeconds
        print("⏰ [LissenceBLE] clock_pong: esp_ts=\(espTs), now=\(nowTs), offset=\(String(format: "%.3f", offsetSeconds))s")
    }

    /// iPhone Date를 ESP32 윈도 매칭용 timestamp(ms) 로 변환합니다. clockOffset이 있으면 적용합니다.
    private func esp32TimestampMillis(for date: Date) -> Int64 {
        let base = date.timeIntervalSince1970 * 1000
        if let offset = clockOffsetSeconds {
            return Int64(base + offset * 1000)
        }
        // 클록 미동기 상태에서는 fallback latency를 빼서 ESP32가 과거 윈도와 매칭하도록 합니다.
        return Int64(base - LissenceBLEConstants.bleEstimatedLatencySeconds * 1000)
    }

    // MARK: - 스캔 처리

    /// Service UUID 스캔에서 연결되지 않은 경우 이름 기반 fallback 스캔을 시작합니다.
    private func startNameFallbackScanIfNeeded() {
        guard centralManager.state == .poweredOn else {
            isNameFallbackScan = false
            print("📡 [LissenceBLE] fallback scan skipped: state=\(stateText(for: centralManager.state))")
            return
        }

        guard connectedPeripheral == nil else {
            return
        }

        centralManager.stopScan()
        isNameFallbackScan = true
        notifyStatus("이름 기반 fallback 스캔 중")
        print("📡 [LissenceBLE] fallback 스캔 시작 (deviceName=\(LissenceBLEConstants.deviceName))")
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    /// 새 스캔을 위해 이전 연결 상태를 정리합니다.
    private func resetConnectionStateForNewScan() {
        centralManager.stopScan()
        messageCharacteristic = nil
        clockOffsetSeconds = nil
        lastClockPingAt = nil

        if let connectedPeripheral {
            centralManager.cancelPeripheralConnection(connectedPeripheral)
        }

        connectedPeripheral = nil
        notifyConnection(false)
    }

    /// 발견된 Peripheral이 연결 대상인지 판단합니다.
    private func shouldConnect(to peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        guard isNameFallbackScan else {
            return true
        }

        return advertisedName(for: peripheral, advertisementData: advertisementData) == LissenceBLEConstants.deviceName
    }

    /// Peripheral 이름 또는 광고 Local Name을 반환합니다.
    private func advertisedName(for peripheral: CBPeripheral, advertisementData: [String: Any]) -> String {
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            return localName
        }

        return peripheral.name ?? "이름 없음"
    }

    // MARK: - 연결 처리

    /// 발견된 Peripheral에 연결합니다.
    private func connect(to peripheral: CBPeripheral, deviceName: String) {
        centralManager.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        notifyDiscoveredDevice(deviceName)
        notifyStatus("\(deviceName) 연결 시도 중")
        centralManager.connect(peripheral)
    }

    /// 연결된 Peripheral에서 대상 service를 탐색합니다.
    private func discoverServices(on peripheral: CBPeripheral) {
        notifyStatus("BLE Service 탐색 중")
        peripheral.discoverServices([LissenceBLEConstants.serviceUUID])
    }

    /// 대상 service에서 문자열 송수신 characteristic을 탐색합니다.
    private func discoverMessageCharacteristic(in service: CBService, peripheral: CBPeripheral) {
        notifyStatus("BLE Characteristic 탐색 중")
        peripheral.discoverCharacteristics([LissenceBLEConstants.characteristicUUID], for: service)
    }

    /// 찾은 characteristic의 notify/read 기능을 활성화합니다.
    private func configureMessageCharacteristic(_ characteristic: CBCharacteristic, peripheral: CBPeripheral) {
        messageCharacteristic = characteristic

        if characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
        }

        if characteristic.properties.contains(.read) {
            peripheral.readValue(for: characteristic)
        }

        notifyStatus("BLE 연결 준비 완료")

        // 연결 직후 clock_ping을 보내 ESP32 방향 윈도와 iPhone 분류 시각을 동기화합니다.
        sendClockPing()
    }

    // MARK: - 메시지 처리

    /// Characteristic 값에서 UTF-8 문자열을 추출해 delegate로 전달합니다.
    private func handleReceivedValue(_ data: Data?) {
        guard let data else {
            notifyStatus("BLE 메시지 수신 데이터가 비어 있습니다.")
            return
        }

        guard let text = String(data: data, encoding: .utf8) else {
            notifyStatus("BLE 메시지 UTF-8 해석 실패")
            return
        }

        handleClockPongIfNeeded(text)
        notifyReceivedMessage(text)
    }

    /// Characteristic 속성에 맞는 write 방식을 선택합니다.
    private func writeType(for characteristic: CBCharacteristic) -> CBCharacteristicWriteType {
        if characteristic.properties.contains(.writeWithoutResponse) {
            return .withoutResponse
        }

        return .withResponse
    }

    // MARK: - 상태 업데이트

    /// Bluetooth 상태 enum을 화면 표시용 문구로 변환합니다.
    private func stateText(for state: CBManagerState) -> String {
        switch state {
        case .unknown:
            return "Bluetooth 상태 확인 중"
        case .resetting:
            return "Bluetooth 재설정 중"
        case .unsupported:
            return "이 기기에서 Bluetooth를 지원하지 않습니다."
        case .unauthorized:
            return "Bluetooth 권한이 없습니다."
        case .poweredOff:
            return "Bluetooth가 꺼져 있습니다."
        case .poweredOn:
            return "Bluetooth 사용 가능"
        @unknown default:
            return "알 수 없는 Bluetooth 상태"
        }
    }

    /// delegate 호출을 main thread에서 수행합니다.
    private func notifyOnMain(_ action: @escaping (LissenceBLEManagerDelegate) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let delegate = self.delegate else { return }
            action(delegate)
        }
    }

    /// Bluetooth 상태 문구를 전달합니다.
    private func notifyBluetoothState(_ stateText: String) {
        notifyOnMain { $0.bleManager(self, didUpdateBluetoothState: stateText) }
    }

    /// 진행 상태 문구를 전달합니다.
    private func notifyStatus(_ statusText: String) {
        notifyOnMain { $0.bleManager(self, didUpdateStatus: statusText) }
    }

    /// 연결 상태를 전달합니다.
    private func notifyConnection(_ isConnected: Bool) {
        notifyOnMain { $0.bleManager(self, didUpdateConnection: isConnected) }
    }

    /// 발견된 Peripheral 이름을 전달합니다.
    private func notifyDiscoveredDevice(_ deviceName: String) {
        notifyOnMain { $0.bleManager(self, didDiscoverDeviceName: deviceName) }
    }

    /// 수신 메시지를 전달합니다.
    private func notifyReceivedMessage(_ text: String) {
        let message = LissenceBLEMessage(text: text)
        notifyOnMain { $0.bleManager(self, didReceive: message) }
    }

    /// 송신 메시지를 전달합니다.
    private func notifySentMessage(_ text: String) {
        let message = LissenceBLEMessage(text: text)
        notifyOnMain { $0.bleManager(self, didSend: message) }
    }
}

// MARK: - CBCentralManagerDelegate

extension LissenceBLEManager: CBCentralManagerDelegate {
    /// Central Bluetooth 상태 변경을 처리합니다.
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        notifyBluetoothState(stateText(for: central.state))
        print("📡 [LissenceBLE] didUpdateState → \(stateText(for: central.state))")

        if central.state == .poweredOn {
            notifyStatus("BLE 스캔 준비 완료")

            // 사용자가 onAppear에서 startScan을 너무 일찍 호출했다면 여기서 자동으로 재실행합니다.
            if pendingScanRequest {
                print("📡 [LissenceBLE] BT 활성화 감지 → 대기 중이던 스캔 요청 실행")
                performScan()
            }
        }
    }

    /// 스캔으로 발견한 Peripheral을 연결 대상으로 처리합니다.
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard shouldConnect(to: peripheral, advertisementData: advertisementData) else {
            return
        }

        let deviceName = advertisedName(for: peripheral, advertisementData: advertisementData)
        connect(to: peripheral, deviceName: deviceName)
    }

    /// Peripheral 연결 완료 후 service 탐색을 시작합니다.
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        notifyConnection(true)
        notifyStatus("BLE 연결됨")
        discoverServices(on: peripheral)
    }

    /// Peripheral 연결 실패를 화면 상태로 전달합니다.
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        notifyConnection(false)
        notifyStatus("BLE 연결 실패: \(error?.localizedDescription ?? "원인 알 수 없음")")
    }

    /// Peripheral 연결 해제를 화면 상태로 전달합니다. 자동 재스캔을 트리거합니다.
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        messageCharacteristic = nil
        connectedPeripheral = nil
        clockOffsetSeconds = nil
        notifyConnection(false)

        if let error {
            notifyStatus("BLE 연결 해제: \(error.localizedDescription)")
        } else {
            notifyStatus("BLE 연결 해제")
        }

        // ESP32 전원 toggling 등으로 끊긴 경우 1초 뒤 자동 재스캔.
        bluetoothQueue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startScan()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension LissenceBLEManager: CBPeripheralDelegate {
    /// Peripheral service 탐색 결과에서 대상 service를 찾습니다.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            notifyStatus("BLE Service 탐색 실패: \(error.localizedDescription)")
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == LissenceBLEConstants.serviceUUID }) else {
            notifyStatus("대상 BLE Service를 찾지 못했습니다.")
            return
        }

        discoverMessageCharacteristic(in: service, peripheral: peripheral)
    }

    /// Service characteristic 탐색 결과에서 대상 characteristic을 설정합니다.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            notifyStatus("BLE Characteristic 탐색 실패: \(error.localizedDescription)")
            return
        }

        guard let characteristic = service.characteristics?.first(where: { $0.uuid == LissenceBLEConstants.characteristicUUID }) else {
            notifyStatus("대상 BLE Characteristic을 찾지 못했습니다.")
            return
        }

        configureMessageCharacteristic(characteristic, peripheral: peripheral)
    }

    /// notify 또는 read로 갱신된 characteristic 값을 처리합니다.
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            notifyStatus("BLE 메시지 수신 실패: \(error.localizedDescription)")
            return
        }

        handleReceivedValue(characteristic.value)
    }

    /// 응답이 필요한 write 결과를 처리합니다.
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            pendingWritePayload = nil
            notifyStatus("BLE 메시지 전송 실패: \(error.localizedDescription)")
            return
        }

        if let pendingWritePayload {
            notifySentMessage(pendingWritePayload)
            self.pendingWritePayload = nil
        }

        notifyStatus("BLE 메시지 전송 완료")
    }
}
