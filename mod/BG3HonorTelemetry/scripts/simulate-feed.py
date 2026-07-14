#!/usr/bin/env python3
"""Write one test snapshot for local companion QA; never touches BG3 or run state."""

import argparse
import json
import os
import tempfile
import time
import uuid
from pathlib import Path


DEFAULT_PATH = Path.home() / "Library/Application Support/BG3HonorAssistant/telemetry/events.json"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("event", nargs="?", default="combat_entered")
    parser.add_argument("--path", type=Path, default=DEFAULT_PATH)
    parser.add_argument("--actor", default="simulated-player")
    parser.add_argument("--success", choices=("0", "1"), default="1")
    parser.add_argument("--stale", action="store_true")
    parser.add_argument("--duration", type=float, default=0, help="Refresh mtime for bounded live-feed UI QA")
    args = parser.parse_args()

    now = time.time()
    payload = {"success": args.success} if args.event in {"roll_result", "dialog_roll"} else {}
    snapshot = {
        "schema_version": 1,
        "producer_id": "bg3-honor-telemetry",
        "producer_version": "simulator",
        "session_id": f"sim-{uuid.uuid4()}",
        "written_at": now,
        "sequence": 1,
        "events": [{
            "sequence": 1,
            "kind": args.event,
            "emitted_at": now,
            "actor": args.actor,
            "payload": payload,
        }],
    }
    args.path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=args.path.parent, delete=False) as handle:
        json.dump(snapshot, handle, separators=(",", ":"))
        temporary = Path(handle.name)
    os.replace(temporary, args.path)
    if args.stale:
        stale_time = now - 30
        os.utime(args.path, (stale_time, stale_time))
    elif args.duration > 0:
        deadline = time.monotonic() + args.duration
        while time.monotonic() < deadline:
            time.sleep(min(2, max(0, deadline - time.monotonic())))
            os.utime(args.path, None)
    print(args.path)


if __name__ == "__main__":
    main()
