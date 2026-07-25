#!/usr/bin/env python3
"""Train PaneCue Mini, a tiny offline intent model for macOS.

The runtime is deliberately simple: a hashed character/word feature extractor
and a quantized linear classifier. The exported model is usually below 250 KB
and has no Python, Ollama, or transformer dependency inside PaneCue.
"""

from __future__ import annotations

import argparse
import json
import random
import re
import struct
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable

import numpy as np


CLASS_NAMES = [
    "apply_code_and_call",
    "apply_documentation_and_code",
    "apply_notes_and_browser",
    "arrange_dynamic_workspace",
    "show_browser_video",
    "restore_previous_layout",
    "no_action",
]

DYNAMIC_REQUESTS = [
    "открой вскод а заметки сделай чуть поменьше",
    "поставь VS Code большим а Notes маленькими справа",
    "открой Xcode и Safari поровну",
    "сделай Cursor главным а браузер вспомогательным",
    "расположи терминал слева а Obsidian справа",
    "покажи Chrome сверху а заметки снизу",
    "открой телеграм маленьким рядом с Xcode",
    "сделай браузер на весь экран а заметки маленькими сбоку",
    "вскод побольше заметки поменьше",
    "заментки слева а хром справа",
    "поставь Notion рядом с Figma",
    "открой Safari и терминал разделив экран",
    "make VS Code larger and Notes a little smaller",
    "put Xcode and Safari side by side equally",
    "keep Cursor large with a small browser on the right",
    "place Terminal on the left and Obsidian on the right",
    "show Chrome above Notes",
    "open Telegram as a small window beside Xcode",
    "make the browser primary and notes secondary",
    "arrange Notion next to Figma",
]

DYNAMIC_TARGETS = [
    ("VS Code", "заметки"),
    ("Xcode", "Safari"),
    ("Cursor", "Chrome"),
    ("Terminal", "Obsidian"),
    ("Windsurf", "документация"),
    ("Zed", "браузер"),
    ("PyCharm", "Telegram"),
    ("IntelliJ", "Notion"),
    ("Figma", "Slack"),
    ("Sublime Text", "Firefox"),
    ("Arc", "Bear"),
    ("Brave", "Craft"),
    ("Preview", "Notes"),
    ("Finder", "Terminal"),
    ("VS Code", "Discord"),
    ("Safari", "календарь"),
]

DYNAMIC_TEMPLATES_RU = [
    "открой {left} и {right} поровну",
    "поставь {left} большим а {right} чуть поменьше",
    "сделай {left} главным а {right} узкой колонкой справа",
    "расположи {left} слева и {right} справа",
    "покажи {left} сверху а {right} снизу",
    "размести {left} на две трети экрана и {right} на оставшуюся треть",
    "оставь {left} почти на весь экран а {right} компактным сбоку",
    "хочу {left} 70 на 30 вместе с {right}",
    "выведи {right} маленьким рядом с {left}",
    "сделай {right} уже а {left} шире",
]

DYNAMIC_TEMPLATES_EN = [
    "open {left} and {right} equally",
    "make {left} primary and {right} a little smaller",
    "keep {left} large with {right} in a narrow right column",
    "place {left} on the left and {right} on the right",
    "show {left} above {right}",
    "give {left} two thirds and {right} the remaining third",
    "keep {left} almost full screen with compact {right} beside it",
    "arrange {left} and {right} seventy thirty",
    "float a small {right} next to {left}",
    "make {right} narrower and {left} wider",
]

UNRELATED_REQUESTS = [
    "какая сегодня погода",
    "расскажи последние новости",
    "напиши письмо коллеге",
    "создай напоминание",
    "прибавь громкость",
    "поставь будильник",
    "найди хороший ресторан",
    "как приготовить пасту",
    "сколько сейчас времени",
    "расскажи шутку",
    "включи музыку",
    "выключи компьютер",
    "проверь мою почту",
    "переведи этот текст",
    "что ты умеешь",
    "what is the weather",
    "tell me the latest news",
    "write an email",
    "create a reminder",
    "turn up the volume",
    "set an alarm",
    "find a restaurant",
    "play some music",
    "translate this text",
    "tell me a joke",
    "what time is it",
    "open my mail",
    "shut down the computer",
]

PREFIXES_RU = [
    "",
    "panecue ",
    "слушай ",
    "пожалуйста ",
    "можешь ",
    "давай ",
    "мне нужно чтобы ты ",
    "быстро ",
]
SUFFIXES_RU = [
    "",
    " пожалуйста",
    " сейчас",
    " на этом экране",
    " для работы",
]
PREFIXES_EN = [
    "",
    "panecue ",
    "please ",
    "can you ",
    "could you ",
    "quickly ",
    "i need you to ",
]
SUFFIXES_EN = [
    "",
    " please",
    " now",
    " on this display",
    " for work",
]

