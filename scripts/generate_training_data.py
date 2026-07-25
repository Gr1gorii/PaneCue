#!/usr/bin/env python3
"""Generate a deterministic PaneCue tool-routing dataset."""

from __future__ import annotations

import argparse
import copy
import json
import random
import re
from pathlib import Path
from typing import Any


SCENARIO_NAMES = [
    "Deep Work",
    "Исследование",
    "Монтаж",
    "Writing",
]

ACTION_PHRASES = {
    "apply_code_and_call": [
        "открой код и созвон",
        "поставь VS Code рядом с FaceTime",
        "мне нужен редактор и окно звонка",
        "разложи код и встречу",
        "сделай рабочее место для программирования и созвона",
        "код на весь экран а камеру маленькой сбоку",
        "запусти сценарий код плюс звонок",
        "покажи IDE и маленькое окно камеры",
        "оставь редактор большим и добавь Zoom",
        "подготовь экран для кодинга во время встречи",
        "терминал и созвон рядом",
        "работа с кодом плюс видеовстреча",
        "выведи звонок поверх редактора",
        "хочу писать код и видеть собеседника",
        "расположи Xcode вместе со звонком",
        "code and call",
        "put VS Code next to FaceTime",
        "keep the editor large and float the meeting",
        "arrange my IDE with a small camera window",
        "I need to code during a video call",
        "open the coding and meeting workspace",
        "show Xcode together with Zoom",
        "make the call compact beside my editor",
        "prepare a programming workspace for a meeting",
    ],
    "apply_documentation_and_code": [
        "открой документацию рядом с кодом",
        "поставь справку и VS Code рядом",
        "мне нужен браузер с документацией возле редактора",
        "разложи код и документацию",
        "сделай рабочее место для чтения API и программирования",
        "покажи мануал слева а код справа",
        "запусти сценарий документация плюс код",
        "открой reference рядом с IDE",
        "хочу читать документацию и писать код",
        "расположи Preview с документацией рядом с Xcode",
        "браузер со справкой и редактор кода",
        "раздели экран между документацией и кодом",
        "покажи документацию к библиотеке возле терминала",
        "поставь окно API docs рядом с проектом",
        "подготовь экран для работы по инструкции",
        "documentation and code",
        "put the API docs beside VS Code",
        "split the screen between reference and editor",
        "I need to read documentation while coding",
        "open the docs and coding workspace",
        "show the manual next to Xcode",
        "place browser documentation beside my IDE",
        "arrange reference material with the code editor",
        "prepare a coding layout with documentation",
    ],
    "apply_notes_and_browser": [
        "открой заметки и браузер",
        "поставь Safari рядом с заметками",
        "мне нужны Notes и Chrome рядом",
        "разложи браузер и заметки",
        "сделай рабочее место для исследования и записей",
        "покажи сайт слева а заметки справа",
        "запусти сценарий заметки плюс браузер",
        "хочу искать информацию и сразу записывать",
        "расположи Notion рядом с Chrome",
        "раздели экран между браузером и заметками",
        "открой веб страницу возле Notes",
        "браузер большой а заметки рядом",
        "подготовь экран для ресерча",
        "поставь Obsidian рядом с Safari",
        "хочу конспектировать из браузера",
        "notes and browser",
        "put Safari beside Notes",
        "split the screen between Chrome and my notes",
        "I want to research and take notes",
        "open the browser and notes workspace",
        "show Notion next to the browser",
        "place Obsidian beside Safari",
        "arrange a web page with a note editor",
        "prepare a research and note taking layout",
    ],
    "show_browser_video": [
        "вытащи видео из браузера",
        "покажи видео отдельным маленьким окном",
        "вынеси плеер из Chrome",
        "открой плавающее видео",
        "оставь только кадр видео сбоку",
        "сделай картинку в картинке из браузера",
        "покажи браузерное видео поверх окон",
        "убери интерфейс Chrome и оставь плеер",
        "перенеси текущее видео в компактное окно",
        "отдели видеоплеер от вкладки",
        "хочу смотреть ролик в маленьком окне",
        "вынеси YouTube в плавающий плеер",
        "покажи только область видео",
        "сверни вкладку и оставь видео",
        "запусти режим браузерного видео",
        "extract the browser video",
        "show the video in a small floating window",
        "detach the player from Chrome",
        "open browser picture in picture",
        "keep only the video frame visible",
        "float the current YouTube video",
        "hide the browser interface and show the player",
        "move this video into a compact overlay",
        "start the browser video mode",
    ],
    "restore_previous_layout": [
        "верни всё обратно",
        "восстанови предыдущую раскладку",
        "отмени расположение окон",
        "верни окна как были",
        "восстанови рабочее место",
        "откати последний сценарий",
        "убери текущую раскладку",
        "верни прежние размеры окон",
        "отмени последнее изменение окон",
        "закрой сценарий и восстанови окна",
        "хочу прежнее расположение",
        "верни исходный вид",
        "восстанови окна до сценария",
        "отмени менеджмент окон",
        "поставь всё обратно как раньше",
        "restore the previous layout",
        "put all windows back",
        "undo the window arrangement",
        "restore my workspace",
        "return to the old window sizes",
        "cancel the current layout",
        "undo the last PaneCue scenario",
        "restore windows to where they were",
        "bring back the original arrangement",
    ],
    "no_action": [
        "какая сегодня погода",
        "напиши письмо коллеге",
        "увеличь громкость",
        "выключи компьютер",
        "найди рецепт пасты",
        "расскажи анекдот",
        "открой почту",
        "создай напоминание на завтра",
        "не открывай заметки и браузер",
        "не меняй расположение окон",
        "не выноси видео из браузера",
        "я просто говорю про код и созвон",
        "может быть потом сделаем документацию и код",
        "поставь это рядом",
        "сделай красиво",
        "what is the weather today",
        "write an email to my colleague",
        "turn up the volume",
        "shut down the computer",
        "find a pasta recipe",
        "tell me a joke",
        "do not arrange notes and browser",
        "do not change my windows",
        "maybe later we can use code and call",
    ],
}

