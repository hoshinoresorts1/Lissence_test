# 한국기술교육대학교 LISSENCE 팀

청각장애인을 위한 촉각, 시각 변환 시스템

## iOS 앱

이 저장소는 최종 발표용 Lissence iPhone / Apple Watch 앱을 관리합니다. iPhone이 위험 소리를 분석하고, HearAlert ESP32 보드가 양쪽 마이크 방향 감지와 양쪽 햅틱 모터 출력을 담당하는 구조입니다.

## 현재 주요 기능

- iPhone 감지 모드
  - iPhone 마이크 기반 SoundAnalysis 위험 소리 감지
  - speech gate 기반 "저기요" 호출어 감지
  - 음성인식 자막 기능
  - 위험 소리 분류 결과를 HearAlert 보드로 BLE write
  - 분류 시각 `ts`와 분석 window `win`을 함께 전송해 보드의 방향 ring buffer와 매칭
  - 호출어 전용 `attention_haptic` BLE 메시지로 즉시 양쪽 모터 진동
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

호출어 햅틱 write 예시:

```json
{"type":"attention_haptic","pattern":"single"}
{"type":"attention_haptic","pattern":"repeat"}
{"type":"attention_haptic","pattern":"emergency"}
```

위험음은 `ts/win` 기반 정밀 방향 매칭을 사용하고, 호출어는 방향 매칭 없이 즉시 양쪽 모터를 울립니다.

## 최종 안정화 요약

5월 21일 완성본 이후에는 기능 추가보다 발표 환경에서의 안정성과 통합 동작 신뢰성을 높이는 데 집중했습니다.

- TTS 직후 STT 첫 음절이 사라지는 문제를 baseline/delta transcript 처리 개선으로 해결했습니다.
- 위험음 감지와 호출어 STT가 마이크를 두고 충돌하지 않도록 speech gate 구조를 적용했습니다.
- BLE `clock_ping` / `clock_pong` 기반 precise timestamp 변환을 안정화하고, 실패 시 fallback latency 모드를 유지했습니다.
- 위험음 BLE와 호출어 BLE를 분리해 위험음은 방향 매칭, 호출어는 즉시 햅틱으로 역할을 나눴습니다.
- ESP32 호출어 `single/repeat` 햅틱을 짧은 "삑"이 아니라 사용자가 느끼기 쉬운 "웅~윙" 패턴으로 조정했습니다.
- iPhone + Watch + ESP32 실기기 통합 테스트에서 위험음 감지, BLE precise sync, MATCH-A 방향 매칭, 호출어 햅틱, TTS 이후 첫 음절 유지 흐름을 확인했습니다.

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
