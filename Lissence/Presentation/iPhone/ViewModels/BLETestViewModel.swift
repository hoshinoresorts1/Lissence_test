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

    /// ESP32에서 최근 수신한 INMP441 RMS 값입니다.
    @Published var latestMicRMS: Int?

    /// ESP32에서 최근 수신한 INMP441 peak 값입니다.
    @Published var latestMicPeak: Int?

    /// 최근 RMS 값 기준의 간단한 마이크 입력 상태입니다.
    @Published var micLevelStateText = "-"

    /// PCM audio stream binary packet 수신 개수입니다.
    @Published var audioPacketsReceived = 0

    /// 재조립에 성공한 20ms PCM chunk 개수입니다.
    @Published var audioChunksReconstructed = 0

    /// sequence gap 기준으로 감지한 누락 chunk 개수입니다.
    @Published var audioDroppedChunks = 0

    /// 최근 재조립한 PCM chunk byte 크기입니다.
    @Published var latestAudioChunkSize = 0

    /// 최근 수신한 PCM audio stream sequence입니다.
    @Published var latestAudioSequence: UInt16?

    /// PCM audio stream 테스트 상태 문구입니다.
    @Published var audioStreamingStateText = "idle"

    /// 테스트 write 버튼 활성화 여부입니다.
    var canSendTestCommand: Bool {
        isConnected
    }

    /// PCM audio stream 버튼 활성화 여부입니다.
    var canControlAudioStream: Bool {
        isConnected
    }

    /// 화면에 표시할 최근 RMS 값 문자열입니다.
    var latestMicRMSText: String {
        latestMicRMS.map(String.init) ?? "-"
    }

    /// 화면에 표시할 최근 peak 값 문자열입니다.
    var latestMicPeakText: String {
        latestMicPeak.map(String.init) ?? "-"
    }

    /// 화면에 표시할 최근 PCM audio stream sequence 문자열입니다.
    var latestAudioSequenceText: String {
        latestAudioSequence.map(String.init) ?? "-"
    }

    /// BLE 통신을 담당하는 서비스 객체입니다.
    private let bleManager: LissenceBLEManager

    /// sequence별 미완성 PCM chunk 조립 버퍼입니다.
    private var audioChunkBuffers: [UInt16: AudioChunkBuffer] = [:]

    /// 다음에 완성될 것으로 기대하는 sequence입니다.
    private var expectedAudioSequence: UInt16?

    /// 오래된 자동 종료 타이머가 최신 stream 상태를 덮어쓰지 않도록 구분하는 ID입니다.
    private var audioStreamRequestID = 0

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

    /// ESP32에 3초 PCM audio stream 시작을 요청합니다.
    func startAudioStream() {
        resetAudioStreamStats()
        audioStreamingStateText = "requested"
        audioStreamRequestID += 1
        let requestID = audioStreamRequestID
        bleManager.writeStartAudioStreamCommand()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard let self,
                  self.audioStreamRequestID == requestID,
                  self.audioStreamingStateText != "stop requested" else {
                return
            }

            self.audioStreamingStateText = "completed"
        }
    }

    /// ESP32에 PCM audio stream 중지를 요청합니다.
    func stopAudioStream() {
        audioStreamRequestID += 1
        audioStreamingStateText = "stop requested"
        bleManager.writeStopAudioStreamCommand()
    }

    // MARK: - 수신 메시지 처리

    /// BLE notify 문자열에서 mic_level payload를 파싱해 마이크 레벨 상태를 갱신합니다.
    private func updateMicLevelIfNeeded(from text: String) {
        guard let data = text.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["type"] as? String == "mic_level",
              let rms = payload["rms"] as? Int,
              let peak = payload["peak"] as? Int else {
            return
        }

        latestMicRMS = rms
        latestMicPeak = peak
        micLevelStateText = micLevelState(for: rms)
    }

    /// RMS 값 기준으로 BLE 테스트 화면에 표시할 간단한 상태값을 반환합니다.
    private func micLevelState(for rms: Int) -> String {
        switch rms {
        case ..<8_000:
            return "quiet"
        case 8_000..<50_000:
            return "active"
        default:
            return "loud"
        }
    }

    // MARK: - Audio stream 처리

    /// PCM audio stream 통계와 조립 버퍼를 초기화합니다.
    private func resetAudioStreamStats() {
        audioPacketsReceived = 0
        audioChunksReconstructed = 0
        audioDroppedChunks = 0
        latestAudioChunkSize = 0
        latestAudioSequence = nil
        audioChunkBuffers.removeAll()
        expectedAudioSequence = nil
    }

    /// binary notify packet을 20ms PCM chunk 단위로 재조립합니다.
    private func handleAudioPacket(_ data: Data) {
        guard let packet = AudioStreamPacket(data: data) else {
            return
        }

        audioPacketsReceived += 1
        latestAudioSequence = packet.sequence
        audioStreamingStateText = "receiving"

        var buffer = audioChunkBuffers[packet.sequence] ?? AudioChunkBuffer(packetCount: packet.packetCount)
        buffer.append(packet)
        audioChunkBuffers[packet.sequence] = buffer

        pruneIncompleteAudioChunks(currentSequence: packet.sequence)

        guard buffer.isComplete, let chunk = buffer.reconstructedData else {
            return
        }

        audioChunkBuffers.removeValue(forKey: packet.sequence)
        updateSequenceGapIfNeeded(completedSequence: packet.sequence)
        audioChunksReconstructed += 1
        latestAudioChunkSize = chunk.count
    }

    /// 오래 남은 미완성 chunk를 누락으로 계산하고 버퍼에서 제거합니다.
    private func pruneIncompleteAudioChunks(currentSequence: UInt16) {
        let staleSequences = audioChunkBuffers.keys.filter { sequence in
            currentSequence > sequence && currentSequence - sequence > 2
        }

        audioDroppedChunks += staleSequences.count
        staleSequences.forEach { audioChunkBuffers.removeValue(forKey: $0) }
    }

    /// 완성된 sequence 사이의 gap을 dropped chunk로 계산합니다.
    private func updateSequenceGapIfNeeded(completedSequence: UInt16) {
        guard let expectedAudioSequence else {
            self.expectedAudioSequence = completedSequence &+ 1
            return
        }

        if completedSequence > expectedAudioSequence {
            audioDroppedChunks += Int(completedSequence - expectedAudioSequence)
        }

        self.expectedAudioSequence = completedSequence &+ 1
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
        updateMicLevelIfNeeded(from: message.text)
    }

    /// ESP32에서 받은 PCM audio stream binary packet을 재조립 통계에 반영합니다.
    func bleManager(_ manager: LissenceBLEManager, didReceiveAudioPacket data: Data) {
        handleAudioPacket(data)
    }

    /// ESP32로 보낸 메시지를 ViewModel 상태로 반영합니다.
    func bleManager(_ manager: LissenceBLEManager, didSend message: LissenceBLEMessage) {
        lastSentMessage = message.text
    }
}