CUSTOM_PHRASES = [
    ("Deep Work", "запусти Deep Work"),
    ("Deep Work", "включи глубокую работу"),
    ("Deep Work", "перейди в режим фокуса"),
    ("Deep Work", "apply my Deep Work scenario"),
    ("Deep Work", "start the focus workspace"),
    ("Исследование", "запусти сценарий Исследование"),
    ("Исследование", "начать исследование"),
    ("Исследование", "включи мой исследовательский режим"),
    ("Исследование", "apply the Исследование scenario"),
    ("Исследование", "start my research workspace"),
    ("Монтаж", "запусти Монтаж"),
    ("Монтаж", "включи сценарий для монтажа"),
    ("Монтаж", "перейди в монтажный режим"),
    ("Монтаж", "apply my Монтаж scenario"),
    ("Монтаж", "start the editing workspace"),
    ("Writing", "запусти Writing"),
    ("Writing", "включи мой сценарий для текста"),
    ("Writing", "перейди в режим письма"),
    ("Writing", "apply the Writing scenario"),
    ("Writing", "start my writing workspace"),
    ("Deep Work", "активируй Deep Work пожалуйста"),
    ("Исследование", "открой рабочее место Исследование"),
    ("Монтаж", "подготовь раскладку Монтаж"),
    ("Writing", "switch to Writing"),
]

