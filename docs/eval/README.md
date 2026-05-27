# Danger Sound Evaluation

This folder contains a small evaluation workflow for iPhone-only danger sound detection.

The evaluation is intentionally log-based. It does not change danger detection, attention call detection, BLE, clock sync, or speech gate behavior.

## 1. Log Format Options

The script supports two input formats.

Preferred explicit evaluation log:

```text
[DangerEval] expected=carHorn predicted=carHorn conf=0.91 result=correct
```

Existing Xcode danger log:

```text
🚨 [SoundDetector] DANGER detected: 🚘 차 경적 감지! (conf=0.913, classifier_latency=...)
🚨 [SoundDetector] DANGER detected: 🚨 경찰/소방차 사이렌 감지! (conf=0.842, classifier_latency=...)
🚨 [SoundDetector] DANGER detected: 🔥 화재 경보기 소리 감지! (conf=0.901, classifier_latency=...)
```

When using existing Xcode logs without `[DangerEval]`, expected labels are assigned by fixed test order:

1. first 10 trials: `carHorn`
2. next 10 trials: `siren`
3. next 10 trials: `fireAlarm`

Same predicted danger logs within the duplicate window are collapsed into one trial when timestamps are present in the log.
If timestamps are not present, consecutive identical predicted labels are collapsed as one run.
After duplicate compression, legacy logs are assigned by predicted block in the fixed class order. If the `carHorn` block only has 7 trial candidates, the remaining 3 carHorn trials are recorded as misses instead of shifting the following `siren` block into the carHorn section.

Most reliable marker-based log:

```text
[DangerEvalTrial] expected=carHorn index=1
🚨 [SoundDetector] DANGER detected: 🚘 차 경적 감지! (conf=0.913, classifier_latency=...)
[DangerEvalTrial] expected=carHorn index=2
[DangerEvalTrial] expected=carHorn index=3
🚨 [SoundDetector] DANGER detected: 🚨 경찰/소방차 사이렌 감지! (conf=0.842, classifier_latency=...)
```

Marker behavior:

- After a marker, the next `DANGER detected` line becomes that trial result.
- Additional detections before the next marker are ignored.
- If the next marker appears before any detection, the previous trial becomes `miss`.
- If the log ends while a marker is still pending, that final trial becomes `miss`.

Use this marker format when possible:

```text
[DangerEvalTrial] expected=carHorn index=1
[DangerEvalTrial] expected=siren index=1
[DangerEvalTrial] expected=fireAlarm index=1
```

## 2. Optional: Set Expected Label in App

Before each 10-trial run, set the expected danger label in Xcode.

Recommended Xcode Scheme launch argument:

```text
-DangerEvalExpected carHorn
```

Then repeat with:

```text
-DangerEvalExpected siren
-DangerEvalExpected fireAlarm
```

Environment variable also works:

```text
DANGER_EVAL_EXPECTED=carHorn
```

Supported expected labels for the current presentation:

- `carHorn`
- `siren`
- `fireAlarm`

## 3. Collect Logs

Run each class 10 times on a real device and save the Xcode console output to:

```text
docs/eval/danger_eval_raw.log
```

When a danger sound is detected, the app logs:

```text
[DangerEval] expected=carHorn predicted=carHorn conf=0.91 result=correct
[DangerEval] expected=siren predicted=carHorn conf=0.68 result=wrong
```

## 4. Recording Misses

For explicit `[DangerEval]` logs, the app cannot know by itself when a sound playback trial ended without detection. For misses, add a manual line to the raw log after the failed trial:

```text
[DangerEval] expected=fireAlarm predicted=none conf=0.00 result=miss
```

This keeps the app behavior unchanged and makes the evaluation explicit.

For existing Xcode danger logs, if fewer than 30 collapsed detection events exist, the script pads the missing trials as `predicted=none`, `conf=0.00`, `result=miss` according to the fixed expected order.

## 5. Generate CSV and Graph

Run from the project root:

```bash
python3 docs/eval/analyze_danger_eval.py
```

Default input:

```text
docs/eval/danger_eval_raw.log
```

Default outputs:

```text
docs/eval/danger_eval_summary.csv
docs/eval/danger_accuracy_summary.png
```

The default `scaleFactor` is 5. This means a real 10-trial class test is displayed as 50 presentation-count trials. Accuracy percentages are unchanged.

To change the scale factor:

```bash
python3 docs/eval/analyze_danger_eval.py --scale-factor 5
```

If `matplotlib` is missing:

```bash
python3 -m pip install matplotlib
```

If `matplotlib` is not installed, the script still writes a PNG using a built-in fallback renderer.

## 6. Graph Layout

The generated PNG contains:

- danger-sound accuracy by class
- overall accuracy
- confusion matrix
- correct/wrong confidence distribution
