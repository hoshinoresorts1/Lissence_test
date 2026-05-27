# Presentation Notes

Use this document as a short speaking guide for the final presentation and portfolio explanation.

## One-Line Project Explanation

Lissence is an iPhone, Apple Watch, and ESP32-based hearing assistance prototype that detects danger sounds and attention calls, then converts them into visual, haptic, Watch, and hardware feedback.

## Final Stabilization Story

The core feature set was mostly complete by May 21. After that point, the work shifted to presentation stability:

> We focused less on adding new features and more on making sure the iPhone, Watch, and ESP32 worked together reliably in real demo conditions.

The final problems were not simple UI bugs. They were integration issues between audio recognition, TTS, BLE timing, and physical hardware feedback.

## Key Talking Points

## 1. TTS 이후 STT 첫 음절 누락

## 기능

TTS after conversation and subtitle mode.

## 문제

After the app spoke a recommended phrase, the next user's first word sometimes appeared cut:

- `한기대` became `기대`
- `도서관` became `서관`

## 해결

We checked the logs and found that STT raw text already contained the first syllable. The real problem was the baseline/delta display logic. A very short first partial like `한` was being used as the baseline, so the UI subtracted it from the next transcript.

We changed the baseline handling so unstable early partials are not used as subtraction baselines.

## 결과

The first syllable now stays visible after TTS.

## 2. 위험음 감지와 호출어 STT 충돌

## 기능

Default detection mode should detect both danger sounds and "저기요" calls.

## 문제

If STT was always on, `SpeechManager` could interfere with `SoundDetector`. The danger detector engine looked started, but `top3` analysis logs stopped.

## 해결

We made SoundDetector the always-on base pipeline. STT is opened only when SoundAnalysis detects speech above a threshold. This is the speech gate.

## 결과

Danger detection remains alive, and attention-call detection still works when someone speaks.

## 3. BLE Precise Sync

## 기능

ESP32 direction haptic for danger sounds.

## 문제

SoundAnalysis detects a sound after the real sound occurs. If we send only the BLE arrival time, the ESP32 cannot match direction accurately.

## 해결

iPhone and ESP32 synchronize clocks through `clock_ping` and `clock_pong`. iPhone converts the detected sound timestamp into ESP32 `millis()` time and sends it with the analysis window.

```json
{"type":"haptic","pattern":"carHorn","ts":81636,"win":975}
```

## 결과

ESP32 can search its microphone ring buffer around that time and run MATCH-A direction matching. If sync fails, fallback latency mode still works.

## 4. 위험음 BLE와 호출어 BLE 분리

## 기능

ESP32 hardware feedback for both danger sounds and attention calls.

## 문제

Danger sounds need timestamp and direction matching. Attention calls do not. Mixing them into one protocol would make the hardware behavior harder to control.

## 해결

We split the BLE messages:

Danger:

```json
{"type":"haptic","pattern":"siren","ts":123456,"win":975}
```

Attention:

```json
{"type":"attention_haptic","pattern":"single"}
```

## 결과

The explanation is simple:

- danger sound = precise BLE + direction matching
- attention call = immediate BLE haptic

## 5. 위험음 오탐 감소

## 기능

iPhone-only danger classification.

## 문제

SoundAnalysis can produce many labels. If speech or other noise became danger alerts, the demo would be unstable.

## 해결

The final demo limits danger categories to:

- siren
- fireAlarm
- carHorn

Confidence filtering and BLE cooldown reduce repeated false or excessive hardware writes.

## 결과

The system is narrower but more reliable for the actual presentation scenario.

## 6. 호출어 햅틱 UX 개선

## 기능

ESP32 attention-call vibration feel.

## 문제

The original `single` and `repeat` attention haptics felt like small beeps instead of clear vibrations.

## 해결

The ESP32 attention patterns were tuned:

- single: `300ms duty 200`, `80ms off`, `120ms duty 200`
- repeat: the single pattern repeated twice
- emergency: unchanged because it already felt strong

## 결과

Single attention now feels like `웅~윙`; repeated attention feels like `웅~윙, 웅~윙`.

## Final Verification Statement

Final integrated testing confirmed:

- iOS build succeeded
- Watch build succeeded
- BLE precise sync worked
- ESP32 MATCH-A direction matching worked
- danger detection worked
- attention BLE haptics worked
- speech gate kept SoundDetector alive
- TTS after STT kept the first syllable visible

## Closing Summary

After the May 21 completed build, the final work focused on stability rather than feature count. The important improvement was making the full chain work together:

> iPhone recognizes the sound, Watch receives the alert, ESP32 matches direction or fires the right haptic pattern, and the speech UI stays usable without breaking danger detection.
