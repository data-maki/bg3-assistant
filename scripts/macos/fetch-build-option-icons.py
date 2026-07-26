#!/usr/bin/env -S uv run --script
# /// script
# dependencies = [
#   "Pillow>=11,<12",
#   "requests>=2.32,<3",
# ]
# ///
"""Bundle BG3 build-choice icons from bg3.wiki with deterministic fallbacks."""

from __future__ import annotations

import colorsys
import concurrent.futures
import hashlib
import json
import pathlib
import re
import time
import unicodedata
from io import BytesIO

import requests
from PIL import Image, ImageDraw, ImageFont


ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE_FILES = (
    ROOT / "mac/BG3Assistant/ManualBuild.swift",
    ROOT / "mac/BG3Assistant/BG3SpellCatalog.generated.swift",
)
OUTPUT = ROOT / "Resources/BuildOptionIcons"
MANIFEST = OUTPUT / "manifest.json"
API = "https://bg3.wiki/w/api.php"
USER_AGENT = "BG3Overlay/1.0 (fan-content build asset fetcher)"
ABILITIES = ("Strength", "Dexterity", "Constitution", "Intelligence", "Wisdom", "Charisma")
ALIASES = {
    "Shield": "Shield (spell)",
    "Resistance": "Resistance (cantrip)",
    "Light": "Light (cantrip)",
    "Guidance": "Guidance (cantrip)",
    "Blade Ward": "Blade Ward (cantrip)",
    "True Strike": "True Strike (cantrip)",
    "The Hexblade": "Hexblade",
}


def slug(value: str) -> str:
    folded = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", folded).strip("-")


def swift_strings(path: pathlib.Path) -> set[str]:
    source = path.read_text(encoding="utf-8")
    values: set[str] = set()
    for match in re.finditer(r'"(?:\\.|[^"\\])*"', source):
        try:
            value = json.loads(match.group(0))
        except json.JSONDecodeError:
            continue
        if (
            len(value) >= 2
            and "\\(" not in value
            and value[0].isupper() or value.startswith("+")
        ):
            values.add(value)
    return values


def option_names() -> list[str]:
    names = set().union(*(swift_strings(path) for path in SOURCE_FILES))
    names.update(ABILITIES)
    names.update(f"+2 {ability}" for ability in ABILITIES)
    names.update(
        f"+1 {first} / +1 {second}"
        for index, first in enumerate(ABILITIES)
        for second in ABILITIES[index + 1 :]
    )
    return sorted(names)


def query(params: dict[str, str]) -> dict:
    for retry in range(6):
        response = requests.get(
            API,
            params={"format": "json", "formatversion": "2", **params},
            headers={"User-Agent": USER_AGENT},
            timeout=45,
        )
        if response.status_code != 429:
            response.raise_for_status()
            return response.json()
        time.sleep(2 ** (retry + 1))
    raise RuntimeError("bg3.wiki rate limit did not clear")


def batches(values: list[str], size: int = 40):
    for offset in range(0, len(values), size):
        yield values[offset : offset + size]


def artwork_sources(names: list[str]) -> dict[str, dict[str, str]]:
    query_titles: dict[str, list[str]] = {}
    for name in names:
        if name.startswith("+"):
            title = "Ability Improvement"
        elif name in ABILITIES:
            title = "Ability Improvement"
        else:
            title = ALIASES.get(name, name)
        query_titles.setdefault(title, []).append(name)

    result: dict[str, dict[str, str]] = {}
    titles = sorted(query_titles)
    for batch in batches(titles):
        data = query(
            {
                "action": "query",
                "prop": "pageimages",
                "piprop": "thumbnail|original",
                "pithumbsize": "144",
                "titles": "|".join(batch),
            }
        )
        for page in data.get("query", {}).get("pages", []):
            title = page["title"]
            image = page.get("original") or page.get("thumbnail")
            if not image:
                continue
            for name in query_titles.get(title, []):
                result[name] = {
                    "kind": "wiki-page-image",
                    "source_title": title,
                    "source_url": image["source"],
                    "page_url": f"https://bg3.wiki/wiki/{title.replace(' ', '_')}",
                }
        time.sleep(0.15)

    missing_titles = sorted(
        title for title, mapped_names in query_titles.items()
        if not any(name in result for name in mapped_names)
    )
    file_titles = [f"File:{title} Icon.webp" for title in missing_titles]
    for batch in batches(file_titles):
        data = query(
            {
                "action": "query",
                "prop": "imageinfo",
                "iiprop": "url",
                "titles": "|".join(batch),
            }
        )
        for page in data.get("query", {}).get("pages", []):
            info = page.get("imageinfo")
            if not info:
                continue
            title = page["title"].removeprefix("File:").removesuffix(" Icon.webp")
            for name in query_titles.get(title, []):
                result[name] = {
                    "kind": "wiki-file-image",
                    "source_title": page["title"],
                    "source_url": info[0]["url"],
                    "page_url": f"https://bg3.wiki/wiki/{page['title'].replace(' ', '_')}",
                }
        time.sleep(0.15)
    return result


