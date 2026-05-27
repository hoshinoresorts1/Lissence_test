# Troubleshooting Log

This document records issues that were actually encountered while stabilizing the iOS and ESP32 demo. It is written as maintenance history, not as a feature list.

## TTS 이후 STT 첫 단어 유실 문제

### 문제 현상

In conversation and subtitle modes, after the app played a TTS sentence, the other person's immediate response sometimes appeared with the first word or first syllable missing.

Examples:

- User says: `한기대 갈려면 버스 몇번 타요?`
- UI shows: `기대 갈려면...` or `향기대...`
- User says: `도서관...`
- UI shows: `서관...`

### 원인 분석

The first suspicion was STT capture delay after TTS, but diagnostic logs showed that the STT engine did receive the first partial from the beginning.

The real issue was in display-side baseline/delta processing:

- first partial received: `한`
- later raw transcript: `한기대 갈려면`
- baseline had already been set to `한`
- visible transcript became `기대 갈려면`

So the audio was not lost. The UI removed the first syllable because it treated an unstable early partial as the baseline to subtract.

### 실제 로그 근거

Representative log pattern:

```text
[TTS] didFinish -> schedule STT restart after 0.1s
[STT] audio engine actually started timestamp=... reason=tts-finished
[STT] first partial received timestamp=... reason=tts-finished text=한
[STT] transcript route mode=conversation raw=한기대 갈려면 baseline=한 visible=기대 갈려면 displayed=true
```

After the fix, the expected log pattern is:

```text
[STT] first partial received timestamp=... reason=tts-finished text=한
[STT] baseline empty -> display raw=한
[STT] transcript route mode=conversation raw=한기대 갈려면 baseline=<empty> visible=한기대 갈려면 displayed=true
```

### 해결 방법

`visibleSpeechText(from:)` was changed so that an empty `visibleTranscriptBaseline` does not cause the first partial to become a baseline. When the baseline is empty, the app now treats the incoming transcript as the new visible sentence and displays it as-is.

Baseline removal still exists for the original purpose: removing transcript text that existed before the voice UI session began.

### 현재 상태

The behavior is fixed at the display logic level. STT restart delay remains `0.1s`. Audio session policy was not changed for this fix.

Final presentation verification confirmed that the first syllable in examples such as `한기대` and `도서관` remains visible after TTS.

### 남은 이슈

The fix should be verified on device for both:

- conversation mode
- subtitle mode

Both paths share the same `updateVisibleTranscriptIfNeeded` and `visibleSpeechText(from:)` logic.

For future debugging, compare raw STT and visible text before changing audio-session timing. If raw starts correctly but visible text is missing the first syllable, the issue is still in baseline/delta display handling.

## Baseline 처리 문제

### 문제 현상

The app needed to avoid showing background STT text accumulated before the user opened the speech UI. A baseline was used for that. However, after TTS, the baseline could be reset to empty, and the first unstable partial could be incorrectly captured as the new baseline.

### 원인 분석

The original baseline logic had a prefix-mismatch path that could store the current raw transcript as the new baseline. This is useful when a long accumulated transcript does not match the expected baseline. It is unsafe when the baseline is empty immediately after a fresh STT restart.

### 실제 로그 근거

```text
[STT] first partial displayed/ignored mode=conversation displayed=true raw=한기대 갈려면 baseline=한 visible=기대 갈려면
```

This proves the raw transcript contained the missing syllable, but `visible` dropped it.

### 해결 방법

The baseline function now explicitly handles an empty baseline first:

- if baseline is empty, display raw transcript
- if baseline is non-empty and raw starts with baseline, display delta
- if raw equals baseline, display nothing
- if raw is shorter than baseline, reset baseline and display raw
- if baseline is non-empty and prefix mismatch occurs, treat it as mismatch and refresh baseline

### 현재 상태

Baseline still exists. Only the empty-baseline case was changed.

### 남은 이슈

If future changes introduce another baseline reset path, verify that it does not convert a 1-2 syllable partial into a subtraction baseline.

## AVAudioSession / STT Restart Timing

### 문제 현상

Early testing suggested that STT was starting too late after TTS and missing the first word.

### 원인 분석

Diagnostic logs were added to distinguish timing loss from UI filtering:

- TTS finish time
- STT restart scheduled delay
- `startRecording` request time
- audio engine actual start time
- first partial received time and text
- first partial displayed/ignored decision

The logs showed that the first partial could arrive with the correct first syllable. That shifted the primary root cause away from capture delay and toward baseline/delta handling.

