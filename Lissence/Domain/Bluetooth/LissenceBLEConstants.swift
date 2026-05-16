/// HearAlert ESP32 Peripheral과 통신하기 위한 고정 식별자와 타이밍 상수를 정의합니다.
/// 값이 변경되면 ESP32 펌웨어(main.cpp)의 SERVICE_UUID, CHAR_UUID, DEVICE_NAME과 반드시 일치해야 합니다.

import CoreBluetooth
import Foundation

/// HearAlert ESP32 BLE Peripheral과 통신하기 위한 상수 모음입니다.
enum LissenceBLEConstants {
    // MARK: - Peripheral 식별자

    /// ESP32 Peripheral 광고 이름입니다.
    static let deviceName = "HearAlert"

    /// ESP32 Custom GATT Service UUID입니다.
    static let serviceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")

    /// ESP32와 문자열을 주고받는 Characteristic UUID입니다.
    static let characteristicUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")

    // MARK: - 스캔 설정

    /// Service UUID 스캔에서 장치를 찾지 못했을 때 이름 기반 fallback으로 전환하기까지 기다리는 시간입니다.
    static let serviceScanTimeout: TimeInterval = 5

    // MARK: - 타이밍 상수

    /// 동일 위험 소리가 짧은 시간 안에 반복 분류될 때 BLE write를 건너뛰는 쿨다운입니다.
    static let bleWriteCooldownSeconds: TimeInterval = 0.8

    /// 클록 동기 실패 시 ESP32 윈도 매칭에 사용할 추정 latency입니다.
    static let bleEstimatedLatencySeconds: TimeInterval = 0.15

    /// 클록 동기 pong 응답을 기다릴 최대 시간입니다. 초과 시 fallback latency 모드로 전환합니다.
    static let clockSyncTimeoutSeconds: TimeInterval = 1.5

    /// iPhone SoundAnalysis 분류 결과의 유효 윈도 길이입니다. ESP32 방향 윈도 매칭에 사용됩니다.
    static let analysisWindowSeconds: TimeInterval = 0.975
}
