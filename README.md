# 한국기술교육대학교 LISSENCE 팀

청각장애인을 위한 촉각, 시각 변환 시스템

## iOS 앱

이 저장소는 최종 발표용 Lissence iPhone / Apple Watch 앱을 관리합니다. iPhone이 위험 소리를 분석하고, HearAlert ESP32 보드가 양쪽 마이크 방향 감지와 양쪽 햅틱 모터 출력을 담당하는 구조입니다.

## 현재 주요 기능

- iPhone 감지 모드
  - iPhone 마이크 기반 SoundAnalysis 위험 소리 감지
  - 음성인식 자막 기능
  - 위험 소리 분류 결과를 HearAlert 보드로 BLE write
  - 분류 시각 `ts`와 분석 window `win`을 함께 전송해 보드의 방향 ring buffer와 매칭
- iPhone 음악 모드
  - 마이크 입력 기반 음악 mood 분석 PoC
  - mood 상태 ViewModel 노출
- Apple Watch 앱
  - 기존 Watch 감지 UI 및 WatchConnectivity 구조 유지

## BLE 대상 장치

ESP32 Peripheral:

```text
Device name: HearAlert
Service UUID: 4fafc201-1fb5-459e-8fcc-c5c9c331914b
Characteristic UUID: beb5483e-36e1-4688-b7f5-ea07361b26a8
```

햅틱 write 예시:

```json
{"type":"haptic","pattern":"siren","ts":123456,"win":975}
```

지원 pattern:

- `siren`
- `fireAlarm`
- `carHorn`

## 빌드

Xcode에서 `Lissence/Lissence.xcodeproj`를 열고 `Lissence` scheme을 선택합니다.

CLI generic iOS build:

```bash
xcodebuild -project Lissence/Lissence.xcodeproj \
  -scheme Lissence \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /Users/administrator/Portfolio/Final_Presentation/iOS_HearAlert_Direction_App/DerivedData \
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
