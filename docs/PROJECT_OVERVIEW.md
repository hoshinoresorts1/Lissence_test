# Lissence Project Overview

## Project Purpose

Lissence is an iOS-based hearing assistance prototype that detects environmental danger sounds, attention calls, and conversation speech, then turns them into visual, haptic, Watch, and ESP32 hardware feedback.

The project is built for a presentation and portfolio context, so the implementation favors reliable end-to-end behavior over experimental architecture. The important design goal is that danger detection must continue working even when secondary features such as speech recognition, TTS, Watch messaging, or BLE hardware are unavailable.

## Core Features

- iPhone danger sound detection for `siren`, `fireAlarm`, and `carHorn`.
- iPhone haptic feedback for danger sounds.
- Apple Watch danger message forwarding.
- ESP32 BLE hardware haptic output with direction matching.
- BLE clock synchronization using `clock_ping` / `clock_pong`.
- Precise BLE timestamp conversion into ESP32 `millis()` coordinates.
- Fallback BLE timestamp mode when clock synchronization fails.
- Attention call detection for "저기요" style calls.
- Three attention-call controls:
  - single call haptic toggle
  - repeated call haptic toggle
  - emergency call haptic toggle
- Conversation and subtitle STT/TTS flow.
- Speech gate that briefly enables STT for attention-call analysis when SoundAnalysis detects speech.
- Final presentation stabilization for TTS/STT transcript baseline, BLE precise sync, speech-gated attention calls, and ESP32 attention haptic patterns.

## Final Presentation Stabilization

After the May 21 feature-complete build, the main work shifted from adding visible features to making the integrated demo reliable in a real presentation environment. The final stabilization focused on four practical failure modes:

1. TTS output could make the next STT transcript appear to lose the first syllable.
2. Always-on STT could interfere with the SoundDetector audio pipeline.
3. BLE danger haptics needed precise ESP32-side timestamp matching, but still needed a fallback if sync failed.
4. Attention-call hardware haptics needed a separate immediate path from danger direction matching.

The final architecture keeps danger detection as the base layer. `SoundDetector` remains active in detection mode, and STT is only activated by voice UI state or by the speech gate. BLE danger haptics use precise timestamp conversion when clock sync succeeds, while attention haptics use simple immediate commands. This makes the demo easier to explain and safer to operate: danger sounds, attention calls, TTS/STT, Watch, and ESP32 feedback can fail or recover independently.

## Main Architecture

The current app separates responsibilities into domain services and the iPhone view model:

- `SoundDetector`
  - Owns the iPhone SoundAnalysis audio engine.
  - Runs continuously in detection mode.
  - Emits danger classifications and speech activity events.

- `SpeechManager`
  - Owns Apple Speech recognition for STT.
  - Used for conversation/subtitle UI and speech-gated attention call detection.
  - Does not own danger detection.

- `TTSManager`
  - Owns AVSpeechSynthesizer output.
  - Stops STT while speaking and lets `DetectionViewModel` restart STT when appropriate.

- `AttentionCallAnalyzer`
  - Converts STT transcript segments into `displayOnly`, `softAlert`, or `strongAlert`.
  - Keeps repeat detection, emergency context, and partial-overlap dedupe isolated from UI behavior.

- `LissenceBLEManager`
  - Owns CoreBluetooth scanning, connection, characteristic discovery, notify subscription, clock sync, and BLE writes.
  - Separates danger haptic messages from attention haptic messages.

- `DetectionViewModel`
  - Coordinates SoundDetector, SpeechManager, TTSManager, BLE, Watch, and UI state.
  - Applies user-facing attention-call slider policy after analyzer output.

This separation exists because danger detection and attention/conversation STT have different reliability requirements. Danger detection must be the stable base layer; STT and TTS are allowed to start/stop around UI and speech conditions without disabling the danger pipeline.

## Technology Stack

- Swift / SwiftUI
- Combine
- AVFoundation
- Apple SoundAnalysis v1
- Speech framework
- CoreBluetooth
- WatchConnectivity
- CoreHaptics / UIKit haptics depending on controller path
- ESP32 BLE peripheral
- ESP32 ring buffer based direction matching
- Two-microphone direction estimation on hardware

## iPhone to ESP32 BLE Structure

The iPhone connects to the ESP32 peripheral using the constants in `LissenceBLEConstants`:

