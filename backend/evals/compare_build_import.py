#!/usr/bin/env python3
"""Compare strict build extraction between OpenRouter and local Qwen3 4B."""

from __future__ import annotations

import argparse
import json
import re
import time
from pathlib import Path

import httpx
from pydantic import Field, ValidationError

from app.config import get_settings
from app.loadout_import import SYSTEM_PROMPT, _download, _source_text
from app.models import AbilityName, AbilityScores, POINT_BUY_COSTS, PointBuyScores, StrictCamelModel


class ExplicitImportedBuildLevel(StrictCamelModel):
    level: int = Field(ge=1, le=12)
    take: str
    subclass_choice: str
    choices: str
    tactics: str
    confidence: str
    ability_score_reset: AbilityScores | None


class ExplicitImportedBuildGear(StrictCamelModel):
    item: str
    slot: str
    priority: str
    act: int = Field(ge=1, le=3)
    region: str
    acquisition: str
    why: str
    minimum_level: int | None = Field(ge=1, le=12)
    maximum_level: int | None = Field(ge=1, le=12)
    requirement: str
    alternative: str


class ExplicitImportedBuildDraft(StrictCamelModel):
    name: str
    role: str
    final_split: str
    class_progression: str
    point_buy_scores: PointBuyScores
    bonus_two: AbilityName
    bonus_one: AbilityName
    play_pattern: str
    caveat: str
    levels: list[ExplicitImportedBuildLevel]
    gear: list[ExplicitImportedBuildGear]


OLLAMA_URL = "http://127.0.0.1:11434/api/chat"
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
MODEL = "qwen3:4b"
OUTPUT_DIR = Path("/var/folders/xs/ktkn7dys59nf62lflbngs1740000gn/T/opencode/build-evals")

CASES = [
    {
        "id": "bladesinger",
        "url": "https://gamestegy.com/post/bg3/1589/bladesinging-build",
        "classes": ["wizard"],
        "split": ["12"],
    },
    {
        "id": "open-hand-monk",
        "url": "https://tabletopbuilds.com/bg3-honor-build-the-way-of-the-open-hand-monk/",
        "classes": ["fighter", "monk", "cleric", "rogue"],
        "split": ["1", "6", "1", "4"],
    },
    {
        "id": "flamadin",
        "url": "https://eip.gg/bg3/builds/flamadin/",
        "classes": ["druid", "paladin", "sorcerer"],
        "split": ["3", "5", "4"],
    },
    {
        "id": "light-cleric",
        "url": "https://eip.gg/bg3/builds/stars-of-the-circle-light-cleric/",
        "classes": ["cleric", "druid"],
        "split": ["10", "2"],
    },
]

GOLDEN_EXAMPLE = """\
Example source facts:
- Name: Example Storm Sorcerer
- Final build: Storm Sorcerer 10 / Tempest Cleric 2
- Start STR 8, DEX 14, CON 16, INT 8, WIS 12, CHA 16
- Levels 1-5 Sorcerer; level 6 respec Cleric 1 / Sorcerer 5; level 7 Cleric; levels 8-12 Sorcerer.
- Take War Caster at character level 6. Gear: The Spellsparkler from Waukeen's Rest in Act 1.

Correct extraction behavior:
- finalSplit names both classes and exact totals.
- levels uses character levels, not class levels.
- level 6 has take "Tempest Cleric 1" and a complete abilityScoreReset only because the source explicitly says respec.
- The Spellsparkler is the only gear row; no conventional sorcerer items are invented.
- Empty optional text fields are empty strings, never omitted.

Negative examples:
- A page with sections "Level 1" through "Level 12" must not produce only one level row.
- For a respec progression whose final cumulative state is Fighter 1 / Monk 6 / Cleric 1 / Rogue 4, finalSplit is exactly those totals. Do not add historical pre-respec Monk levels and write Monk 8; respec levels replace the old allocation.

BG3 starting-ability validation:
- Remove exactly one +2 and one +1 bonus from two different final abilities.
- The remaining six point-buy values must each be 8-15 and cost exactly 27 total.
- Costs are 8=0, 9=1, 10=2, 11=3, 12=4, 13=5, 14=7, 15=9.
- Example legal monk result: STR 10, DEX 16, CON 15, INT 8, WIS 16, CHA 8. Removing +2 DEX and +1 WIS leaves 10/14/15/8/15/8, which costs 27.

Example schema-valid output for those source facts (abbreviated to three character levels only because the example source has three):
{
  "name": "Example Storm Sorcerer",
  "role": "Lightning damage and control",
  "finalSplit": "Tempest Cleric 1 / Storm Sorcerer 2",
  "classProgression": "Level 1 Sorcerer; level 2 Tempest Cleric; level 3 Sorcerer",
  "pointBuyScores": {"strength": 8, "dexterity": 14, "constitution": 15, "intelligence": 8, "wisdom": 12, "charisma": 14},
  "bonusTwo": "charisma",
  "bonusOne": "constitution",
  "playPattern": "Create wet targets, then use lightning spells.",
  "caveat": "The example source covers only levels 1-3.",
  "levels": [
    {"level": 1, "take": "Storm Sorcerer 1", "subclassChoice": "Storm Sorcery", "choices": "", "tactics": "", "confidence": "Explicit", "abilityScoreReset": null},
    {"level": 2, "take": "Tempest Cleric 1", "subclassChoice": "Tempest Domain", "choices": "", "tactics": "", "confidence": "Explicit", "abilityScoreReset": null},
    {"level": 3, "take": "Storm Sorcerer 2", "subclassChoice": "", "choices": "", "tactics": "", "confidence": "Explicit", "abilityScoreReset": null}
  ],
  "gear": [
    {"item": "The Spellsparkler", "slot": "Quarterstaff", "priority": "Core", "act": 1, "region": "Waukeen's Rest", "acquisition": "Quest reward", "why": "Builds Lightning Charges", "minimumLevel": 1, "maximumLevel": null, "requirement": "", "alternative": ""}
  ]
}
"""

