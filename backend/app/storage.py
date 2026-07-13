import json
from pathlib import Path

from .models import AnalysisResponse


def create_run_dir(runs_dir: Path, analysis_id: str) -> Path:
    run_dir = runs_dir / analysis_id
    run_dir.mkdir(parents=True, exist_ok=True)
    return run_dir


def save_upload(run_dir: Path, data: bytes, filename: str, content_type: str | None) -> Path:
    suffix = ".jpg"
    if content_type == "image/png" or filename.lower().endswith(".png"):
        suffix = ".png"
    elif filename.lower().endswith(".jpeg"):
        suffix = ".jpeg"
    path = run_dir / f"screenshot{suffix}"
    path.write_bytes(data)
    return path


def save_analysis(run_dir: Path, response: AnalysisResponse) -> Path:
    path = run_dir / "analysis.json"
    path.write_text(json.dumps(response.model_dump(), indent=2), encoding="utf-8")
    return path
