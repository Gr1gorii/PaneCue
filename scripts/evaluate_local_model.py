#!/usr/bin/env python3
"""Evaluate an Ollama model against PaneCue's held-out tool requests."""

from __future__ import annotations

import argparse
import json
import random
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


KNOWN_ACTIONS = {
    "apply_code_and_call",
    "apply_documentation_and_code",
    "apply_notes_and_browser",
    "show_browser_video",
    "restore_previous_layout",
    "apply_custom_scenario",
    "no_action",
}


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    with path.open(encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def expected_action(record: dict[str, Any]) -> tuple[str, str | None]:
    function = record["messages"][-1]["tool_calls"][0]["function"]
    arguments = function.get("arguments") or {}
    if isinstance(arguments, str):
        arguments = json.loads(arguments)
    return function["name"], arguments.get("scenario_name")


def parse_prediction(message: dict[str, Any]) -> tuple[str | None, str | None]:
    calls = message.get("tool_calls") or []
    if calls:
        function = calls[0].get("function") or {}
        arguments = function.get("arguments") or {}
        if isinstance(arguments, str):
            try:
                arguments = json.loads(arguments)
            except json.JSONDecodeError:
                arguments = {}
        return function.get("name"), arguments.get("scenario_name")

    content = (message.get("content") or "").strip()
    try:
        decoded = json.loads(content)
        if isinstance(decoded, dict):
            return decoded.get("action"), decoded.get("scenario_name")
    except json.JSONDecodeError:
        pass

    matches = [action for action in KNOWN_ACTIONS if action in content]
    if len(matches) == 1:
        return matches[0], None
    return None, None


def request_prediction(
    base_url: str,
    model: str,
    record: dict[str, Any],
) -> tuple[str | None, str | None]:
    body = {
        "model": model,
        "stream": False,
        "think": False,
        "keep_alive": "5m",
        "messages": record["messages"][:-1],
        "tools": record["tools"],
        "options": {
            "temperature": 0,
            "num_predict": 64,
        },
    }
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/api/chat",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        root = json.load(response)
    return parse_prediction(root.get("message") or {})


def unload(base_url: str, model: str) -> None:
    body = {"model": model, "keep_alive": 0}
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/api/generate",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        urllib.request.urlopen(request, timeout=30).read()
    except (urllib.error.URLError, TimeoutError):
        pass


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("model")
    parser.add_argument(
        "--data",
        type=Path,
        default=Path("training/data/test.jsonl"),
    )
    parser.add_argument("--limit", type=int, default=70)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--base-url", default="http://127.0.0.1:11434")
    parser.add_argument("--show-errors", action="store_true")
    args = parser.parse_args()

    records = read_jsonl(args.data)
    random.Random(args.seed).shuffle(records)
    if args.limit > 0:
        records = records[: args.limit]

    total = 0
    correct = 0
    per_action: dict[str, Counter[str]] = defaultdict(Counter)
    confusions: Counter[tuple[str, str]] = Counter()
    failures: list[tuple[str, str, str]] = []

    try:
        for index, record in enumerate(records, start=1):
            expected, expected_scenario = expected_action(record)
            predicted, predicted_scenario = request_prediction(
                args.base_url,
                args.model,
                record,
            )
            scenario_ok = (
                expected != "apply_custom_scenario"
                or expected_scenario == predicted_scenario
            )
            is_correct = expected == predicted and scenario_ok
            total += 1
            correct += int(is_correct)
            per_action[expected]["correct" if is_correct else "wrong"] += 1
            if not is_correct:
                confusions[(expected, predicted or "<none>")] += 1
                request = record["messages"][0]["content"].split(
                    "Request: ",
                    maxsplit=1,
                )[-1]
                failures.append(
                    (expected, predicted or "<none>", request)
                )
            print(
                f"\r{index}/{len(records)}  accuracy={correct / total:.1%}",
                end="",
                flush=True,
            )
    finally:
        unload(args.base_url, args.model)

    print()
    print(f"model: {args.model}")
    print(f"accuracy: {correct}/{total} = {correct / max(total, 1):.1%}")
    for action in sorted(per_action):
        values = per_action[action]
        action_total = values["correct"] + values["wrong"]
        print(
            f"  {action}: "
            f"{values['correct']}/{action_total} "
            f"= {values['correct'] / max(action_total, 1):.1%}"
        )
    if confusions:
        print("top confusions:")
        for (expected, predicted), count in confusions.most_common(10):
            print(f"  {expected} -> {predicted}: {count}")
    if args.show_errors and failures:
        print("errors:")
        for expected, predicted, request in failures:
            print(f"  {expected} -> {predicted}: {request}")


if __name__ == "__main__":
    main()
