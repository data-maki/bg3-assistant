#!/usr/bin/env python3
"""Compile reviewed Python data loaders into one Swift runtime resource."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from app import catalog
from app.route_data import GUIDE_VERSION, load_act_catalog, load_route, load_timed_events
from app.walkthrough_data import load_walkthrough


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "Resources" / "Data" / "guide-bundle.json"
ICON_SOURCE = ROOT / "backend" / "app" / "static" / "map" / "icons"
ICON_OUTPUT = ROOT / "Resources" / "ItemIcons"


def dump(item):
    return item.model_dump(mode="json")


def main() -> None:
    acts = load_act_catalog()
    builds = catalog.catalog_builds()
    payloads = {}
    for act in acts:
        payloads[str(act.act)] = {
            "guideVersion": GUIDE_VERSION,
            "act": act.act,
            "routeAvailable": act.route_available,
            "checkpoints": [dump(item) for item in load_route(act.act)],
            "builds": [dump(item) for item in builds],
            "walkthrough": [dump(item) for item in load_walkthrough(act.act)],
            "timedEvents": [dump(item) for item in load_timed_events(act.act)],
            "acts": [dump(item) for item in acts],
        }

    bundle = {
        "guideVersion": GUIDE_VERSION,
        "payloads": payloads,
        "items": [dump(item) for item in catalog.list_items()],
    }
    OUTPUT.write_text(json.dumps(bundle, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    shutil.copytree(ICON_SOURCE, ICON_OUTPUT, dirs_exist_ok=True)
    print(OUTPUT)


if __name__ == "__main__":
    main()
