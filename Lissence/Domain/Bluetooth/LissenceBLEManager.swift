/// CoreBluetooth 기반으로 Lissence ESP32 Peripheral 스캔, 연결, notify 구독, 문자열 write를 수행합니다.

import CoreBluetooth
import Foundation

/// ESP32 PCM audio stream binary packet 규격입니다.
private enum AudioStreamPacketFormat {
    /// ESP32 firmware의 audio packet payload 최대 byte 크기입니다.
    static let maxAudioPacketPayloadSize = 160
}

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

    /// ESP32에서 PCM audio stream binary packet을 받았을 때 호출됩니다.
    func bleManager(_ manager: LissenceBLEManager, didReceiveAudioPacket data: Data)

    /// ESP32로 문자열 메시지 전송이 완료되었거나 전송 요청이 큐에 들어갔을 때 호출됩니다.
    func bleManager(_ manager: LissenceBLEManager, didSend message: LissenceBLEMessage)
}

/// Lissence ESP32 BLE Peripheral과 통신하는 CoreBluetooth 서비스 객체입니다.
final class LissenceBLEManager: NSObject {
    // MARK: - 속성

    /// BLE 테스트와 앱 내부 write 경로에서 공유하는 ESP32 BLE manager입니다.
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

    // MARK: - 시작 제어

    /// BLE 스캔을 시작합니다. 먼저 Service UUID로 스캔하고, 일정 시간 후 이름 기반 스캔으로 fallback합니다.
    func startScan() {
        bluetoothQueue.async { [weak self] in
            guard let self else { return }

            guard self.centralManager.state == .poweredOn else {
                self.notifyStatus("Bluetooth가 준비되지 않았습니다.")
                self.notifyBluetoothState(self.stateText(for: self.centralManager.state))
                return
            }

            self.resetConnectionStateForNewScan()
            self.isNameFallbackScan = false
            self.notifyStatus("Service UUID로 ESP32 스캔 중")
            self.centralManager.scanForPeripherals(
                withServices: [LissenceBLEConstants.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )

            self.bluetoothQueue.asyncAfter(deadline: .now() + LissenceBLEConstants.serviceScanTimeout) { [weak self] in
                self?.startNameFallbackScanIfNeeded()
            }
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

    /// ESP32로 햅틱 테스트 payload를 전송합니다.
    func writeWarningHapticCommand() {
        write(LissenceBLEConstants.warningHapticPayload)
    }

    /// ESP32로 지정된 햅틱 pattern 실행 command를 전송합니다.
    func writeHapticPattern(_ pattern: String) {
        let payload = #"{"type":"haptic","pattern":"\#(pattern)"}"#
        write(payload)
    }

    /// ESP32 3초 PCM audio stream 시작 command를 전송합니다.
    func writeStartAudioStreamCommand() {
        write(#"{"type":"config","audio_stream":true}"#)
    }

    /// ESP32 PCM audio stream 중지 command를 전송합니다.
    func writeStopAudioStreamCommand() {
        write(#"{"type":"config","audio_stream":false}"#)
    }

    /// ESP32로 UTF-8 문자열을 전송합니다.
    func write(_ text: String) {
        bluetoothQueue.async { [weak self] in
            guard let self else { return }

            guard let connectedPeripheral = self.connectedPeripheral,
                  let messageCharacteristic = self.messageCharacteristic else {
                self.notifyStatus("전송할 BLE 연결이 없습니다.")
                return
            }

            guard let data = text.data(using: .utf8) else {
                self.notifyStatus("UTF-8 변환 실패")
                return
            }

            let writeType = self.writeType(for: messageCharacteristic)
            if writeType == .withResponse {
                self.pendingWritePayload = text
            }

            connectedPeripheral.writeValue(data, for: messageCharacteristic, type: writeType)

            if writeType == .withoutResponse {
                self.notifySentMessage(text)
                self.notifyStatus("BLE 메시지 전송 요청 완료")
            } else {
                self.notifyStatus("BLE 메시지 전송 중")
            }
        }
    }

    // MARK: - 스캔 처리

    /// Service UUID 스캔에서 연결되지 않은 경우 이름 기반 fallback 스캔을 시작합니다.
    private func startNameFallbackScanIfNeeded() {
        guard connectedPeripheral == nil else {
            return
        }

        centralManager.stopScan()
        isNameFallbackScan = true
        notifyStatus("이름 기반 fallback 스캔 중")
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    /// 새 스캔을 위해 이전 연결 상태를 정리합니다.
    private func resetConnectionStateForNewScan() {
        centralManager.stopScan()
        messageCharacteristic = nil

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
    }

    // MARK: - 메시지 처리

    /// Characteristic 값에서 UTF-8 문자열 또는 PCM audio stream binary packet을 추출해 delegate로 전달합니다.
    private func handleReceivedValue(_ data: Data?) {
        guard let data else {
            notifyStatus("BLE 메시지 수신 데이터가 비어 있습니다.")
            return
        }

        if isAudioStreamPacket(data) {
            notifyReceivedAudioPacket(data)
            return
        }

        guard let text = String(data: data, encoding: .utf8) else {
            notifyStatus("BLE 메시지 UTF-8 해석 실패")
            return
        }

        notifyReceivedMessage(text)
    }

    /// binary notify payload가 PCM audio stream packet 형식인지 검사합니다.
    private func isAudioStreamPacket(_ data: Data) -> Bool {
        guard data.count >= 7,
              data[0] == 0xA1 else {
            return false
        }

        let packetIndex = data[3]
        let packetCount = data[4]
        let payloadSize = Int(data[5]) | (Int(data[6]) << 8)

        return packetCount > 0 &&
            packetIndex < packetCount &&
            payloadSize > 0 &&
            payloadSize <= AudioStreamPacketFormat.maxAudioPacketPayloadSize &&
            data.count == 7 + payloadSize
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

    /// 수신한 PCM audio stream binary packet을 전달합니다.
    private func notifyReceivedAudioPacket(_ data: Data) {
        notifyOnMain { $0.bleManager(self, didReceiveAudioPacket: data) }
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

        if central.state == .poweredOn {
            notifyStatus("BLE 스캔 준비 완료")
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

    /// Peripheral 연결 해제를 화면 상태로 전달합니다.
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        messageCharacteristic = nil
        connectedPeripheral = nil
        notifyConnection(false)

        if let error {
            notifyStatus("BLE 연결 해제: \(error.localizedDescription)")
        } else {
            notifyStatus("BLE 연결 해제")
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