ASR_REPLACEMENTS = [
    ("vs code", "вс код"),
    ("visual studio code", "vs code"),
    ("face time", "facetime"),
    ("фейс тайм", "facetime"),
    ("документацию", "документация"),
    ("документацией", "документация"),
    ("видеозвонок", "видео звонок"),
    ("созвона", "созвон"),
    ("браузером", "браузер"),
    ("заметками", "заметки"),
    ("picture in picture", "picture and picture"),
    ("workspace", "work space"),
    ("vscode", "вскод"),
    ("notes", "ноутс"),
    ("заметки", "заментки"),
    ("obsidian", "обсидиан"),
    ("notion", "ноушен"),
    ("pycharm", "пайчарм"),
    ("intellij", "интеллиджей"),
    ("sublime text", "саблайм"),
    ("seventy thirty", "70 30"),
    ("two thirds", "2 thirds"),
]


def normalize(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text.casefold())
    characters = [
        character
        if character.isalnum()
        else " "
        for character in decomposed
        if not unicodedata.combining(character)
    ]
    return " ".join("".join(characters).split())


def fnv1a(value: str) -> int:
    result = 0xCBF29CE484222325
    for byte in value.encode("utf-8"):
        result ^= byte
        result = (result * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return result


def feature_indices(text: str, dimension: int) -> list[int]:
    normalized = normalize(text)
    if not normalized:
        return []

    features: set[str] = set()
    words = normalized.split()
    for word in words:
        features.add(f"w:{word}")
    for left, right in zip(words, words[1:]):
        features.add(f"b:{left}_{right}")

    compact = f"^{normalized.replace(' ', '_')}$"
    for width in range(2, 6):
        for index in range(max(0, len(compact) - width + 1)):
            features.add(f"c{width}:{compact[index:index + width]}")

    return sorted({fnv1a(feature) % dimension for feature in features})


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    with path.open(encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def request_and_action(record: dict[str, Any]) -> tuple[str, str]:
    content = record["messages"][0]["content"]
    request = content.rsplit("Request: ", maxsplit=1)[-1]
    action = record["messages"][-1]["tool_calls"][0]["function"]["name"]
    return request, action


def is_russian(text: str) -> bool:
    return bool(re.search(r"[а-яё]", text, flags=re.IGNORECASE))


def mutate_typo(text: str, rng: random.Random) -> str:
    candidates = [
        index
        for index, character in enumerate(text)
        if character.isalpha()
        and 0 < index < len(text) - 1
        and text[index - 1].isalpha()
        and text[index + 1].isalpha()
    ]
    if not candidates:
        return text
    index = rng.choice(candidates)
    if rng.random() < 0.5:
        return text[:index] + text[index + 1:]
    characters = list(text)
    characters[index - 1], characters[index] = (
        characters[index],
        characters[index - 1],
    )
    return "".join(characters)


def augment(text: str, rng: random.Random) -> str:
    result = normalize(text)
    russian = is_russian(result)
    prefixes = PREFIXES_RU if russian else PREFIXES_EN
    suffixes = SUFFIXES_RU if russian else SUFFIXES_EN

    if rng.random() < 0.8:
        result = rng.choice(prefixes) + result
    if rng.random() < 0.55:
        result += rng.choice(suffixes)
    for source, target in ASR_REPLACEMENTS:
        if source in result and rng.random() < 0.65:
            result = result.replace(source, target)
    if rng.random() < 0.22:
        result = mutate_typo(result, rng)
    if rng.random() < 0.15:
        result = result.replace(" и ", " плюс ", 1)
    return " ".join(result.split())


def negative_variants(
    positives: Iterable[str],
    rng: random.Random,
) -> list[str]:
    rows: list[str] = []
    for request in positives:
        normalized = normalize(request)
        if is_russian(normalized):
            templates = [
                "не " + normalized,
                "не надо " + normalized,
                "я только обсуждаю как " + normalized + " ничего не делай",
                "позже можно " + normalized + " но сейчас не меняй окна",
                "можно ли вообще " + normalized,
            ]
        else:
            templates = [
                "do not " + normalized,
                "please do not " + normalized,
                "i am only discussing how to " + normalized,
                "maybe later " + normalized + " but do nothing now",
                "is it possible to " + normalized,
            ]
        rows.extend(templates)
    rng.shuffle(rows)
    return rows


def generated_dynamic_requests() -> list[str]:
    rows = list(DYNAMIC_REQUESTS)
    for left, right in DYNAMIC_TARGETS:
        for template in DYNAMIC_TEMPLATES_RU + DYNAMIC_TEMPLATES_EN:
            rows.append(template.format(left=left, right=right))
    return rows


def balanced_training_rows(
    records: list[dict[str, Any]],
    hard_records: list[dict[str, Any]],
    per_class: int,
    seed: int,
) -> tuple[list[str], list[str]]:
    rng = random.Random(seed)
    grouped: dict[str, list[str]] = defaultdict(list)
    positives: list[str] = []

    for record in records + hard_records:
        request, action = request_and_action(record)
        if action == "apply_custom_scenario":
            continue
        if action in CLASS_NAMES:
            grouped[action].append(request)
            if action != "no_action":
                positives.append(request)

    grouped["no_action"].extend(UNRELATED_REQUESTS)
    grouped["no_action"].extend(negative_variants(positives, rng))
    grouped["arrange_dynamic_workspace"].extend(
        generated_dynamic_requests()
    )

    texts: list[str] = []
    labels: list[str] = []
    for action in CLASS_NAMES:
        bases = list(dict.fromkeys(grouped[action]))
        if not bases:
            raise RuntimeError(f"No training examples for {action}")
        for index in range(per_class):
            base = bases[index % len(bases)]
            texts.append(augment(base, rng) if index >= len(bases) else base)
            labels.append(action)

    order = list(range(len(texts)))
    rng.shuffle(order)
    return [texts[index] for index in order], [
        labels[index] for index in order
    ]


def train_linear_model(
    texts: list[str],
    labels: list[str],
    dimension: int,
    seed: int,
    epochs: int,
) -> tuple[np.ndarray, np.ndarray]:
    rng = np.random.default_rng(seed)
    weights = np.zeros(
        (len(CLASS_NAMES), dimension),
        dtype=np.float32,
    )
    biases = np.zeros(len(CLASS_NAMES), dtype=np.float32)
    class_indices = {
        name: index
        for index, name in enumerate(CLASS_NAMES)
    }
    encoded_labels = np.asarray(
        [class_indices[label] for label in labels],
        dtype=np.int32,
    )
    encoded_features = [
        np.asarray(feature_indices(text, dimension), dtype=np.int32)
        for text in texts
    ]
    order = np.arange(len(texts))

    for epoch in range(epochs):
        rng.shuffle(order)
        learning_rate = 0.035 / (1 + epoch * 0.18)
        correct = 0
        for row in order:
            indices = encoded_features[row]
            scores = biases + np.sum(weights[:, indices], axis=1)
            shifted = scores - np.max(scores)
            probabilities = np.exp(shifted)
            probabilities /= np.sum(probabilities)
            expected = encoded_labels[row]
            correct += int(np.argmax(probabilities) == expected)
            probabilities[expected] -= 1

            weights[:, indices] *= 1 - learning_rate * 2e-5
            weights[:, indices] -= (
                learning_rate * probabilities[:, None]
            )
            biases -= learning_rate * probabilities
        print(
            f"epoch {epoch + 1:02d}: "
            f"train_accuracy={correct / len(texts):.1%}"
        )

    return weights, biases


def logits_for_texts(
    texts: list[str],
    weights: np.ndarray,
    biases: np.ndarray,
    dimension: int,
) -> np.ndarray:
    result = np.empty(
        (len(texts), len(CLASS_NAMES)),
        dtype=np.float32,
    )
    for row, text in enumerate(texts):
        indices = feature_indices(text, dimension)
        result[row] = biases + np.sum(
            weights[:, indices],
            axis=1,
        )
    return result


def softmax(logits: np.ndarray) -> np.ndarray:
    shifted = logits - np.max(logits, axis=1, keepdims=True)
    exponentials = np.exp(shifted)
    return exponentials / np.sum(exponentials, axis=1, keepdims=True)


def evaluate(
    weights: np.ndarray,
    biases: np.ndarray,
    texts: list[str],
    labels: list[str],
    dimension: int,
    confidence_threshold: float,
    margin_threshold: float,
) -> dict[str, Any]:
    probabilities = softmax(
        logits_for_texts(texts, weights, biases, dimension)
    )
    predictions: list[str] = []
    confidences: list[float] = []
    margins: list[float] = []
    for row in probabilities:
        order = np.argsort(row)
        best = int(order[-1])
        confidence = float(row[best])
        margin = confidence - float(row[order[-2]])
        prediction = CLASS_NAMES[best]
        if (
            prediction != "no_action"
            and (
                confidence < confidence_threshold
                or margin < margin_threshold
            )
        ):
            prediction = "no_action"
        predictions.append(prediction)
        confidences.append(confidence)
        margins.append(margin)

    correct = sum(
        expected == predicted
        for expected, predicted in zip(labels, predictions)
    )
    per_action: dict[str, Counter[str]] = defaultdict(Counter)
    for expected, predicted in zip(labels, predictions):
        per_action[expected][
            "correct" if expected == predicted else "wrong"
        ] += 1
    return {
        "accuracy": correct / max(len(labels), 1),
        "correct": correct,
        "total": len(labels),
        "mean_confidence": float(np.mean(confidences)),
        "mean_margin": float(np.mean(margins)),
        "per_action": {
            action: dict(counts)
            for action, counts in sorted(per_action.items())
        },
    }


def write_model(
    path: Path,
    weights: np.ndarray,
    biases: np.ndarray,
    dimension: int,
    confidence_threshold: float,
    margin_threshold: float,
    temperature: float,
) -> dict[str, Any]:
    scales = np.maximum(np.max(np.abs(weights), axis=1) / 127.0, 1e-8)
    quantized = np.clip(
        np.rint(weights / scales[:, None]),
        -127,
        127,
    ).astype(np.int8)

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        handle.write(
            struct.pack(
                "<8sIIIfff",
                b"PCMINI1\0",
                1,
                dimension,
                len(CLASS_NAMES),
                confidence_threshold,
                margin_threshold,
                temperature,
            )
        )
        handle.write(biases.astype("<f4").tobytes())
        handle.write(scales.astype("<f4").tobytes())
        handle.write(quantized.tobytes())

    return {
        "format": "PaneCueMini",
        "version": 1,
        "classes": CLASS_NAMES,
        "dimension": dimension,
        "confidence_threshold": confidence_threshold,
        "margin_threshold": margin_threshold,
        "temperature": temperature,
        "size_bytes": path.stat().st_size,
        "quantization": "per-class int8",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--data",
        type=Path,
        default=Path("training/data"),
    )
    parser.add_argument(
        "--hard-data",
        type=Path,
        default=Path("training/hard-data"),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("training/panecue-mini/panecue-mini-v2.bin"),
    )
    parser.add_argument("--dimension", type=int, default=71_424)
    parser.add_argument("--per-class", type=int, default=6_000)
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    train_records = read_jsonl(args.data / "train.jsonl")
    hard_records = read_jsonl(args.hard_data / "train.jsonl")
    texts, labels = balanced_training_rows(
        train_records,
        hard_records,
        per_class=args.per_class,
        seed=args.seed,
    )

    weights, biases = train_linear_model(
        texts,
        labels,
        args.dimension,
        args.seed,
        args.epochs,
    )

    validation_rows = read_jsonl(args.data / "valid.jsonl")
    validation_pairs = [
        request_and_action(record)
        for record in validation_rows
        if request_and_action(record)[1] != "apply_custom_scenario"
    ]
    validation_texts = [pair[0] for pair in validation_pairs]
    validation_labels = [pair[1] for pair in validation_pairs]

    confidence_threshold = 0.52
    margin_threshold = 0.10
    validation = evaluate(
        weights,
        biases,
        validation_texts,
        validation_labels,
        args.dimension,
        confidence_threshold,
        margin_threshold,
    )

    metadata = write_model(
        args.output,
        weights,
        biases,
        args.dimension,
        confidence_threshold,
        margin_threshold,
        temperature=1.0,
    )

    test_rows = read_jsonl(args.data / "test.jsonl")
    test_pairs = [
        request_and_action(record)
        for record in test_rows
        if request_and_action(record)[1] != "apply_custom_scenario"
    ]
    test_texts = [pair[0] for pair in test_pairs]
    test_labels = [pair[1] for pair in test_pairs]
    test = evaluate(
        weights,
        biases,
        test_texts,
        test_labels,
        args.dimension,
        confidence_threshold,
        margin_threshold,
    )

    metadata["training_examples"] = len(texts)
    metadata["learned_parameters"] = (
        len(CLASS_NAMES) * args.dimension + len(CLASS_NAMES)
    )
    metadata["validation"] = validation
    metadata["test"] = test
    metadata_path = args.output.with_suffix(".json")
    metadata_path.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"training examples: {len(texts)}")
    print(
        "validation: "
        f"{validation['correct']}/{validation['total']} "
        f"= {validation['accuracy']:.1%}"
    )
    print(
        "test: "
        f"{test['correct']}/{test['total']} "
        f"= {test['accuracy']:.1%}"
    )
    print(f"model: {args.output} ({metadata['size_bytes']:,} bytes)")
    print(f"metadata: {metadata_path}")


if __name__ == "__main__":
    main()