### 실제 로그 근거

```text
[TTS] didFinish timestamp=...
[STT] restart scheduled delay=0.1 timestamp=... mode=conversation
[STT] startRecording called reason=tts-finished timestamp=...
[STT] audio engine actually started timestamp=... reason=tts-finished deltaFromRequestMs=...
[STT] first partial received timestamp=... reason=tts-finished deltaFromAudioStartMs=... text=한
```

### 해결 방법

The restart delay was not increased. Current value is `ttsSpeechRestartDelay = 0.1`.

The final fix for the first-syllable issue was in transcript display baseline logic, not AVAudioSession.

### 현재 상태

The logging remains useful for regression diagnosis. If future tests show first partial received already starts mid-word, then the problem should be revisited as an audio/STT startup issue.

### 남은 이슈

On-device verification should continue to compare:

- first partial received text
- first partial displayed text

That tells whether a future issue is capture-side or display-side.

## SoundDetector / SpeechManager 오디오 충돌

### 문제 현상

After TTS/STT restart changes, default detection mode could start `SpeechManager` aggressively. `SoundDetector` still logged that the audio engine started, but the regular danger analysis logs disappeared:

```text
SoundDetector startDetection called
[SoundDetector] analyzer request started
[SoundDetector] audio engine started
[SpeechManager] configure audio session for recording
[SpeechManager] audio engine started
```

Expected danger logs such as the following stopped appearing:

```text
🎧 [SoundDetector] top3: ...
```

This meant iPhone-only danger detection could silently stop working even though the detector object looked active.

### 원인 분석

The danger path and speech path both need microphone input. When `SpeechManager` started recording in the default detection state, it could reconfigure the audio session and start its own audio engine, disturbing the SoundDetector stream. The core issue was not the danger classifier itself; it was ownership of the microphone pipeline.

### 실제 로그 근거

The failure pattern was:

```text
[SoundDetector] audio engine started
[SpeechManager] configure audio session for recording
[SpeechManager] audio engine started
```

followed by no ongoing `top3` logs.

The fixed pattern keeps danger analysis alive:

```text
[SoundDetector] analyzer callback alive
🎧 [SoundDetector] top3: speech(...), ...
[SpeechGate] speech detected confidence=...
[SpeechGate] start STT for attention call
```

### 해결 방법

The app now treats `SoundDetector` as the always-on base pipeline in detection mode. STT starts only when:

- the voice UI is active, or
- SoundAnalysis detects speech and opens the speech gate.

Speech gate keeps STT alive only briefly after speech activity, then stops it. TTS also prevents speech-gated STT from starting while the app itself is speaking.

### 현재 상태

Danger detection, speech-gated attention calls, and TTS/STT interaction have been verified together on device. The important presentation result is that danger sound logs remain alive while attention-call detection can still work in the default detection screen.

### 남은 이슈

Speech gate threshold is a practical value for the presentation environment. If the demo space is noisy, tune the threshold carefully and verify that `SoundDetector` top3 logs do not stop.

## BLE Clock Sync 설계

### 문제 현상

Early BLE runs showed danger haptic writes using fallback timestamps even though the ESP32 was receiving `clock_ping` and sending `clock_pong`.

Example fallback log:

```text
📡 [BLEHaptic] write pattern=carHorn, ts=1779285282480, win=975, mode=fallback
```

### 원인 분석

The root issue was not the timestamp formula first. The important failure was the notify receive path:

- iPhone write path worked.
- ESP32 logged `TX clock_pong`.
- iPhone did not log raw notify payload.

This meant `clock_pong` was not being received or processed by iOS. ESP32 can expose write and notify properties separately, so the iOS side had to discover all characteristics and subscribe to notify/indicate paths instead of assuming one write characteristic was enough.

### 실제 로그 근거

ESP32:

```text
[BLE RX] {"type":"clock_ping","ts":1779285240042}
[TX clock_pong] {"type":"clock_pong","phone_ts":1779285240042,"esp_ts":108094}
```

Expected iPhone logs after fix:

```text
📡 [LissenceBLE] setNotifyValue true for characteristic=...
📥 [LissenceBLE] notify raw characteristic=... text={"type":"clock_pong","phone_ts":1779285240042,"esp_ts":108094}
📥 [LissenceBLE] clock_pong received raw=...
⏰ [LissenceBLE] clock sync success: phoneSent=..., espTs=..., rtt=..., offset=...
⏰ [LissenceBLE] precise timestamp enabled
```

### 해결 방법

