import os
import sys

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from . import catalog, llm_chat, loadout_import, stores
from .config import get_settings
from .map_data import load_act_one_map
from .models import (
    ActOneMap,
    ChatRequest,
    ChatResponse,
    HealthResponse,
    ImportedBuild,
    LoadoutImportRequest,
    PositionResponse,
    PositionUpdateRequest,
    ReadinessRequest,
    ReadinessResponse,
    RunState,
    RunStateResponse,
)
from .paths import resource_root
from .route_data import GUIDE_VERSION, assess_readiness, checkpoint_by_id, load_act_catalog, load_route, load_timed_events
from .walkthrough_data import load_walkthrough, walkthrough_by_id


STATIC_DIR = resource_root() / "backend" / "app" / "static" / "map"

app = FastAPI(title="BG3 Honor Assistant Backend")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost", "http://localhost:8787", "http://127.0.0.1", "http://127.0.0.1:8787"],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)
app.mount("/map-assets", StaticFiles(directory=STATIC_DIR), name="map-assets")


@app.middleware("http")
async def revalidate_frontend_assets(request: Request, call_next):
    """The frontend ships inside the frozen backend and changes on every
    rebuild; no-cache forces cheap ETag revalidation so the browser can never
    show a stale app against a new API."""
    response = await call_next(request)
    if request.url.path in ("/", "/map") or request.url.path.startswith("/map-assets/"):
        response.headers["Cache-Control"] = "no-cache"
    return response


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(
        ok=True,
        service="bg3-honor-assistant",
        pid=os.getpid(),
        parent_pid=os.getppid(),
        packaged=bool(getattr(sys, "frozen", False)),
        walkthrough_count=len(load_walkthrough()),
        ai_available=bool(get_settings().openrouter_api_key),
    )


@app.get("/", include_in_schema=False)
def root() -> RedirectResponse:
    return RedirectResponse(url="/map")


@app.get("/map", include_in_schema=False)
def act_one_map_page() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/act1/markers", response_model=ActOneMap)
def act_one_markers() -> ActOneMap:
    return load_act_one_map()


@app.get("/api/items")
def catalog_items(act: int | None = None, slot: str | None = None) -> JSONResponse:
    # Snake_case dump to match the Mac app's convertFromSnakeCase decoder,
    # same style as /api/acts/{act}/guide.
    return JSONResponse(
        content=[item.model_dump(mode="json") for item in catalog.list_items(act=act, slot=slot)]
    )


@app.get("/api/acts/{act}/guide")
def act_guide(act: int) -> JSONResponse:
    # The Mac app decodes snake_case (convertFromSnakeCase), so this payload
    # dumps by field name rather than by the camelCase web alias.
    try:
        acts = load_act_catalog()
        guide = next(item for item in acts if item.act == act)
    except (KeyError, StopIteration) as exc:
        raise HTTPException(status_code=404, detail=f"Unknown act: {act}") from exc
    return JSONResponse(
        content={
            "guideVersion": GUIDE_VERSION,
            "act": act,
            "routeAvailable": guide.route_available,
            "checkpoints": [item.model_dump(mode="json") for item in load_route(act)],
            "builds": [item.model_dump(mode="json") for item in catalog.catalog_builds()],
            "walkthrough": [item.model_dump(mode="json") for item in load_walkthrough(act)],
            "timedEvents": [item.model_dump(mode="json") for item in load_timed_events(act)],
            "acts": [item.model_dump(mode="json") for item in acts],
        }
    )


@app.post("/api/builds/import", response_model=ImportedBuild)
def import_custom_build(request: LoadoutImportRequest) -> ImportedBuild:
    settings = get_settings()
    if not settings.openrouter_api_key:
        raise HTTPException(status_code=428, detail="AI build import is not available right now. Check that the assistant is up to date.")
    try:
        imported = loadout_import.import_build(request.url, settings)
    except loadout_import.LoadoutImportError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except httpx.HTTPStatusError as exc:
        status = exc.response.status_code
        if exc.request.url.host == "openrouter.ai":
            detail = {
                401: "OpenRouter rejected the API key.",
                402: "The OpenRouter account needs credits for this import.",
                429: "OpenRouter is rate-limiting imports. Try again shortly.",
            }.get(status, "OpenRouter rejected the request.")
        else:
            detail = "The build page could not be downloaded."
        raise HTTPException(status_code=502, detail=f"{detail} (HTTP {status})") from exc
    except (httpx.HTTPError, KeyError, ValueError) as exc:
        raise HTTPException(status_code=502, detail="The build could not be processed. Try another public URL.") from exc
    catalog.save_imported_build(imported)
    return imported


@app.post("/api/acts/{act}/readiness", response_model=ReadinessResponse)
def act_readiness(act: int, request: ReadinessRequest) -> ReadinessResponse:
    try:
        return assess_readiness(request, act)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown checkpoint: {exc.args[0]}") from exc


@app.post("/api/chat", response_model=ChatResponse)
def chat(request: ChatRequest) -> ChatResponse:
    act = request.context.selected_act if request.context else 1
    try:
        walkthrough_step = walkthrough_by_id(request.walkthrough_step_id, act) if request.walkthrough_step_id else None
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown walkthrough step: {exc.args[0]}") from exc
    checkpoint_id = request.checkpoint_id or (walkthrough_step.checkpoint_id if walkthrough_step else None)
    try:
        checkpoint = checkpoint_by_id(checkpoint_id, act) if checkpoint_id else None
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown checkpoint: {exc.args[0]}") from exc
    if walkthrough_step and checkpoint and walkthrough_step.checkpoint_id != checkpoint.id:
        raise HTTPException(status_code=422, detail="Walkthrough step and checkpoint do not match.")
    if not walkthrough_step and not checkpoint:
        raise HTTPException(status_code=422, detail="A walkthrough step or checkpoint is required.")
    return llm_chat.answer(checkpoint, request, walkthrough_step, get_settings())


@app.get("/api/run-state", response_model=RunStateResponse)
def get_run_state() -> RunStateResponse:
    return RunStateResponse(**stores.current_run_state().model_dump())


@app.post("/api/run-state", response_model=RunStateResponse)
def set_run_state(state: RunState) -> RunStateResponse:
    return RunStateResponse(**stores.save_run_state(state).model_dump())


@app.get("/api/position", response_model=PositionResponse)
def get_position() -> PositionResponse:
    return PositionResponse(ok=True, position=stores.current_position())


@app.post("/api/position", response_model=PositionResponse)
def set_position(request: PositionUpdateRequest) -> PositionResponse:
    position = stores.publish_position(request.lat, request.lng, source=request.source, confidence=1.0)
    return PositionResponse(ok=True, position=position)
