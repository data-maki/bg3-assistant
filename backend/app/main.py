import json
import time
import uuid

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from . import guide_chat, stores
from .config import get_settings
from .map_align import get_aligner
from .map_data import load_act_one_map, overlay_targets
from .marker_sync import marker_sync_preview
from .models import (
    ActOneMap,
    AnalysisResponse,
    ChatRequest,
    ChatResponse,
    HealthResponse,
    LatLng,
    MapAlignResponse,
    MapAlignTarget,
    MarkerSyncConfirmRequest,
    MarkerSyncConfirmResponse,
    MarkerSyncPreview,
    MarkerSyncRequest,
    PositionResponse,
    PositionUpdateRequest,
    ReadinessRequest,
    ReadinessResponse,
    RunState,
    RunStateResponse,
)
from .paths import resource_root
from .route_data import assess_readiness, checkpoint_by_id, load_builds, load_route
from .storage import create_run_dir, save_analysis, save_upload
from .vision import analyze_screenshot


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
    return HealthResponse(ok=True, service="bg3-honor-assistant")


@app.get("/", include_in_schema=False)
def root() -> RedirectResponse:
    return RedirectResponse(url="/map")


@app.get("/map", include_in_schema=False)
def act_one_map_page() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/act1/markers", response_model=ActOneMap)
def act_one_markers() -> ActOneMap:
    return load_act_one_map()


@app.post("/api/marker-sync/preview", response_model=MarkerSyncPreview)
def preview_marker_sync(request: MarkerSyncRequest) -> MarkerSyncPreview:
    preview = marker_sync_preview(request)
    preview.already_synced = stores.marker_sync_confirmed(preview.fingerprint)
    return stores.activate_marker_sync(preview)


@app.post("/api/marker-sync/confirm", response_model=MarkerSyncConfirmResponse)
def confirm_marker_sync(request: MarkerSyncConfirmRequest) -> MarkerSyncConfirmResponse:
    active = stores.current_marker_sync()
    if active is None or active.fingerprint != request.fingerprint:
        raise HTTPException(status_code=409, detail="Marker queue changed; preview it again before confirming.")
    stores.confirm_marker_sync(request.fingerprint)
    return MarkerSyncConfirmResponse(fingerprint=request.fingerprint)


@app.get("/api/act1/route")
def act_one_route() -> JSONResponse:
    # The Mac app decodes snake_case (convertFromSnakeCase), so this payload
    # dumps by field name rather than by the camelCase web alias.
    return JSONResponse(
        content={
            "guideVersion": "2026-07-12",
            "checkpoints": [item.model_dump(mode="json") for item in load_route()],
            "builds": [item.model_dump(mode="json") for item in load_builds()],
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
    return guide_chat.answer(checkpoint, request)


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


@app.post("/api/map-align", response_model=MapAlignResponse)
async def map_align(image: UploadFile = File(...), context: str | None = Form(default=None)) -> MapAlignResponse:
    started = time.perf_counter()
    image_bytes = await image.read()

    aligner = await run_in_threadpool(get_aligner)
    if aligner is None:
        return MapAlignResponse(ok=False, error="Map alignment unavailable: mosaic tile cache could not be built.")

    result = await run_in_threadpool(aligner.align, image_bytes)
    latency_ms = int((time.perf_counter() - started) * 1000)
    if result is None or not result.map_open:
        return MapAlignResponse(
            ok=True, map_open=False, inliers=result.inliers if result else 0, latency_ms=latency_ms
        )

    try:
        context_payload = json.loads(context) if context else {}
    except json.JSONDecodeError:
        context_payload = {}

    width, height = result.image_size
    margin = 40.0
    targets = []
    sync_mode = bool(context_payload.get("use_active_marker_sync"))
    active_sync = stores.current_marker_sync() if sync_mode else None
    if active_sync and stores.marker_sync_confirmed(active_sync.fingerprint):
        active_sync = None
    requested_marker_ids = context_payload.get("marker_ids") or ([marker.id for marker in active_sync.markers] if active_sync else [])
    marker_labels = context_payload.get("marker_labels") or {}
    if active_sync and not marker_labels:
        marker_labels = {marker.id: marker.label for marker in active_sync.markers}
    if requested_marker_ids:
        markers_by_id = {marker.id: marker for marker in load_act_one_map().markers}
        requested_targets = [
            (
                marker.id,
                marker_labels.get(marker.id) or marker.name,
                marker.type,
                marker.danger or "moderate",
                marker.lat,
                marker.lng,
            )
            for marker_id in requested_marker_ids
            if (marker := markers_by_id.get(marker_id)) is not None
        ]
    elif not sync_mode:
        requested_targets = [
            (checkpoint.id, checkpoint.name, "checkpoint", checkpoint.danger, lat, lng)
            for checkpoint, lat, lng in overlay_targets(
                context_payload.get("checkpoint_id"), set(context_payload.get("completed_checkpoint_ids") or [])
            )
        ]
    else:
        requested_targets = []

    for target_id, label, kind, danger, lat, lng in requested_targets:
        x, y = result.latlng_to_screen(lat, lng)
        targets.append(
            MapAlignTarget(
                id=target_id,
                label=label,
                kind=kind,
                danger=danger,
                lat=lat,
                lng=lng,
                x=x,
                y=y,
                on_screen=-margin <= x <= width + margin and -margin <= y <= height + margin,
            )
        )

    center_lat, center_lng = result.center_latlng
    # The BG3 map opens centred on the party, so the aligned view centre is a
    # good approximate live position. Manual pins can still override it.
    stores.publish_position(center_lat, center_lng, source="map-align", confidence=result.confidence, zoom=result.scale)

    return MapAlignResponse(
        ok=True,
        map_open=True,
        inliers=result.inliers,
        confidence=result.confidence,
        zoom=result.scale,
        center=LatLng(lat=center_lat, lng=center_lng),
        position_updated=True,
        targets=targets,
        latency_ms=latency_ms,
    )


@app.post("/analyze", response_model=AnalysisResponse)
async def analyze(image: UploadFile = File(...), context: str | None = Form(default=None)) -> JSONResponse:
    settings = get_settings()
    analysis_id = str(uuid.uuid4())
    started = time.perf_counter()
    image_bytes = await image.read()

    try:
        result = analyze_screenshot(image_bytes, image.content_type, context, settings, load_route())
        response = AnalysisResponse(
            ok=True,
            analysis_id=analysis_id,
            screen_summary=result.screen_summary,
            detected=result.detected,
            candidates=result.candidates,
            confidence=result.confidence,
            latency_ms=int((time.perf_counter() - started) * 1000),
        )
    except Exception as exc:
        response = AnalysisResponse(
            ok=False,
            analysis_id=analysis_id,
            error=f"Screenshot analysis failed: {exc}",
            latency_ms=int((time.perf_counter() - started) * 1000),
        )

    # Screenshots remain in memory by default. Debug capture is explicit.
    if settings.debug_capture:
        run_dir = create_run_dir(settings.runs_dir, analysis_id)
        save_upload(run_dir, image_bytes, image.filename or "screenshot.jpg", image.content_type)
        save_analysis(run_dir, response)
    return JSONResponse(status_code=200, content=response.model_dump(mode="json"))
