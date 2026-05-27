# Session Handoff

This document is for starting a new Codex session without losing project context.

## Current Branch

Current working branch at the time this document was written:

```text
final-presentation/ble-hardware-final-sync
```

Recent pushed commit before documentation:

```text
e89e6bb Fix post-TTS transcript baseline handling
```

The repository was clean after that push. Later documentation and danger-evaluation helper files may appear as uncommitted changes. Treat them as documentation/evaluation work unless the user asks to commit them.

Final presentation context:

- The May 21 build was the feature-complete baseline.
- Work after that focused on integration stability, not large new features.
- The final demo goal was reliable iPhone + Watch + ESP32 behavior under presentation conditions.
- The main stabilized areas were BLE precise sync, speech-gated attention calls, TTS/STT transcript baseline, attention BLE haptics, and ESP32 attention haptic feel.

## Recent Core Changes

### BLE Hardware Timing

- iOS and ESP32 now use `clock_ping` / `clock_pong` to synchronize iPhone epoch time with ESP32 `millis()`.
- iOS parses `clock_pong` robustly, including `phone_ts` and `esp_ts`.
- iOS can use pending `clock_ping` timestamp if `phone_ts` is missing.
- iOS logs raw notify values so receive-path failures are visible.
- BLE write and notify characteristics are discovered separately.
- When sync succeeds, danger haptic payloads log `mode=precise`.
- If sync fails, fallback latency mode remains active.

### Danger Sound Pipeline

- `SoundDetector` remains the always-on base pipeline in detection mode.
- Apple SoundAnalysis v1 classifies audio.
- Confidence threshold for iPhone danger adoption is `> 0.6`.
- Danger mapping is limited to:
  - `siren`
  - `fireAlarm`
  - `carHorn`
- Speech/shouting/etc. are not danger BLE categories.
- iPhone haptic and Watch send should continue even if BLE is unavailable.

### Attention Call Pipeline

- Attention call detection is STT-based.
- SoundAnalysis speech labels only open a speech gate; they do not identify "저기요".
- Speech gate threshold is currently `0.50`.
- Speech gate keeps STT alive for `4.0s` after latest speech activity.
- Attention repeat window is `5.0s`.
- Emergency context window is `3.0s`.
- Partial overlap dedupe window is `1.0s`.
- Direct repeated phrase detection runs before overlap dedupe so `저기요저기요` still becomes repeated call.

### Attention Call Slider Policy

The three top controls are haptic toggles, not visibility toggles:

- single call ON:
  - screen display
  - iPhone soft haptic once
  - BLE `attention_haptic` pattern `single`
- single call OFF:
  - screen display only
  - no iPhone haptic
  - no BLE attention haptic

- repeated call ON:
  - screen display
  - delayed popup
  - iPhone soft haptic twice
  - BLE `attention_haptic` pattern `repeat`
- repeated call OFF:
  - screen display
  - delayed popup
  - no iPhone haptic
  - no BLE attention haptic

- emergency call ON:
  - screen display
  - iPhone strong haptic
  - BLE `attention_haptic` pattern `emergency`
  - Watch policy remains active
- emergency call OFF:
  - screen display
  - no iPhone haptic
  - no BLE attention haptic
  - Watch policy remains active

### TTS/STT Current State

- TTS duplicate speaking was blocked through source-aware request handling.
- Auto reply TTS is disabled.
- TTS starts by stopping STT.
- After TTS finishes, STT restarts after `0.1s` only if voice UI is active.
- Diagnostic logs exist for:
  - TTS finish timestamp
  - STT restart schedule
  - startRecording reason
  - audio engine started timestamp
  - first partial received
  - first partial displayed/ignored
  - baseline/delta route
- The first-syllable loss was fixed in display baseline handling, not in AVAudioSession timing.
- On-device presentation testing confirmed that examples such as `한기대` and `도서관` keep the first syllable after TTS.

### ESP32 Attention Haptic Current State

The iOS attention BLE protocol is:

```json
{"type":"attention_haptic","pattern":"single"}
{"type":"attention_haptic","pattern":"repeat"}
{"type":"attention_haptic","pattern":"emergency"}
```

The hardware attention haptic policy is:

- `single`: "웅~윙" using `PAT_GENTLE`, duty around `200`
- `repeat`: "웅~윙, 웅~윙" using `PAT_ATTENTION_REPEAT`
- `emergency`: existing strong attention pattern, unchanged

Do not mix this with danger `type="haptic"`. Attention haptics are immediate both-motor haptics and do not use direction matching.

## BLE Protocol Notes

### Danger Haptic: `haptic`

Use only for danger sounds:

```json
{"type":"haptic","pattern":"carHorn","ts":123456,"win":975}
```

Properties:

- uses clock sync when available
- sends `ts` in ESP32 `millis()` coordinates in precise mode
- includes `win`
- triggers ESP32 direction matching
- affected by danger BLE cooldown

Do not use this for attention calls.

### Attention Haptic: `attention_haptic`

Use only for call/attention haptics:

