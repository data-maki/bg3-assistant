import os
import sys

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from . import catalog, guide_chat, llm_chat, loadout_import, stores
from .config import get_settings
from .map_data import load_act_map_index, load_act_one_map
from .models import (
    ActGuideSummary,
    ActMapIndex,
    ActOneMap,
    BuildGear,
    ChatRequest,
    ChatResponse,
    HealthResponse,
    ImportedBuild,
    LatLng,
    LoadoutImportRequest,
    PositionResponse,
    PositionUpdateRequest,
    ReadinessRequest,
    ReadinessResponse,
    RunState,
    RunStateResponse,
)
from .paths import resource_root
from .route_data import GUIDE_VERSION, assess_readiness, checkpoint_by_id, load_act_catalog, load_route
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


@app.get("/api/acts", response_model=list[ActGuideSummary])
def acts() -> list[ActGuideSummary]:
    return load_act_catalog()


@app.get("/api/acts/{act}/equipment", response_model=list[BuildGear])
def act_equipment(act: int) -> list[BuildGear]:
    try:
        return catalog.catalog_gear(act)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown act: {act}") from exc


@app.get("/api/items")
def catalog_items(act: int | None = None, slot: str | None = None) -> JSONResponse:
    # Snake_case dump to match the Mac app's convertFromSnakeCase decoder,
    # same style as /api/act1/route.
    return JSONResponse(
        content=[item.model_dump(mode="json") for item in catalog.list_items(act=act, slot=slot)]
    )


@app.get("/api/acts/{act}/map", response_model=ActMapIndex)
def act_map(act: int) -> ActMapIndex:
    try:
        return load_act_map_index(act)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown act: {act}") from exc


@app.get("/api/act1/route")
def act_one_route() -> JSONResponse:
    # The Mac app decodes snake_case (convertFromSnakeCase), so this payload
    # dumps by field name rather than by the camelCase web alias.
    return JSONResponse(
        content={
            "guideVersion": GUIDE_VERSION,
            "checkpoints": [item.model_dump(mode="json") for item in load_route()],
            "builds": [item.model_dump(mode="json") for item in catalog.catalog_builds()],
            "walkthrough": [item.model_dump(mode="json") for item in load_walkthrough()],
            "acts": [item.model_dump(mode="json") for item in load_act_catalog()],
        }
    )


@app.get("/api/builds/custom", response_model=list[ImportedBuild])
def custom_builds() -> list[ImportedBuild]:
    return catalog.imported_builds()


@app.post("/api/builds/import", response_model=ImportedBuild)
def import_custom_build(request: LoadoutImportRequest) -> ImportedBuild:
    settings = get_settings()
    if not settings.openrouter_api_key:
        raise HTTPException(status_code=428, detail="Add an OpenRouter API key in Settings before importing a build.")
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


@app.post("/api/act1/readiness", response_model=ReadinessResponse)
def readiness(request: ReadinessRequest) -> ReadinessResponse:
    try:
        return assess_readiness(request)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown checkpoint: {exc.args[0]}") from exc


@app.post("/api/chat", response_model=ChatResponse)
def chat(request: ChatRequest) -> ChatResponse:
    try:
        checkpoint = checkpoint_by_id(request.checkpoint_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown checkpoint: {exc.args[0]}") from exc
    try:
        walkthrough_step = walkthrough_by_id(request.walkthrough_step_id) if request.walkthrough_step_id else None
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown walkthrough step: {exc.args[0]}") from exc
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