// MARK: - Audio stream packet

/// ESP32 PCM audio stream binary notify packet입니다.
private struct AudioStreamPacket {
    /// 20ms PCM chunk sequence입니다.
    let sequence: UInt16

    /// chunk 내부 packet index입니다.
    let packetIndex: Int

    /// chunk를 구성하는 전체 packet 수입니다.
    let packetCount: Int

    /// packet에 포함된 PCM payload입니다.
    let payload: Data

    /// binary packet header를 해석해 audio stream packet을 생성합니다.
    init?(data: Data) {
        guard data.count >= 7,
              data[0] == 0xA1 else {
            return nil
        }

        let payloadSize = Int(data[5]) | (Int(data[6]) << 8)
        guard payloadSize > 0,
              payloadSize <= 120,
              data.count == 7 + payloadSize else {
            return nil
        }

        self.sequence = UInt16(data[1]) | (UInt16(data[2]) << 8)
        self.packetIndex = Int(data[3])
        self.packetCount = Int(data[4])
        self.payload = data.subdata(in: 7..<data.count)

        guard packetCount > 0,
              packetIndex >= 0,
              packetIndex < packetCount else {
            return nil
        }
    }
}

/// sequence 하나에 속한 여러 binary packet을 PCM chunk로 조립하는 버퍼입니다.
private struct AudioChunkBuffer {
    /// chunk를 구성하는 전체 packet 수입니다.
    let packetCount: Int

    /// packet index별 PCM payload입니다.
    private var payloads: [Int: Data] = [:]

    /// 필요한 packet 수로 빈 chunk 조립 버퍼를 생성합니다.
    init(packetCount: Int) {
        self.packetCount = packetCount
    }

    /// 모든 packet을 수신했는지 여부입니다.
    var isComplete: Bool {
        payloads.count == packetCount
    }

    /// packet index 순서대로 결합한 PCM chunk입니다.
    var reconstructedData: Data? {
        guard isComplete else {
            return nil
        }

        return (0..<packetCount).reduce(into: Data()) { result, index in
            if let payload = payloads[index] {
                result.append(payload)
            }
        }
    }

    /// 수신한 packet을 버퍼에 저장합니다.
    mutating func append(_ packet: AudioStreamPacket) {
        guard packet.packetCount == packetCount else {
            return
        }

        payloads[packet.packetIndex] = packet.payload
    }
}