```json
{"type":"attention_haptic","pattern":"single"}
{"type":"attention_haptic","pattern":"repeat"}
{"type":"attention_haptic","pattern":"emergency"}
```

Properties:

- no `ts`
- no `win`
- no clock sync dependency
- no direction matching
- ESP32 fires both motors immediately
- only sent when the corresponding attention slider is ON

### Clock Sync

iOS -> ESP32:

```json
{"type":"clock_ping","ts":1779285240042}
```

ESP32 -> iOS notify:

```json
{"type":"clock_pong","phone_ts":1779285240042,"esp_ts":108094}
```

Expected iOS success logs:

```text
📥 [LissenceBLE] clock_pong received raw=...
⏰ [LissenceBLE] clock sync success: phoneSent=..., espTs=..., rtt=..., offset=...
⏰ [LissenceBLE] precise timestamp enabled
```

Expected danger write log after sync:

```text
📡 [BLEHaptic] write pattern=carHorn, ts=81636, win=975, mode=precise
```

## Danger Category Policy

The app intentionally restricts danger BLE categories to three:

- `siren`
- `fireAlarm`
- `carHorn`

The `DangerSound` enum still contains other cases such as `speech`, `shouting`, and `knock`, but those are not mapped from SoundAnalysis for danger BLE. This reduces false positives and keeps ESP32 haptic patterns aligned with the presentation.

If adding a new category, update all of these:

- `DangerSound.from(identifier:)`
- `DangerSound.hapticPattern`
- iPhone danger UI and haptic
- Watch message handling
- ESP32 `lookupPattern`
- documentation and presentation slides

## Speech Gate Behavior

Speech gate exists because running conversation STT continuously together with SoundDetector caused audio-session/audio-engine conflict risk.

Current policy:

- SoundDetector always stays on in detection mode.
- SoundDetector emits `speechActivity` when Top-3 includes a speech-like identifier with confidence >= `0.50`.
- If voice UI is inactive and TTS is not speaking, DetectionViewModel starts SpeechManager for attention-call STT.
- If more speech is detected, the STT window is extended.
- If no speech activity occurs for `4.0s`, speech-gated STT stops.
- If voice UI is active, conversation/subtitle STT takes priority.

Important logs:

```text
[SpeechGate] speech detected confidence=...
[SpeechGate] start STT for attention call
[SpeechGate] extend STT window
[SpeechGate] stop STT after timeout
[SpeechManager] startRecording called reason=speechGate
```

## TTS/STT Notes

The most recent TTS/STT bug was not a capture delay. Logs showed STT received the first syllable, but UI baseline subtraction hid it.

Bad pattern:

```text
raw=한기대 갈려면
baseline=한
visible=기대 갈려면
```

Fix behavior:

```text
[STT] baseline empty -> display raw=한
raw=한기대 갈려면
baseline=<empty>
visible=한기대 갈려면
```

Do not remove baseline entirely. It prevents background STT text from appearing when opening the voice UI.

## Build and Test Results

Recent verification completed before this documentation:

- `git diff --check`: passed
- iOS generic build: passed
- Watch build: passed
- BLE precise sync: confirmed on device
- ESP32 MATCH-A direction matching: confirmed on device
- danger detection for `carHorn`, `siren`, `fireAlarm`: confirmed on device
- attention BLE `single`, `repeat`, `emergency`: confirmed on device
- speech gate after danger detection stabilization: confirmed with SoundDetector logs alive
- TTS after first-syllable baseline fix: confirmed with first syllable retained

Watch build note:

- `Lissence` scheme with `generic/platform=watchOS` did not match a destination.
- Building the `Watch Watch App` scheme with `generic/platform=watchOS` succeeded.

Representative command:

```bash
xcodebuild -project Lissence/Lissence.xcodeproj -scheme "Watch Watch App" -destination generic/platform=watchOS -derivedDataPath /tmp/LissenceWatchDerivedData build
```

## Known Unresolved or Watch Items

- Keep a short real-device regression pass before any public demo. The feature set is stable, but audio/BLE behavior is environment-sensitive.
- Speech gate threshold `0.50` is a practical presentation value; if it opens too often in noisy environments, tune carefully.
- Global BLE danger cooldown `0.8s` is simple and stable, but it can suppress different danger sounds that occur within the cooldown window.
- ESP32 MATCH-A uses a wide factor internally for robustness. It can be tuned later, but keep it for presentation stability.
- Documentation created in this task should be committed separately if accepted.

## Recommended Next Work Priority

1. Run a short final real-device regression pass:
   - danger sound detection
   - BLE precise mode
   - ESP32 direction matching
   - attention call single/repeat/emergency
   - TTS -> STT in conversation and subtitle mode

2. Update Notion portfolio page using these docs:
   - architecture diagram
   - problem-solving timeline
   - before/after logs
   - role and technical decisions

3. Reduce debug log volume only after presentation rehearsal is stable. Logs are currently useful for diagnosis.

4. If creating presentation slides, use the exact protocol wording from `PROJECT_OVERVIEW.md` and the failure analysis from `TROUBLESHOOTING.md`.