def save_webp(content: bytes, destination: pathlib.Path) -> None:
    with Image.open(BytesIO(content)) as image:
        image.convert("RGBA").resize((144, 144), Image.Resampling.LANCZOS).save(
            destination, "WEBP", quality=88, method=6
        )


def save_fallback(name: str, destination: pathlib.Path) -> None:
    digest = hashlib.sha256(name.encode("utf-8")).digest()
    hue = int.from_bytes(digest[:2], "big") / 65535
    bright = tuple(round(channel * 255) for channel in colorsys.hsv_to_rgb(hue, 0.68, 0.72))
    image = Image.new("RGB", (144, 144), (14, 17, 22))
    draw = ImageDraw.Draw(image)
    for inset in range(60):
        amount = 1 - inset / 80
        color = tuple(round(channel * amount) for channel in bright)
        draw.rounded_rectangle((inset, inset, 143 - inset, 143 - inset), radius=18, outline=color)
    initials = "".join(word[0] for word in re.findall(r"[A-Za-z0-9]+", name)[:2]).upper() or "?"
    font = ImageFont.load_default(size=48)
    bounds = draw.textbbox((0, 0), initials, font=font)
    x = (144 - (bounds[2] - bounds[0])) / 2
    y = (144 - (bounds[3] - bounds[1])) / 2 - bounds[1]
    draw.text((x, y), initials, font=font, fill=(239, 220, 169))
    image.save(destination, "WEBP", quality=88, method=6)


def main() -> None:
    names = option_names()
    sources = artwork_sources(names)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest: dict[str, dict[str, str]] = {}

    def save_option(name: str) -> tuple[str, dict[str, str]]:
        destination = OUTPUT / f"{slug(name)}.webp"
        source = sources.get(name)
        if not destination.exists():
            if source:
                response = requests.get(
                    source["source_url"],
                    headers={"User-Agent": USER_AGENT},
                    timeout=45,
                )
                response.raise_for_status()
                save_webp(response.content, destination)
            else:
                save_fallback(name, destination)
        if source:
            entry = {"filename": destination.name, **source}
        else:
            entry = {
                "filename": destination.name,
                "kind": "generated-fallback",
                "source_title": "",
                "source_url": "",
                "page_url": "",
            }
        return name, entry

    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        futures = [pool.submit(save_option, name) for name in names]
        for index, future in enumerate(concurrent.futures.as_completed(futures), start=1):
            name, entry = future.result()
            manifest[name] = entry
            if index % 75 == 0:
                print(f"Saved {index}/{len(names)} icons", flush=True)
    MANIFEST.write_text(
        json.dumps(
            {
                "generated_by": "scripts/macos/fetch-build-option-icons.py",
                "source": "https://bg3.wiki",
                "options": manifest,
            },
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    exact = sum(item["kind"] != "generated-fallback" for item in manifest.values())
    print(f"Wrote {len(manifest)} icons to {OUTPUT} ({exact} sourced, {len(manifest) - exact} fallbacks)")


if __name__ == "__main__":
    main()
