# 한국기술교육대학교 LISSENCE 팀

청각장애인을 위한 촉각, 시각 변환 시스템

## iOS 앱

이 저장소는 Lissence iPhone / Apple Watch 앱을 관리합니다. 현재 작업 브랜치는 ESP32 BLE 연동과 candidate-triggered 위험 감지 PoC를 포함합니다.

## 현재 주요 기능

- iPhone 감지 모드
  - iPhone 마이크 기반 SoundAnalysis 위험 소리 감지
  - 음성인식 자막 기능
  - BLE `audio_candidate` 수신 시 iPhone 마이크 위험 분석을 짧게 실행하는 PoC
- iPhone 음악 모드
  - 마이크 입력 기반 음악 mood 분석 PoC
  - mood 상태 ViewModel 노출
- BLE 테스트 화면
  - ESP32 Peripheral scan / connect / notify / write
  - `mic_level`, `audio_candidate` notify 표시
  - BLE PCM stream reconstruction / ring buffer / lightweight stats PoC
  - 위험 감지 결과를 ESP32 DRV2605L haptic command로 write
- Apple Watch 앱
  - 기존 Watch 감지 UI 및 WatchConnectivity 구조 유지

## BLE 대상 장치

ESP32 Peripheral:

```text
Device name: Lissence-ESP32
Service UUID: 7d2f3a10-3b7a-4f9f-9b37-6b6a0f4f7c10
Characteristic UUID: 7d2f3a11-3b7a-4f9f-9b37-6b6a0f4f7c10
```

햅틱 write 예시:

```json
{"type":"haptic","pattern":"warning"}
```

지원 pattern:

- `siren`
- `fireAlarm`
- `carHorn`
- `warning`
- `test`

## 빌드

Xcode에서 `Lissence/Lissence.xcodeproj`를 열고 `Lissence` scheme을 선택합니다.

CLI generic iOS build:

```bash
xcodebuild -project Lissence/Lissence.xcodeproj \
  -scheme Lissence \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /Users/administrator/Portfolio/Lissence_iOS/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

## GitHub 업로드 전 제외 대상

아래 항목은 `.gitignore`로 제외합니다.

- `DerivedData/`
- `build/`
- `xcuserdata/`
- `*.xcuserstate`
- `*.ipa`
- `*.dSYM`
- `.DS_Store`