- Device name: `HearAlert`
- Service UUID: `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
- Characteristic UUID: `beb5483e-36e1-4688-b7f5-ea07361b26a8`

The iOS code first scans by Service UUID. If it does not find the board within `serviceScanTimeout = 5s`, it falls back to name-based scanning for `HearAlert`.

The BLE manager discovers all characteristics in the target service and stores write and notify characteristics separately when needed. This matters because the ESP32 may expose write and notify capabilities on separate characteristic instances. The previous failure mode was that writes worked but `clock_pong` notify was never processed. The current implementation logs discovered characteristics, subscribes to all notify/indicate characteristics, and logs raw notify payloads.

## BLE Message Types

### Danger Haptic

Danger sound detection uses:

```json
{"type":"haptic","pattern":"carHorn","ts":123456,"win":975}
```

Patterns:

- `siren`
- `fireAlarm`
- `carHorn`

`ts` is the detected sound time in ESP32 `millis()` coordinates when precise mode is active. `win` is the SoundAnalysis analysis window in milliseconds. Current iOS constant: `analysisWindowSeconds = 0.975`.

This message is used by ESP32 direction matching. It must not be mixed with attention-call haptics.

### Attention Haptic

Attention call haptics use a separate immediate-execution protocol:

```json
{"type":"attention_haptic","pattern":"single"}
{"type":"attention_haptic","pattern":"repeat"}
{"type":"attention_haptic","pattern":"emergency"}
```

These messages do not include `ts` or `win`. They do not use direction matching. The ESP32 fires both motors immediately.

This separation is intentional: danger haptics need direction and timestamp matching, while attention calls are user-facing call notifications without spatial matching.

On the ESP32 side, the final presentation pattern policy is:

- `single`: gentle "웅~윙" pattern, approximately `300ms duty 200`, `80ms off`, `120ms duty 200`.
- `repeat`: the same "웅~윙" pattern twice with a short gap.
- `emergency`: existing strong emergency attention pattern, unchanged.

The single/repeat change was made because the old duty 100 short pulses felt like a short beep rather than a clear vibration. Emergency was left unchanged because it was already strong and recognizable.

### Clock Sync

Clock sync uses:

```json
{"type":"clock_ping","ts":1779285240042}
{"type":"clock_pong","phone_ts":1779285240042,"esp_ts":108094}
```

iOS sends `clock_ping` after BLE connection is ready. ESP32 responds through notify with `clock_pong`. iOS computes an offset from iPhone epoch milliseconds to ESP32 `millis()` milliseconds. When this succeeds, future danger haptic payloads use `mode=precise`.

## SoundAnalysis, Speech, BLE, RingBuffer, and Clock Sync Relationship

The app has two independent audio interpretation paths:

1. SoundAnalysis danger path
   - Always-on in detection mode.
   - Classifies environmental sounds.
   - Sends danger events to iPhone haptic, Watch, and BLE.

2. Speech/STT path
   - Runs when conversation/subtitle UI is active.
   - Also runs briefly through speech gate when SoundAnalysis detects speech in default detection mode.
   - Feeds attention-call analysis.

SoundAnalysis danger classification produces a physical sound timestamp. That timestamp is converted to ESP32 time using BLE clock sync. ESP32 continuously records microphone direction frames into a ring buffer. When a `haptic` message arrives, the ESP32 searches the ring buffer around `ts +/- win` and fires the motor on the matched side.

The reason for this design is latency compensation. Apple SoundAnalysis classification is not instantaneous. If the app sent a haptic command without the detected sound timestamp, ESP32 would only know when BLE delivered the message, not when the sound happened. Passing `ts` lets the hardware match the direction to the original sound event.

## Danger Sound Detection Flow

1. `SoundDetector.startDetection()` configures `.playAndRecord` audio session and starts an `AVAudioEngine`.
2. Microphone buffers are passed to `SNAudioStreamAnalyzer`.
3. `SNClassifySoundRequest(classifierIdentifier: .version1)` produces classifications.
4. Classifications are sorted by confidence.
5. The app logs the Top-3 classifications for debugging.
6. The app iterates the sorted classifications and accepts the first item with confidence `> 0.6` that maps through `DangerSound.from(identifier:)`.
7. `DangerSound.from(identifier:)` only maps the supported danger categories:
   - `siren`, `emergency_vehicle` -> `siren`
   - `fire_alarm`, `smoke_detector` -> `fireAlarm`
   - `car_horn`, `vehicle_horn` -> `carHorn`
8. Speech, shouting, screaming, crying, knock, and conversation labels are intentionally excluded from danger mapping to reduce false positives.
9. The app sends:
   - iPhone danger haptic
   - Watch danger message
   - BLE `haptic` message with `pattern`, `ts`, and `win`

The policy intentionally trades broad coverage for demo reliability. Only three danger categories are accepted because the hardware pattern set and presentation scenario are built around those sounds. Other speech-like labels are not danger alerts; they are used only to decide whether to briefly enable STT for attention-call analysis.

The Top-3 list is for logging and speech gate detection. Danger adoption is not limited to Top-3; it walks the sorted list until confidence falls below threshold.

## Attention Call Detection Flow

Attention calls are based on STT text, not SoundAnalysis labels. SoundAnalysis can detect that speech exists, but it cannot determine whether the person said "저기요".

The current flow:

1. SoundAnalysis detects `speech` with confidence >= `0.50`.
2. `SoundDetector.speechActivity` notifies `DetectionViewModel`.
3. If the voice UI is not active and TTS is not speaking, speech gate starts `SpeechManager`.
4. STT runs for `speechGateHoldDuration = 4.0s` after the latest speech activity.
5. Transcript segments are sent to `AttentionCallAnalyzer`.
6. Analyzer outputs:
   - `displayOnly`: single attention candidate
   - `softAlert`: repeated call within the repeat window
   - `strongAlert`: attention candidate plus emergency keyword context
7. `DetectionViewModel` applies the three slider states:
   - single call: screen always, optional soft haptic + BLE `single`
   - repeated call: screen and popup always, optional soft haptic x2 + BLE `repeat`
   - emergency call: screen and Watch policy remain, optional strong haptic + BLE `emergency`

The analyzer keeps repeat timing separate from emergency context:

- repeat window: `5.0s`
- emergency context window: `3.0s`
- partial overlap dedupe window: `1.0s`

Direct repeated phrases such as `저기요저기요` are counted before partial-overlap dedupe. This preserves fast repeated-call detection while preventing one STT partial progression from creating false repeats.

The speech gate was added because running full conversation STT all the time could disturb the danger detection audio path. The final approach keeps `SoundDetector` always on and only starts STT for a short window when speech confidence is high enough. This keeps the user experience close to the original goal, where attention calls work in default detection mode, without sacrificing danger sound reliability.

## TTS/STT Transcript Stability

Conversation and subtitle modes use TTS and STT together. During final stabilization, a visible first-syllable loss appeared after TTS:

- spoken: `한기대 갈려면...`
- raw STT: `한기대 갈려면...`
- visible text before fix: `기대 갈려면...`

Logs showed this was not primarily an audio capture delay. The first partial such as `한` was received, but it was incorrectly used as the transcript baseline. Later visible text subtracted that baseline and hid the first syllable.

The fix kept the baseline system but changed when it is allowed to affect visible text. Empty or unstable early partials are not treated as subtraction baselines. Baseline still prevents old background STT text from leaking into the voice UI, but the first real user phrase remains visible.

## Precise and Fallback Mode

### Precise Mode

Precise mode is active after successful `clock_ping` / `clock_pong` synchronization. iOS converts a SoundAnalysis `Date` into ESP32 `millis()` coordinates using the computed offset.

Expected logs:

```text
📥 [LissenceBLE] clock_pong received raw=...
⏰ [LissenceBLE] clock sync success: phoneSent=..., espTs=..., rtt=..., offset=...
⏰ [LissenceBLE] precise timestamp enabled
📡 [BLEHaptic] write pattern=carHorn, ts=81636, win=975, mode=precise
```

This is the preferred path because ESP32 can use MATCH-A with the ring buffer.

### Fallback Mode

Fallback mode is used if clock sync fails or times out. iOS keeps BLE functionality alive and sends a timestamp adjusted by `bleEstimatedLatencySeconds = 0.15`.

Expected log:

```text
⏰ [LissenceBLE] clock_ping timeout -> fallback latency mode
📡 [BLEHaptic] write pattern=carHorn, ts=..., win=975, mode=fallback
```

Fallback is intentionally kept because hardware demos should degrade gracefully. BLE failure or clock sync failure must not block iPhone danger haptics or Watch fallback.