HARD_TRAINING_PHRASES = {
    "apply_code_and_call": [
        "редактор остаётся главным а встреча маленькая справа",
        "размести проект и компактный видеозвонок",
        "put my IDE with a small meeting overlay",
        "programming workspace with the camera in the corner",
    ],
    "apply_documentation_and_code": [
        "размести редактор рядом с сайтом руководства",
        "мне нужно следовать инструкции пока я пишу программу",
        "открой справочную статью вместе с исходным кодом",
        "покажи руководство по API возле проекта",
        "терминал рядом с техническим мануалом",
        "reference material alongside my source code",
        "place an API guide beside the editor",
        "show the technical manual with my project",
        "I need instructions open while programming",
        "developer reference and IDE side by side",
        "open a help article next to the codebase",
        "arrange library reference with the terminal",
    ],
    "apply_notes_and_browser": [
        "Safari рядом с приложением для конспекта",
        "хочу сохранять идеи из веб страницы в Notes",
        "размести обычный сайт вместе с Obsidian",
        "покажи поисковую страницу возле моих записей",
        "браузер для ресерча и отдельный блокнот",
        "place a note app next to the web browser",
        "keep Safari open beside my notebook",
        "research the web while capturing ideas",
        "show a normal website with Obsidian",
        "browser on one side and Notes on the other",
        "arrange Chrome with my writing notes",
        "web research and note taking side by side",
    ],
    "show_browser_video": [
        "скрой исходную вкладку но оставь ролик поверх окон",
        "покажи только текущий фильм без панели браузера",
        "hide the source tab and keep its video overlay",
        "float only the current player without browser chrome",
    ],
    "restore_previous_layout": [
        "откати окна к состоянию до запуска режима",
        "верни прежние позиции и размеры приложений",
        "revert every window to its pre-scenario position",
        "undo PaneCue and restore the old workspace",
    ],
    "no_action": [
        "я лишь упомянул код и звонки ничего не запускай",
        "это разговор о заметках и браузерах без команды",
        "не надо применять сценарий с документацией",
        "пока не меняй мои окна даже если я говорю про видео",
        "I am only mentioning code and calls do nothing",
        "this is a discussion about notes and browsers",
        "do not apply the documentation workspace",
        "leave my windows alone even though I said video",
    ],
}


def tool(name: str, description: str) -> dict[str, Any]:
    return {
        "type": "function",
        "function": {
            "name": name,
            "description": description,
            "parameters": {
                "type": "object",
                "properties": {},
                "additionalProperties": False,
            },
        },
    }


TOOLS = [
    tool("apply_code_and_call", "Code editor together with a call or camera."),
    tool(
        "apply_documentation_and_code",
        "Code editor together with documentation.",
    ),
    tool(
        "apply_notes_and_browser",
        "Notes together with a normal browser window.",
    ),
    tool(
        "show_browser_video",
        "Extract a browser video into a floating player.",
    ),
    tool(
        "restore_previous_layout",
        "Restore the previous window layout.",
    ),
    tool(
        "no_action",
        "Use when the request is unrelated, negated, ambiguous, or unsafe.",
    ),
    {
        "type": "function",
        "function": {
            "name": "apply_custom_scenario",
            "description": "Apply a saved custom PaneCue scenario.",
            "parameters": {
                "type": "object",
                "properties": {
                    "scenario_name": {
                        "type": "string",
                        "enum": SCENARIO_NAMES,
                    }
                },
                "required": ["scenario_name"],
                "additionalProperties": False,
            },
        },
    },
]


def is_russian(text: str) -> bool:
    return bool(re.search(r"[а-яё]", text, flags=re.IGNORECASE))


def variants(text: str) -> list[str]:
    if is_russian(text):
        candidates = [
            text,
            f"PaneCue, {text}",
            f"{text}, пожалуйста",
            f"можешь {text}",
            re.sub(r"[,.!?]", "", text.lower()),
        ]
    else:
        candidates = [
            text,
            f"PaneCue, {text}",
            f"{text}, please",
            f"can you {text}",
            re.sub(r"[,.!?]", "", text.lower()),
        ]
    return list(dict.fromkeys(candidates))


def user_content(request: str) -> str:
    scenarios = (
        "Deep Work (phrases: глубокая работа, focus workspace); "
        "Исследование (phrases: начать исследование, research workspace); "
        "Монтаж (phrases: монтажный режим, editing workspace); "
        "Writing (phrases: режим письма, writing workspace)"
    )
    return (
        "Route this Russian or English request to exactly one PaneCue tool. "
        "Never answer with prose. Use only the supplied tools.\n"
        f"Saved scenarios: {scenarios}\n"
        f"Request: {request}"
    )