PROMPT = SYSTEM_PROMPT + """

Output contract:
- Return one JSON object and no prose, markdown, or reasoning.
- Include every required property from the schema. Arrays may be empty only when the source truly provides no supported entries.
- `levels[].level` is the total character level after taking that row.
- `levels[].take` names the class and resulting class level, for example `Swords Bard 6`.
- When the source has character-level sections, emit one row for every supported character level in order. Do not collapse a 1-12 guide into only its first or final row.
- `finalSplit` contains every final class and exact class level.
- `pointBuyScores` contains the six 8-15 base values before bonuses and must cost exactly 27 points. `bonusTwo` and `bonusOne` name two different abilities. Never return already-combined scores in `pointBuyScores`.
- `gear` contains source-supported build equipment, supplies, or summoned weapons. Never add a conventional item that the source does not name.
- Prefer omission over invention. Confidence describes source support, not your certainty.

""" + GOLDEN_EXAMPLE


def messages(url: str, text: str, enhanced: bool) -> list[dict[str, str]]:
    reminder = "" if not enhanced else """

END OF UNTRUSTED PAGE TEXT.

Extraction checklist:
1. Re-scan every character-level heading and emit one row per supported level, including explicit feats, spells, and choices.
2. Verify finalSplit class names and totals add to 12 when this is a complete level-12 build.
3. Verify every gear row is explicitly supported by the source; do not add conventional items from memory.
4. Validate pointBuyScores against the exact 27-point cost table and keep the separate +2/+1 bonuses on different abilities.
5. Return only the schema object.
"""
    return [
        {"role": "system", "content": PROMPT if enhanced else SYSTEM_PROMPT},
        {"role": "user", "content": f"SOURCE URL: {url}\n\nPAGE TEXT:\n{text}{reminder}"},
    ]


def openrouter_completion(payload_messages: list[dict], schema: dict) -> str:
    settings = get_settings()
    response = httpx.post(
        OPENROUTER_URL,
        headers={"Authorization": f"Bearer {settings.openrouter_api_key}", "X-Title": "BG3 Build Eval"},
        json={
            "model": settings.openrouter_model,
            "messages": payload_messages,
            "response_format": {
                "type": "json_schema",
                "json_schema": {"name": "bg3_character_build", "strict": True, "schema": schema},
            },
            "reasoning": {"effort": "low", "exclude": True},
            "temperature": 0,
            "max_tokens": 10_000,
        },
        timeout=180,
    )
    response.raise_for_status()
    content = response.json()["choices"][0]["message"]["content"]
    if isinstance(content, list):
        return "".join(part.get("text", "") for part in content if isinstance(part, dict))
    return content


def ollama_completion(payload_messages: list[dict], schema: dict) -> str:
    response = httpx.post(
        OLLAMA_URL,
        json={
            "model": MODEL,
            "messages": payload_messages,
            "stream": False,
            "think": False,
            "format": schema,
            "options": {"temperature": 0, "num_ctx": 32768},
            "keep_alive": "10m",
        },
        timeout=600,
    )
    response.raise_for_status()
    return response.json()["message"]["content"]


def valid_point_buy(draft: ExplicitImportedBuildDraft) -> bool:
    values = draft.point_buy_scores.model_dump().values()
    return draft.bonus_two != draft.bonus_one and sum(POINT_BUY_COSTS[value] for value in values) == 27


def normalized_final_split(draft: ExplicitImportedBuildDraft) -> str:
    raw_levels = [int(value) for value in re.findall(r"\b(\d{1,2})\b", draft.final_split)]
    if sum(raw_levels) == 12:
        return draft.final_split
    class_names = (
        "barbarian", "bard", "cleric", "druid", "fighter", "monk",
        "paladin", "ranger", "rogue", "sorcerer", "warlock", "wizard",
    )
    maxima: dict[str, int] = {}
    order: list[str] = []
    for level in sorted(draft.levels, key=lambda row: row.level):
        class_name = next(
            (name for name in class_names if re.search(rf"\b{name}\b", level.take, re.IGNORECASE)),
            None,
        )
        class_levels = [int(value) for value in re.findall(r"\b(\d{1,2})\b", level.take)]
        if class_name is None or not class_levels:
            continue
        if class_name not in maxima:
            order.append(class_name)
        maxima[class_name] = max(maxima.get(class_name, 0), class_levels[-1])
    if sum(maxima.values()) != 12:
        return draft.final_split
    return " / ".join(f"{name.title()} {maxima[name]}" for name in order)