`LissenceBLEManager` now:

- discovers all characteristics in the service
- chooses write and notify characteristics separately
- subscribes to all notify/indicate characteristics
- logs raw notify data
- robustly parses `clock_pong`
- supports `phone_ts`, pending ping timestamp fallback, and several ESP timestamp key variants

### 현재 상태

Precise clock sync has been confirmed in device testing. `BLEHaptic mode=precise` and ESP32 MATCH-A behavior were observed.

### 남은 이슈

If ESP32 firmware changes its BLE characteristic layout, re-check the discovered characteristic logs and notify subscription logs first.

## Attention Haptic BLE 분리

### 문제 현상

Danger haptic BLE messages already used `ts` and `win` for ESP32 direction matching. Attention calls did not need that path. If attention haptics reused danger `haptic` messages, the hardware would unnecessarily wait for direction matching data and the protocol would become harder to reason about.

### 원인 분석

Danger and attention haptics represent different user experiences:

- danger sound: where did the sound come from?
- attention call: someone is trying to get the user's attention now.

The first needs clock sync and ring-buffer matching. The second needs immediate feedback.

### 실제 로그 근거

Attention haptic writes use a separate log family:

```text
📡 [BLEAttention] write pattern=single
📡 [BLEAttention] write pattern=repeat
📡 [BLEAttention] write pattern=emergency
📡 [BLEAttention] skipped pattern=single reason=sliderOff
```

Danger haptic writes remain separate:

```text
📡 [BLEHaptic] write pattern=carHorn, ts=81636, win=975, mode=precise
```

### 해결 방법

The app added a separate BLE protocol:

```json
{"type":"attention_haptic","pattern":"single"}
{"type":"attention_haptic","pattern":"repeat"}
{"type":"attention_haptic","pattern":"emergency"}
```

The ESP32 handles this without `ts`, `win`, or direction matching and fires both motors immediately. The iOS attention sliders control both iPhone haptics and BLE attention haptics.

### 현재 상태

The presentation wording should be:

- danger haptics use precise BLE and direction matching
- attention haptics use immediate BLE and no direction matching

### 남은 이슈

If adding new attention patterns, do not add them to the danger `haptic` path. Keep protocol separation.

## 호출어 햅틱 UX 개선

### 문제 현상

The first ESP32 attention-call patterns for `single` and `repeat` used weak short pulses. On device they felt like a small "삑" or "삑삑" rather than a clear vibration.

### 원인 분석

The old attention single/repeat pattern had short on-times and lower duty. The motor could audibly tick before producing a strong tactile sensation. Emergency felt correct because it already used a stronger pattern.

### 실제 로그 근거

The iOS side was already sending the correct patterns:

```text
📡 [BLEAttention] write pattern=single
📡 [BLEAttention] write pattern=repeat
📡 [BLEAttention] write pattern=emergency
```

The issue was therefore not BLE mapping; it was the ESP32 pattern definition for `single` and `repeat`.

### 해결 방법

Only `Hardware_HearAlert_2Mic_2Haptic/main.cpp` attention single/repeat pattern definitions were changed:

- `PAT_GENTLE`: `300ms duty 200`, `80ms off`, `120ms duty 200`
- `PAT_ATTENTION_REPEAT`: the same "웅~윙" pattern twice, with a `180ms` gap

The following were intentionally left unchanged:

- `attentionEmergency`
- danger `type="haptic"` path
- BLE protocol
- clock sync
- MATCH-A/B direction matching
- precise/fallback behavior

### 현재 상태

Single and repeated attention calls now have a more tactile "웅~윙" feel, while emergency remains the stronger alert pattern.

### 남은 이슈

If the physical motor or enclosure changes, duty and duration may need a final tactile tuning pass.

## Timestamp(ts) + Window(win) 기반 방향 매칭

### 문제 현상

Without a detection timestamp, the ESP32 would only know when BLE delivered the command. That does not match the actual sound event time because SoundAnalysis classification and BLE delivery are delayed.

### 원인 분석

Direction is estimated continuously on the ESP32 and stored in a ring buffer. The iPhone must send when the sound happened, not when the BLE command is delivered.

### 실제 로그 근거

iPhone:

```text
🎯 [SoundDetector] precise timestamp ms=...
📡 [BLEHaptic] write pattern=carHorn, ts=81636, win=975, mode=precise
```

ESP32:

```text
[RX haptic] {"type":"haptic","pattern":"carHorn","ts":81636,"win":975}
[MATCH-A] win=[...,...] frames=... L=... R=... peak=... -> LEFT
[DANGER] direction = LEFT
```