def record(
    request: str,
    action: str,
    scenario_name: str | None,
    call_id: str,
) -> dict[str, Any]:
    arguments: dict[str, str] = {}
    if scenario_name is not None:
        arguments["scenario_name"] = scenario_name
    return {
        "messages": [
            {"role": "user", "content": user_content(request)},
            {
                "role": "assistant",
                "tool_calls": [
                    {
                        "id": call_id,
                        "type": "function",
                        "function": {
                            "name": action,
                            "arguments": arguments,
                        },
                    }
                ],
            },
        ],
        "tools": copy.deepcopy(TOOLS),
    }


def split_groups(
    groups: list[tuple[str, list[dict[str, Any]]]],
    seed: int,
) -> dict[str, list[dict[str, Any]]]:
    rng = random.Random(seed)
    shuffled = list(groups)
    rng.shuffle(shuffled)
    total = len(shuffled)
    train_end = max(1, round(total * 0.7))
    valid_end = max(train_end + 1, round(total * 0.85))
    result = {"train": [], "valid": [], "test": []}
    for index, (_, items) in enumerate(shuffled):
        if index < train_end:
            split = "train"
        elif index < valid_end:
            split = "valid"
        else:
            split = "test"
        result[split].extend(items)
    return result


def build_dataset(seed: int) -> dict[str, list[dict[str, Any]]]:
    combined = {"train": [], "valid": [], "test": []}
    categories: list[tuple[str, list[tuple[str, str | None]]]] = [
        (
            action,
            [(phrase, None) for phrase in phrases],
        )
        for action, phrases in ACTION_PHRASES.items()
    ]
    categories.append(("apply_custom_scenario", CUSTOM_PHRASES))

    for category_index, (action, samples) in enumerate(categories):
        groups = []
        for sample_index, (scenario_or_phrase, maybe_phrase) in enumerate(
            samples
        ):
            if action == "apply_custom_scenario":
                scenario_name = scenario_or_phrase
                phrase = maybe_phrase or ""
            else:
                scenario_name = None
                phrase = scenario_or_phrase
            items = [
                record(
                    request=variant,
                    action=action,
                    scenario_name=scenario_name,
                    call_id=f"call_{category_index}_{sample_index}_{variant_index}",
                )
                for variant_index, variant in enumerate(variants(phrase))
            ]
            groups.append((f"{action}:{sample_index}", items))

        split = split_groups(groups, seed + category_index)
        for name in combined:
            combined[name].extend(split[name])

    rng = random.Random(seed)
    for rows in combined.values():
        rng.shuffle(rows)
    return combined


def build_hard_training_dataset(
    seed: int,
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    call_index = 0
    for action, phrases in HARD_TRAINING_PHRASES.items():
        for phrase in phrases:
            for variant in variants(phrase)[:3]:
                rows.append(
                    record(
                        request=variant,
                        action=action,
                        scenario_name=None,
                        call_id=f"hard_{call_index}",
                    )
                )
                call_index += 1

    for scenario_name, phrase in CUSTOM_PHRASES[:12]:
        for variant in variants(phrase)[:2]:
            rows.append(
                record(
                    request=variant,
                    action="apply_custom_scenario",
                    scenario_name=scenario_name,
                    call_id=f"hard_{call_index}",
                )
            )
            call_index += 1

    random.Random(seed).shuffle(rows)
    return rows


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(
                json.dumps(row, ensure_ascii=False, separators=(",", ":"))
            )
            handle.write("\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("training/data"),
    )
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    dataset = build_dataset(args.seed)
    for split, rows in dataset.items():
        write_jsonl(args.output / f"{split}.jsonl", rows)
        print(f"{split}: {len(rows)} examples")

    hard_output = args.output.parent / "hard-data"
    hard_rows = build_hard_training_dataset(args.seed)
    write_jsonl(hard_output / "train.jsonl", hard_rows)
    write_jsonl(hard_output / "valid.jsonl", dataset["valid"])
    write_jsonl(hard_output / "test.jsonl", dataset["test"])
    print(f"hard train: {len(hard_rows)} examples")


if __name__ == "__main__":
    main()
