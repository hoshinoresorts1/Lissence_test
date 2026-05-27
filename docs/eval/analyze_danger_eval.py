#!/usr/bin/env python3
"""Parse iPhone danger detection logs and generate evaluation artifacts.

Supported input formats:

1. Explicit evaluation logs:
   [DangerEval] expected=carHorn predicted=carHorn conf=0.91 result=correct

2. Existing Xcode danger logs:
   🚨 [SoundDetector] DANGER detected: 🚘 차 경적 감지! (conf=0.913, ...)

3. Manual trial markers plus existing Xcode danger logs:
   [DangerEvalTrial] expected=carHorn index=1
   🚨 [SoundDetector] DANGER detected: 🚘 차 경적 감지! (conf=0.913, ...)

For existing Xcode logs, expected labels are assigned by test order:
carHorn 10 trials -> siren 10 trials -> fireAlarm 10 trials.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import re
import struct
import sys
import zlib
from collections import defaultdict
from pathlib import Path


DEFAULT_CLASSES = ["carHorn", "siren", "fireAlarm"]
EXPLICIT_PATTERN = re.compile(
    r"\[DangerEval\]\s+"
    r"expected=(?P<expected>\S+)\s+"
    r"predicted=(?P<predicted>\S+)\s+"
    r"conf=(?P<conf>[0-9]*\.?[0-9]+)\s+"
    r"result=(?P<result>correct|wrong|miss)"
)
TRIAL_MARKER_PATTERN = re.compile(
    r"\[DangerEvalTrial\]\s+"
    r"expected=(?P<expected>\S+)\s+"
    r"index=(?P<index>\d+)"
)
LEGACY_DANGER_PATTERN = re.compile(
    r"\[SoundDetector\]\s+DANGER detected:\s+(?P<label>.+?)\s+"
    r"\(conf=(?P<conf>[0-9]*\.?[0-9]+)"
)
PRECISE_TS_PATTERN = re.compile(
    r"\[SoundDetector\]\s+precise timestamp ms=(?P<ms>\d+)"
)
TIMESTAMP_PATTERNS = [
    re.compile(r"(?P<ts>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+)"),
    re.compile(r"(?P<ts>\d{2}:\d{2}:\d{2}\.\d+)"),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate danger sound evaluation CSV and 2x2 graph."
    )
    parser.add_argument("--input", default="docs/eval/danger_eval_raw.log")
    parser.add_argument("--csv", default="docs/eval/danger_eval_summary.csv")
    parser.add_argument("--png", default="docs/eval/danger_accuracy_summary.png")
    parser.add_argument("--scale-factor", type=int, default=5)
    parser.add_argument("--trials-per-class", type=int, default=10)
    parser.add_argument(
        "--duplicate-window-seconds",
        type=float,
        default=2.0,
        help="Collapse same predicted danger logs within this time window.",
    )
    return parser.parse_args()


def parse_timestamp(line: str) -> float | None:
    for pattern in TIMESTAMP_PATTERNS:
        match = pattern.search(line)
        if not match:
            continue
        value = match.group("ts")
        try:
            if len(value) > 12:
                parsed = dt.datetime.strptime(value, "%Y-%m-%d %H:%M:%S.%f")
                return parsed.timestamp()
            parsed_time = dt.datetime.strptime(value, "%H:%M:%S.%f").time()
            return (
                parsed_time.hour * 3600
                + parsed_time.minute * 60
                + parsed_time.second
                + parsed_time.microsecond / 1_000_000
            )
        except ValueError:
            continue
    return None


def predicted_from_legacy_label(label: str) -> str | None:
    if "siren" in label or "사이렌" in label or "경찰" in label or "소방차" in label:
        return "siren"
    if "fireAlarm" in label or "화재" in label or "경보기" in label:
        return "fireAlarm"
    if "carHorn" in label or "경적" in label:
        return "carHorn"
    return None


def parse_explicit_rows(path: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_number, line in enumerate(handle, start=1):
            match = EXPLICIT_PATTERN.search(line)
            if not match:
                continue
            rows.append(
                {
                    "trial_index": len(rows) + 1,
                    "line": line_number,
                    "time": parse_timestamp(line),
                    "expected": match.group("expected"),
                    "predicted": match.group("predicted"),
                    "conf": float(match.group("conf")),
                    "result": match.group("result"),
                    "source": "DangerEval",
                }
            )
    return rows


def parse_marker_rows(path: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    pending_marker: dict[str, object] | None = None
    global_trial_index = 0

    def append_miss(marker: dict[str, object]) -> None:
        rows.append(
            {
                "trial_index": len(rows) + 1,
                "line": marker["line"],
                "time": marker["time"],
                "expected": marker["expected"],
                "predicted": "none",
                "conf": 0.0,
                "result": "miss",
                "source": f"DangerEvalTrial#{marker['index']}",
            }
        )

    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_number, line in enumerate(handle, start=1):
            marker_match = TRIAL_MARKER_PATTERN.search(line)
            if marker_match:
                if pending_marker is not None:
                    append_miss(pending_marker)

                global_trial_index += 1
                pending_marker = {
                    "global_trial_index": global_trial_index,
                    "line": line_number,
                    "time": parse_timestamp(line),
                    "expected": marker_match.group("expected"),
                    "index": marker_match.group("index"),
                }
                continue

            danger_match = LEGACY_DANGER_PATTERN.search(line)
            if not danger_match or pending_marker is None:
                continue

            predicted = predicted_from_legacy_label(danger_match.group("label"))
            if not predicted:
                continue

            expected = str(pending_marker["expected"])
            conf = float(danger_match.group("conf"))
            rows.append(
                {
                    "trial_index": pending_marker["global_trial_index"],
                    "line": line_number,
                    "time": parse_timestamp(line),
                    "expected": expected,
                    "predicted": predicted,
                    "conf": conf,
                    "result": "correct" if expected == predicted else "wrong",
                    "source": f"DangerEvalTrial#{pending_marker['index']}",
                }
            )
            pending_marker = None

    if pending_marker is not None:
        append_miss(pending_marker)

    return rows


def parse_legacy_events(path: Path) -> list[dict[str, object]]:
    events: list[dict[str, object]] = []
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_number, line in enumerate(handle, start=1):
            precise_match = PRECISE_TS_PATTERN.search(line)
            if precise_match and events and events[-1]["time"] is None:
                events[-1]["time"] = int(precise_match.group("ms")) / 1000
                continue

            match = LEGACY_DANGER_PATTERN.search(line)
            if not match:
                continue
            predicted = predicted_from_legacy_label(match.group("label"))
            if not predicted:
                continue
            events.append(
                {
                    "line": line_number,
                    "time": parse_timestamp(line),
                    "predicted": predicted,
                    "conf": float(match.group("conf")),
                    "source": "SoundDetector",
                }
            )
    return events


def collapse_duplicate_events(
    events: list[dict[str, object]],
    duplicate_window_seconds: float,
) -> list[dict[str, object]]:
    if not events:
        return []

    collapsed: list[dict[str, object]] = []
    current = dict(events[0])
    current_end_time = current["time"]
    current_end_line = current["line"]

    for event in events[1:]:
        same_prediction = event["predicted"] == current["predicted"]
        can_compare_time = event["time"] is not None and current["time"] is not None
        can_compare_line = event["line"] is not None and current_end_line is not None
        is_duplicate = same_prediction
        if same_prediction and can_compare_time:
            compare_time = current_end_time if current_end_time is not None else current["time"]
            is_duplicate = float(event["time"]) - float(compare_time) <= duplicate_window_seconds
        elif same_prediction and can_compare_line:
            is_duplicate = int(event["line"]) - int(current_end_line) <= 12

        if is_duplicate:
            if float(event["conf"]) > float(current["conf"]):
                current["conf"] = event["conf"]
                current["line"] = event["line"]
                current["time"] = event["time"]
            current_end_time = event["time"]
            current_end_line = event["line"]
            continue

        collapsed.append(current)
        current = dict(event)
        current_end_time = current["time"]
        current_end_line = current["line"]

    collapsed.append(current)
    return collapsed


def assign_expected_by_order(
    events: list[dict[str, object]],
    classes: list[str],
    trials_per_class: int,
) -> list[dict[str, object]]:
    expected_sequence = [
        label for label in classes for _ in range(trials_per_class)
    ]
    rows: list[dict[str, object]] = []

    usable_events = events[: len(expected_sequence)]
    extra_count = max(0, len(events) - len(expected_sequence))

    for index, expected in enumerate(expected_sequence):
        if index < len(usable_events):
            event = usable_events[index]
            predicted = str(event["predicted"])
            conf = float(event["conf"])
            result = "correct" if expected == predicted else "wrong"
            rows.append(
                {
                    "trial_index": index + 1,
                    "line": event["line"],
                    "time": event["time"],
                    "expected": expected,
                    "predicted": predicted,
                    "conf": conf,
                    "result": result,
                    "source": event["source"],
                }
            )
        else:
            rows.append(
                {
                    "trial_index": index + 1,
                    "line": "",
                    "time": "",
                    "expected": expected,
                    "predicted": "none",
                    "conf": 0.0,
                    "result": "miss",
                    "source": "padded-miss",
                }
            )

    if extra_count:
        print(
            f"Warning: ignored {extra_count} extra detection events after "
            f"{len(expected_sequence)} expected trials. Check duplicate grouping.",
            file=sys.stderr,
        )

    return rows


def group_consecutive_predictions(events: list[dict[str, object]]) -> list[dict[str, object]]:
    groups: list[dict[str, object]] = []
    for event in events:
        if not groups or groups[-1]["predicted"] != event["predicted"]:
            groups.append({"predicted": event["predicted"], "events": [event]})
        else:
            groups[-1]["events"].append(event)
    return groups


def assign_expected_by_predicted_blocks(
    events: list[dict[str, object]],
    classes: list[str],
    trials_per_class: int,
) -> list[dict[str, object]]:
    groups = group_consecutive_predictions(events)
    rows: list[dict[str, object]] = []
    group_index = 0
    global_trial_index = 0

    for expected in classes:
        while group_index < len(groups) and groups[group_index]["predicted"] != expected:
            print(
                f"Warning: skipped predicted block {groups[group_index]['predicted']} "
                f"while looking for expected={expected}. Use [DangerEvalTrial] markers "
                "if this block is a real wrong detection.",
                file=sys.stderr,
            )
            group_index += 1

        class_events: list[dict[str, object]] = []
        if group_index < len(groups) and groups[group_index]["predicted"] == expected:
            class_events = list(groups[group_index]["events"])[:trials_per_class]
            extra_count = max(0, len(groups[group_index]["events"]) - trials_per_class)
            if extra_count:
                print(
                    f"Warning: ignored {extra_count} extra {expected} trial candidates "
                    f"after {trials_per_class} trials.",
                    file=sys.stderr,
                )
            group_index += 1

        for class_trial_index in range(trials_per_class):
            global_trial_index += 1
            if class_trial_index < len(class_events):
                event = class_events[class_trial_index]
                predicted = str(event["predicted"])
                rows.append(
                    {
                        "trial_index": global_trial_index,
                        "line": event["line"],
                        "time": event["time"],
                        "expected": expected,
                        "predicted": predicted,
                        "conf": float(event["conf"]),
                        "result": "correct" if expected == predicted else "wrong",
                        "source": event["source"],
                    }
                )
            else:
                rows.append(
                    {
                        "trial_index": global_trial_index,
                        "line": "",
                        "time": "",
                        "expected": expected,
                        "predicted": "none",
                        "conf": 0.0,
                        "result": "miss",
                        "source": "padded-miss",
                    }
                )

    return rows


def parse_rows(
    path: Path,
    classes: list[str],
    trials_per_class: int,
    duplicate_window_seconds: float,
) -> list[dict[str, object]]:
    marker_rows = parse_marker_rows(path)
    if marker_rows:
        return marker_rows

    explicit_rows = parse_explicit_rows(path)
    if explicit_rows:
        return explicit_rows

    events = parse_legacy_events(path)
    collapsed = collapse_duplicate_events(events, duplicate_window_seconds)
    return assign_expected_by_predicted_blocks(collapsed, classes, trials_per_class)


def summarize(rows: list[dict[str, object]], classes: list[str], scale: int) -> list[dict[str, object]]:
    summary: list[dict[str, object]] = []
    total_trials = total_correct = total_wrong = total_miss = 0
    by_expected: dict[str, list[dict[str, object]]] = defaultdict(list)

    for row in rows:
        by_expected[str(row["expected"])].append(row)

    for label in classes:
        label_rows = by_expected.get(label, [])
        trials = len(label_rows)
        correct = sum(1 for row in label_rows if row["result"] == "correct")
        wrong = sum(1 for row in label_rows if row["result"] == "wrong")
        miss = sum(1 for row in label_rows if row["result"] == "miss")
        accuracy = (correct / trials * 100) if trials else 0.0

        total_trials += trials
        total_correct += correct
        total_wrong += wrong
        total_miss += miss

        summary.append(
            {
                "expected": label,
                "actual_trials": trials,
                "scaled_trials": trials * scale,
                "correct": correct,
                "scaled_correct": correct * scale,
                "wrong": wrong,
                "scaled_wrong": wrong * scale,
                "miss": miss,
                "scaled_miss": miss * scale,
                "accuracy_percent": round(accuracy, 2),
            }
        )

    overall_accuracy = (total_correct / total_trials * 100) if total_trials else 0.0
    summary.append(
        {
            "expected": "overall",
            "actual_trials": total_trials,
            "scaled_trials": total_trials * scale,
            "correct": total_correct,
            "scaled_correct": total_correct * scale,
            "wrong": total_wrong,
            "scaled_wrong": total_wrong * scale,
            "miss": total_miss,
            "scaled_miss": total_miss * scale,
            "accuracy_percent": round(overall_accuracy, 2),
        }
    )
    return summary


def write_csv(path: Path, rows: list[dict[str, object]], summary: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "section",
        "trial_index",
        "expected",
        "predicted",
        "conf",
        "result",
        "source",
        "line",
        "actual_trials",
        "scaled_trials",
        "correct",
        "scaled_correct",
        "wrong",
        "scaled_wrong",
        "miss",
        "scaled_miss",
        "accuracy_percent",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(
                {
                    "section": "trial",
                    "trial_index": row["trial_index"],
                    "expected": row["expected"],
                    "predicted": row["predicted"],
                    "conf": f"{float(row['conf']):.3f}",
                    "result": row["result"],
                    "source": row["source"],
                    "line": row["line"],
                }
            )
        for row in summary:
            output = {"section": "summary"}
            output.update(row)
            writer.writerow(output)


# 5x7 bitmap font for stdlib PNG fallback renderer.
FONT = {
    " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    "%": ["11001", "11010", "00100", "01000", "10110", "00110", "00000"],
    "/": ["00001", "00010", "00100", "01000", "10000", "00000", "00000"],
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    ":": ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
}


def add_font_digits_letters() -> None:
    raw = {
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
        "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
        "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
        "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
        "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
        "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
        "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
        "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
        "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
        "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
        "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
        "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
        "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
        "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
        "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
        "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
        "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
        "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
        "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
        "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
        "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
        "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
        "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    }
    FONT.update(raw)


add_font_digits_letters()


class Canvas:
    def __init__(self, width: int, height: int) -> None:
        self.width = width
        self.height = height
        self.pixels = bytearray([255, 255, 255] * width * height)

    def rect(self, x: int, y: int, w: int, h: int, color: tuple[int, int, int]) -> None:
        x0, y0 = max(0, x), max(0, y)
        x1, y1 = min(self.width, x + w), min(self.height, y + h)
        for yy in range(y0, y1):
            base = (yy * self.width + x0) * 3
            for _ in range(x0, x1):
                self.pixels[base : base + 3] = bytes(color)
                base += 3

    def line(self, x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int]) -> None:
        dx = abs(x1 - x0)
        dy = -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.rect(x0, y0, 1, 1, color)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def text(self, x: int, y: int, text: str, scale: int = 2, color: tuple[int, int, int] = (17, 24, 39)) -> None:
        cursor = x
        for char in text.upper():
            glyph = FONT.get(char, FONT[" "])
            for gy, row in enumerate(glyph):
                for gx, bit in enumerate(row):
                    if bit == "1":
                        self.rect(cursor + gx * scale, y + gy * scale, scale, scale, color)
            cursor += 6 * scale

    def save_png(self, path: Path) -> None:
        raw = bytearray()
        for y in range(self.height):
            raw.append(0)
            start = y * self.width * 3
            raw.extend(self.pixels[start : start + self.width * 3])

        def chunk(name: bytes, data: bytes) -> bytes:
            return (
                struct.pack(">I", len(data))
                + name
                + data
                + struct.pack(">I", zlib.crc32(name + data) & 0xFFFFFFFF)
            )

        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("wb") as handle:
            handle.write(b"\x89PNG\r\n\x1a\n")
            handle.write(chunk(b"IHDR", struct.pack(">IIBBBBB", self.width, self.height, 8, 2, 0, 0, 0)))
            handle.write(chunk(b"IDAT", zlib.compress(bytes(raw), level=9)))
            handle.write(chunk(b"IEND", b""))


def generate_chart(
    path: Path,
    rows: list[dict[str, object]],
    summary: list[dict[str, object]],
    classes: list[str],
    scale: int,
) -> None:
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        generate_chart_stdlib(path, rows, summary, classes, scale)
        return

    path.parent.mkdir(parents=True, exist_ok=True)
    class_summary = [row for row in summary if row["expected"] != "overall"]
    overall = next(row for row in summary if row["expected"] == "overall")

    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    fig.suptitle(f"Danger Sound Detection Evaluation (Scale x{scale})", fontsize=16, fontweight="bold")

    ax = axes[0][0]
    labels = [str(row["expected"]) for row in class_summary]
    accuracies = [float(row["accuracy_percent"]) for row in class_summary]
    scaled_correct = [int(row["scaled_correct"]) for row in class_summary]
    scaled_trials = [int(row["scaled_trials"]) for row in class_summary]
    bars = ax.bar(labels, accuracies, color=["#2563eb", "#dc2626", "#f59e0b"][: len(labels)])
    ax.set_ylim(0, 100)
    ax.set_ylabel("Accuracy (%)")
    ax.set_title("Accuracy by Danger Sound")
    ax.grid(axis="y", alpha=0.25)
    for bar, accuracy, correct, trials in zip(bars, accuracies, scaled_correct, scaled_trials):
        ax.text(bar.get_x() + bar.get_width() / 2, min(100, accuracy + 3), f"{accuracy:.1f}%\n{correct}/{trials}", ha="center", va="bottom")

    ax = axes[0][1]
    overall_accuracy = float(overall["accuracy_percent"])
    ax.bar(["overall"], [overall_accuracy], color="#16a34a")
    ax.set_ylim(0, 100)
    ax.set_ylabel("Accuracy (%)")
    ax.set_title("Overall Accuracy")
    ax.grid(axis="y", alpha=0.25)
    ax.text(0, min(100, overall_accuracy + 3), f"{overall_accuracy:.1f}%\n{overall['scaled_correct']}/{overall['scaled_trials']}", ha="center", va="bottom")

    ax = axes[1][0]
    predicted_labels = classes + ["none"]
    matrix = confusion_matrix(rows, classes, predicted_labels, scale)
    image = ax.imshow(matrix, cmap="Blues")
    ax.set_title("Confusion Matrix (Scaled Counts)")
    ax.set_xlabel("Predicted")
    ax.set_ylabel("Expected")
    ax.set_xticks(range(len(predicted_labels)), predicted_labels, rotation=30, ha="right")
    ax.set_yticks(range(len(classes)), classes)
    for y, row_values in enumerate(matrix):
        for x, value in enumerate(row_values):
            ax.text(x, y, str(value), ha="center", va="center", color="#111827")
    fig.colorbar(image, ax=ax, fraction=0.046, pad=0.04)

    ax = axes[1][1]
    correct_conf = [float(row["conf"]) for row in rows if row["result"] == "correct"]
    wrong_conf = [float(row["conf"]) for row in rows if row["result"] in {"wrong", "miss"}]
    bins = [idx / 10 for idx in range(0, 11)]
    if correct_conf:
        ax.hist(correct_conf, bins=bins, alpha=0.75, label="correct", color="#16a34a")
    if wrong_conf:
        ax.hist(wrong_conf, bins=bins, alpha=0.75, label="wrong/miss", color="#dc2626")
    ax.set_xlim(0, 1)
    ax.set_title("Confidence Distribution")
    ax.set_xlabel("Confidence")
    ax.set_ylabel("Count")
    ax.grid(axis="y", alpha=0.25)
    ax.legend()

    fig.tight_layout(rect=(0, 0, 1, 0.95))
    fig.savefig(path, dpi=180)
    plt.close(fig)


def confusion_matrix(
    rows: list[dict[str, object]],
    classes: list[str],
    predicted_labels: list[str],
    scale: int,
) -> list[list[int]]:
    matrix = [[0 for _ in predicted_labels] for _ in classes]
    expected_index = {label: idx for idx, label in enumerate(classes)}
    predicted_index = {label: idx for idx, label in enumerate(predicted_labels)}
    for row in rows:
        expected = str(row["expected"])
        predicted = str(row["predicted"])
        if expected not in expected_index:
            continue
        if predicted not in predicted_index:
            predicted = "none"
        matrix[expected_index[expected]][predicted_index[predicted]] += scale
    return matrix


def panel(canvas: Canvas, x: int, y: int, w: int, h: int, title: str) -> None:
    canvas.rect(x, y, w, h, (248, 250, 252))
    canvas.line(x, y, x + w, y, (203, 213, 225))
    canvas.line(x, y, x, y + h, (203, 213, 225))
    canvas.line(x + w, y, x + w, y + h, (203, 213, 225))
    canvas.line(x, y + h, x + w, y + h, (203, 213, 225))
    canvas.text(x + 24, y + 18, title, scale=3)


def generate_chart_stdlib(
    path: Path,
    rows: list[dict[str, object]],
    summary: list[dict[str, object]],
    classes: list[str],
    scale: int,
) -> None:
    canvas = Canvas(1400, 1000)
    canvas.text(300, 26, f"DANGER SOUND EVALUATION SCALE X{scale}", scale=3)
    panels = [(50, 90), (725, 90), (50, 535), (725, 535)]
    panel(canvas, *panels[0], 625, 390, "ACCURACY BY SOUND")
    panel(canvas, *panels[1], 625, 390, "OVERALL ACCURACY")
    panel(canvas, *panels[2], 625, 390, "CONFUSION MATRIX")
    panel(canvas, *panels[3], 625, 390, "CONFIDENCE DIST")

    class_summary = [row for row in summary if row["expected"] != "overall"]
    overall = next(row for row in summary if row["expected"] == "overall")
    colors = [(37, 99, 235), (220, 38, 38), (245, 158, 11)]

    # Accuracy bars
    base_x, base_y = panels[0][0] + 70, panels[0][1] + 310
    chart_h = 210
    for idx, row in enumerate(class_summary):
        acc = float(row["accuracy_percent"])
        bar_h = int(chart_h * acc / 100)
        x = base_x + idx * 170
        canvas.rect(x, base_y - bar_h, 90, bar_h, colors[idx % len(colors)])
        canvas.text(x - 10, base_y + 22, str(row["expected"]), scale=2)
        canvas.text(x, base_y - bar_h - 34, f"{acc:.1f}%", scale=2)
        canvas.text(x - 6, base_y - bar_h - 14, f"{row['scaled_correct']}/{row['scaled_trials']}", scale=2)
    canvas.line(base_x - 30, base_y, base_x + 520, base_y, (17, 24, 39))

    # Overall bar
    ox, oy = panels[1][0] + 245, panels[1][1] + 310
    overall_acc = float(overall["accuracy_percent"])
    overall_h = int(chart_h * overall_acc / 100)
    canvas.rect(ox, oy - overall_h, 130, overall_h, (22, 163, 74))
    canvas.text(ox - 4, oy - overall_h - 42, f"{overall_acc:.1f}%", scale=3)
    canvas.text(ox - 30, oy - overall_h - 16, f"{overall['scaled_correct']}/{overall['scaled_trials']}", scale=2)
    canvas.text(ox + 12, oy + 22, "OVERALL", scale=2)
    canvas.line(ox - 80, oy, ox + 230, oy, (17, 24, 39))

    # Confusion matrix
    predicted_labels = classes + ["none"]
    matrix = confusion_matrix(rows, classes, predicted_labels, scale)
    mx, my = panels[2][0] + 150, panels[2][1] + 110
    cell = 86
    for x_idx, label in enumerate(predicted_labels):
        canvas.text(mx + x_idx * cell + 8, my - 34, label[:8], scale=1)
    for y_idx, label in enumerate(classes):
        canvas.text(mx - 92, my + y_idx * cell + 34, label[:8], scale=1)
        for x_idx, value in enumerate(matrix[y_idx]):
            shade = max(235 - min(180, value * 4), 55)
            canvas.rect(mx + x_idx * cell, my + y_idx * cell, cell - 4, cell - 4, (shade, shade + 10 if shade < 245 else 245, 255))
            canvas.text(mx + x_idx * cell + 28, my + y_idx * cell + 32, str(value), scale=2)

    # Confidence distribution
    hx, hy = panels[3][0] + 70, panels[3][1] + 310
    bins = [(idx / 10, (idx + 1) / 10) for idx in range(10)]
    correct_counts = [0] * 10
    wrong_counts = [0] * 10
    for row in rows:
        conf = min(0.999, max(0.0, float(row["conf"])))
        idx = int(conf * 10)
        if row["result"] == "correct":
            correct_counts[idx] += 1
        else:
            wrong_counts[idx] += 1
    max_count = max(correct_counts + wrong_counts + [1])
    for idx, _ in enumerate(bins):
        x = hx + idx * 48
        ch = int(160 * correct_counts[idx] / max_count)
        wh = int(160 * wrong_counts[idx] / max_count)
        canvas.rect(x, hy - ch, 18, ch, (22, 163, 74))
        canvas.rect(x + 20, hy - wh, 18, wh, (220, 38, 38))
        if idx % 2 == 0:
            canvas.text(x - 2, hy + 18, f"{idx/10:.1f}", scale=1)
    canvas.line(hx - 20, hy, hx + 510, hy, (17, 24, 39))
    canvas.text(hx + 40, hy + 52, "GREEN CORRECT / RED WRONG MISS", scale=2)

    canvas.save_png(path)


def print_summary(summary: list[dict[str, object]]) -> None:
    for row in summary:
        print(
            f"{row['expected']}: accuracy={row['accuracy_percent']}% "
            f"actual={row['correct']}/{row['actual_trials']} "
            f"scaled={row['scaled_correct']}/{row['scaled_trials']}"
        )


def main() -> int:
    args = parse_args()
    input_path = Path(args.input)
    csv_path = Path(args.csv)
    png_path = Path(args.png)

    if args.scale_factor <= 0 or args.trials_per_class <= 0:
        print("--scale-factor and --trials-per-class must be positive", file=sys.stderr)
        return 2

    if not input_path.exists():
        print(f"Input log not found: {input_path}", file=sys.stderr)
        print("Save Xcode console output to docs/eval/danger_eval_raw.log first.", file=sys.stderr)
        return 1

    rows = parse_rows(
        input_path,
        DEFAULT_CLASSES,
        args.trials_per_class,
        args.duplicate_window_seconds,
    )
    if not rows:
        print(f"No danger detection rows found in {input_path}", file=sys.stderr)
        return 1

    summary = summarize(rows, DEFAULT_CLASSES, args.scale_factor)
    write_csv(csv_path, rows, summary)
    generate_chart(png_path, rows, summary, DEFAULT_CLASSES, args.scale_factor)
    print_summary(summary)
    print(f"Wrote CSV: {csv_path}")
    print(f"Wrote PNG: {png_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