### 해결 방법

iOS computes `classifiedAt` from the SoundAnalysis result's `timeRange.start`, anchored to the first audio buffer timestamp. It then sends:

```json
{"type":"haptic","pattern":"carHorn","ts":<esp32Millis>,"win":975}
```

ESP32 uses MATCH-A to search around the `ts/win` window and MATCH-B as an event-based safety net.

### 현재 상태

Precise timestamp matching and ESP32 direction motor output have been confirmed in hardware testing.

### 남은 이슈

The ESP32 currently uses a wider MATCH-A search margin internally. If latency and timestamp accuracy remain stable, this could be tuned later, but it is safer to keep for demos.

## 위험음 오탐 감소 로직

### 문제 현상

Raw SoundAnalysis can classify many non-danger sounds, including speech-related labels. If all of these became danger alerts, the demo would create false alarms.

### 원인 분석

The app only needs three presentation danger categories:

- `siren`
- `fireAlarm`
- `carHorn`

Speech-related labels should be used for speech gate, not danger haptic.

### 실제 로그 근거

SoundDetector logs Top-3 for visibility:

```text
🎧 [SoundDetector] top3: speech(72%), conversation(20%), ...
```

But `DangerSound.from(identifier:)` returns nil for:

- `speech`
- `conversation`
- `shouting`
- `screaming`
- `yelling`
- `crying_sobbing`
- `baby_crying`
- `knock`

### 해결 방법

Danger mapping is limited to:

- `siren`, `emergency_vehicle`
- `fire_alarm`, `smoke_detector`
- `car_horn`, `vehicle_horn`

The app uses confidence `> 0.6` for iPhone SoundDetector danger adoption.

### 현재 상태

Danger detection is constrained to the hardware-supported categories. Speech is separately used as an STT gate signal.

### 남은 이슈

If a new danger category is added, it must be added consistently in:

- `DangerSound`
- iPhone haptic policy
- Watch display
- ESP32 haptic pattern lookup
- presentation documentation

## BLE Cooldown 적용 이유

### 문제 현상

SoundAnalysis can emit repeated classifications for the same sound event. Without cooldown, BLE writes could flood ESP32 and retrigger haptics too frequently.

### 원인 분석

The classification callback can fire multiple times while the same siren, fire alarm, or car horn remains audible. Hardware haptics need a user-perceivable signal, not every classifier frame.

### 실제 로그 근거

```text
📡 [BLEHaptic] skip: cooldown pattern=carHorn
```

### 해결 방법

iOS applies `bleWriteCooldownSeconds = 0.8` in `writeHapticPattern`.

This is a global danger BLE cooldown, not a per-pattern cooldown. It prevents danger haptic BLE write storms across all danger categories.

### 현재 상태

Cooldown is active for danger BLE `haptic` writes. Attention haptic uses a separate immediate protocol and is controlled by attention-call slider policy.

### 남은 이슈

If multiple different danger sounds must be represented independently within 0.8 seconds, the cooldown may need to become per-pattern. For the current demo, global cooldown is simpler and safer.

## Precise / Fallback Mode 분리 이유

### 문제 현상

BLE clock sync can fail due to notify subscription issues, ESP32 state, Bluetooth state, or timing. Removing fallback would make hardware haptics fragile.

### 원인 분석

The demo needs best-effort hardware behavior. Precise mode is better for direction matching, but fallback mode keeps the feature usable when sync is not available.

### 실제 로그 근거

Fallback:

```text
⏰ [LissenceBLE] clock_ping timeout -> fallback latency mode
📡 [BLEHaptic] write pattern=carHorn, ts=..., win=975, mode=fallback
```

Precise:

```text
⏰ [LissenceBLE] precise timestamp enabled
📡 [BLEHaptic] write pattern=carHorn, ts=81636, win=975, mode=precise
```

ESP32 status also distinguishes plausible ESP32 millis timestamps from huge iPhone epoch timestamps.

### 해결 방법

iOS keeps both paths:

- precise: use clock offset to convert iPhone `Date` to ESP32 millis
- fallback: subtract estimated BLE latency from iPhone epoch timestamp

ESP32 keeps both matching strategies:

- MATCH-A: timestamp window matching
- MATCH-B: recent loudest event fallback

### 현재 상태

Precise mode is the confirmed happy path. Fallback remains for resilience.

### 남은 이슈

If fallback is frequently used during demo, check notify logs before changing timing constants.
