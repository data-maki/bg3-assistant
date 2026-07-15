import os
import sys

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from . import guide_chat, llm_chat, stores
from .config import get_settings
from .map_data import load_act_one_map
from .models import (
    ActOneMap,
    ChatRequest,
    ChatResponse,
    HealthResponse,
    LatLng,
    PositionResponse,
    PositionUpdateRequest,
    ReadinessRequest,
    ReadinessResponse,
    RunState,
    RunStateResponse,
)
from .paths import resource_root
from .route_data import GUIDE_VERSION, assess_readiness, checkpoint_by_id, load_builds, load_route
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


@app.get("/api/act1/route")
def act_one_route() -> JSONResponse:
    # The Mac app decodes snake_case (convertFromSnakeCase), so this payload
    # dumps by field name rather than by the camelCase web alias.
    return JSONResponse(
        content={
            "guideVersion": GUIDE_VERSION,
            "checkpoints": [item.model_dump(mode="json") for item in load_route()],
            "builds": [item.model_dump(mode="json") for item in load_builds()],
            "walkthrough": [item.model_dump(mode="json") for item in load_walkthrough()],
        }
    )


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