def semantic_issues(content: str) -> list[str]:
    try:
        draft = ExplicitImportedBuildDraft.model_validate_json(content)
    except ValidationError as error:
        return [f"The JSON does not match the schema: {error}"]
    issues = []
    if not valid_point_buy(draft):
        issues.append(
            "pointBuyScores must cost exactly 27 points and bonusTwo/bonusOne must name different abilities"
        )
    split = normalized_final_split(draft)
    split_levels = [int(value) for value in re.findall(r"\b(\d{1,2})\b", split)]
    if draft.levels and max(level.level for level in draft.levels) == 12 and split_levels and sum(split_levels) != 12:
        issues.append(
            f"the class levels in finalSplit total {sum(split_levels)}, not 12; make finalSplit agree with the final cumulative progression"
        )
    return issues


def repair_ollama(payload_messages: list[dict], schema: dict, content: str, issues: list[str]) -> str:
    repair_messages = [
        {
            "role": "system",
            "content": (
                "Repair a rejected Baldur's Gate 3 build JSON object. Preserve all supported details and change only fields implicated by the validation errors. "
                "For finalSplit, derive the final class totals from the draft's own final cumulative progression. For abilities, use a complete legal 27-point-buy spread "
                "with separate bonusTwo and bonusOne fields while preserving the build's ability priorities. Return only the complete corrected schema object."
            ),
        },
        {
            "role": "user",
            "content": (
                "REJECTED DRAFT:\n"
                + content
                + "\n\nOBJECTIVE ERRORS:\n- "
                + "\n- ".join(issues)
                + "\nCorrect these errors and return the complete object."
            ),
        },
    ]
    return ollama_completion(repair_messages, schema)


def score(case: dict, content: str) -> dict:
    result = {
        "schemaValid": False,
        "legalAbilities": False,
        "classRecall": 0.0,
        "splitTokenRecall": 0.0,
        "levelRows": 0,
        "gearRows": 0,
        "error": None,
    }
    try:
        draft = ExplicitImportedBuildDraft.model_validate_json(content)
    except ValidationError as error:
        result["error"] = str(error)
        return result
    result["schemaValid"] = True
    result["legalAbilities"] = valid_point_buy(draft)
    final_split = normalized_final_split(draft)
    combined = f"{final_split} {draft.class_progression}".casefold()
    result["classRecall"] = sum(token in combined for token in case["classes"]) / len(case["classes"])
    result["splitTokenRecall"] = sum(token in final_split for token in case["split"]) / len(case["split"])
    result["levelRows"] = len(draft.levels)
    result["gearRows"] = len(draft.gear)
    result["name"] = draft.name
    result["finalSplit"] = final_split
    result["abilities"] = {
        "pointBuyScores": draft.point_buy_scores.model_dump(),
        "bonusTwo": draft.bonus_two,
        "bonusOne": draft.bonus_one,
    }
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", choices=["qwen", "gemini", "both"], default="both")
    parser.add_argument("--baseline", action="store_true")
    parser.add_argument("--case")
    args = parser.parse_args()
    providers = ["qwen", "gemini"] if args.provider == "both" else [args.provider]
    schema = ExplicitImportedBuildDraft.model_json_schema(by_alias=True)
    selected = [case for case in CASES if not args.case or case["id"] == args.case]
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    results = []
    for case in selected:
        final_url, content, content_type = _download(case["url"])
        source_text = _source_text(content, content_type)[:60_000]
        for provider in providers:
            started = time.monotonic()
            payload_messages = messages(final_url, source_text, not args.baseline)
            completion = (
                ollama_completion(payload_messages, schema)
                if provider == "qwen"
                else openrouter_completion(payload_messages, schema)
            )
            repairs = 0
            issues = semantic_issues(completion)
            if provider == "qwen" and issues and not args.baseline:
                completion = repair_ollama(payload_messages, schema, completion, issues)
                repairs = 1
                issues = semantic_issues(completion)
            elapsed = round(time.monotonic() - started, 2)
            case_score = score(case, completion)
            record = {
                "case": case["id"], "provider": provider, "seconds": elapsed,
                "repairs": repairs, "remainingIssues": issues, **case_score,
            }
            results.append(record)
            (OUTPUT_DIR / f"{case['id']}-{provider}.json").write_text(completion, encoding="utf-8")
            print(json.dumps(record, sort_keys=True))

    (OUTPUT_DIR / "summary.json").write_text(json.dumps(results, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
