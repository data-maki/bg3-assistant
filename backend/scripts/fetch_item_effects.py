#!/usr/bin/env python3
"""Fetch per-item effect and acquisition text from bg3.wiki.

Reads the gear TSV, queries the wiki's public MediaWiki API for every unique
item of the requested act(s), and merges the results into data/item_effects.json:

    { "<item-key>": {"name", "effect", "acquire", "wiki"} }

- effect  = the lead paragraph's mechanical summary ("what it does")
- acquire = the "Where to find" section, trimmed ("how to get it")
- wiki    = canonical page URL for the detail card's source link

Hand-curated edits to item_effects.json survive re-runs: existing entries are
only overwritten with --force. To expand to Act 2/3, add the act's rows to
build_gear.tsv and run:  python3 scripts/fetch_item_effects.py --act 2

Run from backend/:  python3 scripts/fetch_item_effects.py --act 1
"""

import argparse
import csv
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
GEAR_PATH = REPO_ROOT / "data" / "build_gear.tsv"
EFFECTS_PATH = REPO_ROOT / "data" / "item_effects.json"
API = "https://bg3.wiki/w/api.php"
USER_AGENT = "BG3AssistantLocal/1.0 (personal local companion tool)"

WHERE_TO_FIND = re.compile(
    r"where to find\s*=\s*(.*?)(?=\n\s*\|\s*[a-z_ ]+\s*=|\n}})", re.DOTALL | re.IGNORECASE
)


def item_key(name: str) -> str:
    stripped = re.sub(r"\s*x\d+$", "", name)
    return re.sub(r"[^a-z0-9]+", "-", stripped.lower()).strip("-")


def wiki_title(name: str) -> str:
    return re.sub(r"\s*x\d+$", "", name).strip()


def api_get(params: dict) -> dict:
    query = urllib.parse.urlencode({**params, "format": "json"})
    request = urllib.request.Request(f"{API}?{query}", headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read())


def clean(text: str, limit: int) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) <= limit:
        return text
    cut = text[:limit]
    # end on a sentence when possible, otherwise on a word
    sentence = cut.rsplit(". ", 1)
    if len(sentence[0]) > limit * 0.5:
        return sentence[0].rstrip(".") + "."
    return cut.rsplit(" ", 1)[0] + "…"


def extract_effect(full_text: str) -> str:
    # First paragraph of the lead is the mechanical summary; the second is
    # usually flavour prose. Keep the first only.
    lead = full_text.split("==")[0].strip()
    first_para = next((p for p in lead.split("\n\n") if p.strip()), "")
    return clean(first_para, 240)


def strip_markup(wikitext: str) -> str:
    text = wikitext
    # {{CharLink|Brem}} / {{Quest|Find X}} / {{SmIconLink|..|..|Label}} → best plain argument
    for _ in range(4):  # templates nest a couple of levels at most
        def replace(match: re.Match) -> str:
            args = [a for a in match.group(1).split("|")[1:] if "=" not in a]
            return max(args, key=len, default="")
        text = re.sub(r"\{\{([^{}]*)\}\}", replace, text)
    text = re.sub(r"\[\[[^\]|]*\|([^\]]+)\]\]", r"\1", text)  # [[page|label]] → label
    text = re.sub(r"\[\[([^\]]+)\]\]", r"\1", text)  # [[page]] → page
    text = re.sub(r"<br\s*/?>", "; ", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = text.replace("'''", "").replace("''", "")
    text = re.sub(r"^\s*[*#]+\s*", "• ", text, flags=re.MULTILINE)
    return text


def extract_acquire(name: str) -> str:
    data = api_get({"action": "parse", "page": name, "prop": "wikitext", "redirects": 1})
    wikitext = data["parse"]["wikitext"]["*"]
    match = WHERE_TO_FIND.search(wikitext)
    if not match:
        return ""
    return clean(strip_markup(match.group(1)), 300)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--act", type=int, default=None, help="act to fetch (default: all acts in the TSV)")
    parser.add_argument("--force", action="store_true", help="overwrite existing entries")
    args = parser.parse_args()

    with GEAR_PATH.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    names = sorted({
        wiki_title(row["Item"]) for row in rows
        if (args.act is None or row["Act"] == str(args.act))
        and (row.get("Map objective") or "yes").strip().lower() not in {"no", "false", "0"}
    })

    effects: dict = json.loads(EFFECTS_PATH.read_text()) if EFFECTS_PATH.exists() else {}
    pending = [n for n in names if args.force or item_key(n) not in effects]
    print(f"{len(names)} items in scope, {len(pending)} to fetch")

    missing = []
    for name in pending:
        title = urllib.parse.quote(name)
        try:
            data = api_get({
                "action": "query", "titles": name, "prop": "extracts",
                "explaintext": 1, "exsectionformat": "wiki", "redirects": 1,
            })
            page = next(iter(data["query"]["pages"].values()))
            text = page.get("extract", "")
            if not text:
                missing.append(name)
                continue
            effects[item_key(name)] = {
                "name": name,
                "effect": extract_effect(text),
                "acquire": extract_acquire(name),
                "wiki": f"https://bg3.wiki/wiki/{title.replace('%20', '_')}",
            }
            print(f"  ok  {name}")
        except Exception as error:  # noqa: BLE001 — report and continue
            missing.append(name)
            print(f"  ERR {name}: {error}")
        time.sleep(0.25)

    EFFECTS_PATH.write_text(json.dumps(effects, indent=2, ensure_ascii=False, sort_keys=True) + "\n")
    print(f"wrote {EFFECTS_PATH} ({len(effects)} entries)")
    if missing:
        print("missing (curate by hand):", ", ".join(missing))


if __name__ == "__main__":
    main()
