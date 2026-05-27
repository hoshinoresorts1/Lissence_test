# Architecture Notes

This document summarizes the final presentation architecture. It focuses on why the system is split this way, not only what each file does.

## Design Goal

Lissence converts important sound events into visual, tactile, Watch, and ESP32 hardware feedback for hearing-impaired users.

The final architecture prioritizes one rule:

> danger detection must remain alive even when speech recognition, TTS, BLE sync, or Watch delivery is unstable.

This rule shaped the final design. Danger sound detection is the base layer. Speech recognition, TTS, attention-call analysis, Watch delivery, and BLE hardware output are coordinated around it instead of replacing it.

## Main Runtime Layers

## 1. Danger Detection Layer

Owner: `SoundDetector`

Role:

- keeps the iPhone microphone analysis running in detection mode
- uses Apple SoundAnalysis v1
- logs Top-3 classifications
- accepts only supported danger categories
- forwards danger events to iPhone haptic, Watch, and BLE

Supported final danger categories:

- `siren`
- `fireAlarm`
- `carHorn`

Why this is limited:

The presentation hardware and haptic patterns are built around these three sounds. Limiting the mapping reduces false positives from speech, shouting, knocking, and other non-demo labels.

## 2. BLE Hardware Layer

Owner: `LissenceBLEManager`

The BLE layer has two separate message families.

### Danger Haptic

```json
{"type":"haptic","pattern":"carHorn","ts":123456,"win":975}
```

Used for:

- danger sound haptic
- ESP32 ring-buffer direction matching
- precise timestamp mode when clock sync succeeds
- fallback latency mode when sync fails

Why `ts` and `win` exist:

SoundAnalysis classification arrives after the real sound. The ESP32 continuously stores direction frames in a ring buffer. Sending the original detected sound time lets ESP32 match the motor direction to when the sound actually happened, not when BLE delivered the command.

### Attention Haptic

```json
{"type":"attention_haptic","pattern":"single"}
{"type":"attention_haptic","pattern":"repeat"}
{"type":"attention_haptic","pattern":"emergency"}
```

Used for:

- "저기요" single call
- repeated "저기요" call
- emergency attention call such as "저기요 조심하세요"

Why this is separate:

Attention calls do not need direction matching. The correct behavior is immediate both-motor feedback, controlled by the attention haptic sliders. Separating the protocol prevents attention calls from depending on clock sync or ring-buffer matching.

## 3. Clock Sync Layer

Protocol:

```json
{"type":"clock_ping","ts":1779285240042}
{"type":"clock_pong","phone_ts":1779285240042,"esp_ts":108094}
```

When sync succeeds:

- iOS converts iPhone epoch time into ESP32 `millis()` time
- danger haptic writes log `mode=precise`
- ESP32 uses MATCH-A timestamp window matching

When sync fails:

- iOS keeps fallback latency mode
- iPhone danger haptic and Watch delivery continue
- BLE hardware still receives best-effort timestamps

Why fallback remains:

Presentation hardware can fail due to Bluetooth state, notify subscription, or timing. A graceful fallback is safer than making hardware haptics depend entirely on perfect clock sync.

## 4. Speech and Attention Layer

Owners:

- `SpeechManager`
- `AttentionCallAnalyzer`
- `DetectionViewModel`

The final design does not keep full STT always running in default detection mode. That caused audio-session conflict risk with `SoundDetector`.

Instead:

1. `SoundDetector` remains always on.
2. SoundAnalysis detects speech-like audio.
3. If speech confidence passes the threshold, `DetectionViewModel` briefly starts STT through speech gate.
4. STT transcript is passed to `AttentionCallAnalyzer`.
5. The analyzer decides `displayOnly`, `softAlert`, or `strongAlert`.
6. `DetectionViewModel` applies the user-facing slider policy.

Why speech gate exists:

SoundAnalysis can tell that someone is speaking, but it cannot know whether the person said "저기요". STT is still needed for the keyword. Speech gate keeps STT available only when speech is likely, reducing the chance that SpeechManager disrupts danger detection.

## 5. TTS/STT Conversation Layer

Owners:

- `TTSManager`
- `SpeechManager`
- `DetectionViewModel`

TTS temporarily stops STT to avoid the app recognizing its own voice output. After TTS finishes, STT restarts when the voice UI still needs it.

The final first-syllable fix was not an audio-session timing change. Logs proved raw STT received the first syllable. The visible text lost it because a very short first partial was treated as the baseline and subtracted from later text.

Final policy:

- keep baseline to prevent old background transcript from appearing
- do not use unstable first partials as a subtraction baseline
- display raw transcript when baseline is empty

## Final Presentation Integration

The final system was validated as an integrated iPhone + Watch + ESP32 flow:

- iPhone SoundAnalysis danger detection
- Watch danger forwarding
- BLE precise sync
- ESP32 MATCH-A direction matching
- BLE fallback mode safety
- speech-gated attention calls
- attention BLE haptic patterns
- TTS/STT first-syllable preservation

The main technical tradeoff is that the app favors stable demo behavior over maximum classifier coverage. It accepts fewer danger categories, uses fallback modes, keeps logs, and separates danger/attention BLE protocols so each feature can recover independently.
