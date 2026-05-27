# Recent Updates: Final Presentation Stabilization

This document records the work completed after the May 21 feature-complete build. The focus was not adding many new screens, but making the real iPhone + Watch + ESP32 demo reliable.

## Summary

After the core app was working, the remaining problems were integration problems:

- STT looked like it missed the first syllable after TTS.
- Speech recognition could interfere with danger sound detection.
- BLE hardware direction matching needed precise time sync.
- Attention-call hardware haptics needed a separate path from danger haptics.
- The first attention haptic patterns were technically working but felt weak on the actual board.

The final work stabilized these areas and made the behavior easier to explain in the presentation.

## TTS 이후 STT 첫 음절 누락 수정

## 기능

Conversation and subtitle STT after TTS.

## 문제

When TTS finished and the other person spoke immediately, the visible transcript sometimes lost the first syllable:

- `한기대` -> `기대`
- `도서관` -> `서관`

## 원인

Logs showed that raw STT already received the first syllable:

```text
[STT] first partial received ... text=한
raw=한기대 갈려면
baseline=한
visible=기대 갈려면
```

The problem was not that the microphone started too late. The display baseline was set too early using a short unstable partial such as `한`. Later delta rendering subtracted that baseline and hid the first syllable.

## 해결

The baseline logic was adjusted so that an empty baseline does not immediately turn a very short first partial into text to subtract. Baseline still exists for its original purpose: hiding old background STT when the voice UI opens.

## 결과

TTS after conversation and subtitle flows now keep the first syllable visible in tested examples such as `한기대` and `도서관`.

## Speech Gate 기반 호출어 감지

## 기능

Default detection mode attention-call detection.

## 문제

The app needed danger detection and "저기요" detection at the same time. Running `SpeechManager` too aggressively could reconfigure the audio session and interrupt the `SoundDetector` analyzer callbacks. The visible symptom was that danger `top3` logs stopped.

## 원인

`SoundDetector` and `SpeechManager` both need microphone input. When STT restarted in the default detection state, it could interfere with the always-on SoundAnalysis pipeline.

## 해결

The final structure keeps `SoundDetector` always on. SoundAnalysis speech labels are used only as a trigger. When speech confidence is high enough, `DetectionViewModel` briefly starts STT through a speech gate, sends transcript to `AttentionCallAnalyzer`, and stops STT after a short timeout.

## 결과

Danger detection stays alive while default detection mode can still recognize:

- single "저기요"
- repeated "저기요 저기요"
- emergency "저기요 조심하세요"

## Attention Haptic BLE 추가

## 기능

ESP32 hardware haptics for attention calls.

## 문제

Danger BLE messages use timestamp and window fields for direction matching. Attention calls do not need direction, but they do need immediate tactile feedback. Reusing the danger `haptic` protocol would mix two different behaviors.

## 해결

A separate attention-call BLE protocol was added:

```json
{"type":"attention_haptic","pattern":"single"}
{"type":"attention_haptic","pattern":"repeat"}
{"type":"attention_haptic","pattern":"emergency"}
```

The iPhone sends these only when the corresponding attention haptic slider is ON. If the slider is OFF, the screen still shows the alert but iPhone and ESP32 attention haptics are skipped.

## 결과

The BLE design became clearer:

- danger sound: precise timestamp + direction matching
- attention call: immediate both-motor haptic

This also makes the presentation easier to explain.

## BLE Precise Clock Sync 안정화

## 기능

iPhone danger classification timestamp alignment with ESP32 ring buffer.

## 문제

The ESP32 could receive danger haptic commands, but without working `clock_pong` notify handling, iOS stayed in fallback timestamp mode. In fallback mode, direction matching is less precise.

## 원인

The write path and notify path may use different BLE characteristic capabilities. Writes worked, but `clock_pong` notify was not always being received by iOS.

## 해결

The BLE manager now discovers write and notify characteristics separately, subscribes to notify/indicate characteristics, logs raw notify payloads, and robustly parses `clock_pong`.

## 결과

Device testing confirmed:

- `clock_pong` received
- `precise timestamp enabled`
- `BLEHaptic mode=precise`
- ESP32 millis-coordinate `ts`
- MATCH-A direction matching

Fallback latency mode remains available if sync fails.

## 위험음 오탐 감소 정책

## 기능

iPhone danger classification filtering.

## 문제

Apple SoundAnalysis returns many labels, including speech-like and non-danger sounds. Accepting too many labels would create false alerts in a noisy presentation space.

## 해결

The final danger policy accepts only:

- `siren`
- `fireAlarm`
- `carHorn`

The app applies confidence filtering and keeps BLE cooldown to avoid repeated writes from the same sound.

## 결과

The danger pipeline is narrower but more reliable for the actual demo. Speech labels are reused for speech gate instead of becoming danger alerts.

## 호출어 햅틱 UX 개선

## 기능

ESP32 attention `single` and `repeat` vibration feel.

## 문제

The first hardware attention haptic patterns technically fired, but `single` and `repeat` felt like a short "삑" sound instead of a clear vibration.

## 원인

The old single/repeat patterns used weak, short pulses. The motor produced an audible tick before creating a strong tactile feel. Emergency already used a stronger pattern and was left unchanged.

## 해결

In `Hardware_HearAlert_2Mic_2Haptic/main.cpp`:

- `PAT_GENTLE`: `300ms duty 200`, `80ms off`, `120ms duty 200`
- `PAT_ATTENTION_REPEAT`: the single "웅~윙" pattern repeated twice with a `180ms` gap

The following were not changed:

- emergency pattern
- danger haptic path
- BLE protocol
- clock sync
- precise/fallback mode
- direction matching

## 결과

Single attention calls now feel like `웅~윙`. Repeated attention calls feel like `웅~윙, 웅~윙`. Emergency remains a stronger alert.

## 최종 검증

Final presentation checks confirmed:

- iOS generic build succeeded
- Watch build succeeded
- BLE precise sync worked
- ESP32 MATCH-A direction matching worked
- danger detection worked for `carHorn`, `siren`, and `fireAlarm`
- attention BLE `single`, `repeat`, and `emergency` worked
- speech gate kept SoundDetector logs alive
- TTS after STT kept the first syllable visible

The final work after May 21 focused on real presentation stability and end-to-end reliability rather than simply adding more features.
