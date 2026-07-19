import hashlib
import os
import secrets
import sys
import uuid

import httpx
from fastapi import FastAPI, Header, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from . import catalog, llm_chat, loadout_import, stores, upstream
from .auth import (
    AppTransactionTemporarilyUnavailableError,
    HostedAuthenticationError,
    InvalidAppTransactionError,
    companion_session,
    get_hosted_auth_service,
    get_usage_store,
)
from .config import Settings, get_settings
from .map_data import load_act_one_map
from .models import (
    ActOneMap,
    AppTransactionAuthRequest,
    ChatRequest,
    ChatResponse,
    CompanionAuthResponse,
    HealthResponse,
    ImportedBuild,
    LoadoutImportRequest,
    PositionResponse,
    PositionUpdateRequest,
    RunState,
    RunStateResponse,
)
from .paths import resource_root
from .route_data import GUIDE_VERSION, checkpoint_by_id, load_act_catalog, load_route, load_timed_events
from .walkthrough_data import load_walkthrough, walkthrough_by_id
from .usage import (
    IdempotencyConflictError,
    ImportAlreadyProcessingError,
    QuotaExhaustedError,
)


STATIC_DIR = resource_root() / "backend" / "app" / "static" / "map"

app = FastAPI(title="BG3 Honor Assistant Backend")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost", "http://localhost:8787", "http://127.0.0.1", "http://127.0.0.1:8787"],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type", "Idempotency-Key"],
)
app.mount("/map-assets", StaticFiles(directory=STATIC_DIR), name="map-assets")


@app.middleware("http")
async def enforce_backend_mode(request: Request, call_next):
    mode = get_settings().backend_mode
    path = request.url.path
    if mode == "hosted" and path != "/health" and not path.startswith("/v1/"):
        return JSONResponse(status_code=404, content={"detail": "Not found."})
    if mode == "local" and path.startswith("/v1/"):
        return JSONResponse(status_code=404, content={"detail": "Not found."})
    return await call_next(request)


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
    settings = get_settings()
    session = companion_session.status()
    authenticated = session.authenticated if settings.upstream_backend_url else False
    ai_available = authenticated if settings.upstream_backend_url else bool(settings.openrouter_api_key)
    return HealthResponse(
        ok=True,
        service="bg3-honor-assistant",
        pid=os.getpid(),
        parent_pid=os.getppid(),
        packaged=bool(getattr(sys, "frozen", False)),
        walkthrough_count=len(load_walkthrough()),
        ai_available=ai_available,
        authenticated=authenticated,
        build_imports=session.build_imports if authenticated else None,
        backend_mode=settings.backend_mode,
    )


@app.put("/_companion/session", response_model=CompanionAuthResponse)
def configure_companion_session(
    request: AppTransactionAuthRequest,
    control_token: str | None = Header(default=None, alias="X-BG3-Companion-Control"),
) -> CompanionAuthResponse:
    settings = get_settings()
    if not settings.upstream_backend_url:
        raise HTTPException(status_code=409, detail="No hosted backend is configured.")
    if not settings.companion_control_token or not control_token or not secrets.compare_digest(
        settings.companion_control_token, control_token
    ):
        raise HTTPException(status_code=404, detail="Not found.")
    try:
        hosted_response = upstream.authenticate(
            settings.upstream_backend_url, request.signed_app_transaction
        )
    except upstream.UpstreamBackendError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
    return companion_session.set(hosted_response)


@app.post("/v1/auth/app-transaction")
def exchange_app_transaction(request: AppTransactionAuthRequest):
    try:
        return get_hosted_auth_service().exchange(request.signed_app_transaction)
    except AppTransactionTemporarilyUnavailableError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except InvalidAppTransactionError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=503, detail="Hosted authentication is not configured.") from exc


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
def import_custom_build(
    request: LoadoutImportRequest,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
    control_token: str | None = Header(default=None, alias="X-BG3-Companion-Control"),
) -> ImportedBuild:
    settings = get_settings()
    if settings.upstream_backend_url:
        _require_companion_control(control_token, settings)
        access_token = companion_session.access_token()
        if not access_token:
            raise HTTPException(status_code=401, detail="Authenticate this TestFlight installation before importing builds.")
        key = _validate_idempotency_key(idempotency_key)
        try:
            result = upstream.import_build(
                settings.upstream_backend_url, request, access_token, key
            )
        except upstream.UpstreamBackendError as exc:
            companion_session.update_quota(access_token, exc.quota)
            if exc.status_code == 401:
                companion_session.clear()
            raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
        imported = result.imported
        companion_session.update_quota(access_token, result.quota)
        if request.persist:
            catalog.save_imported_build(imported)
        return imported
    if not settings.openrouter_api_key:
        raise HTTPException(status_code=428, detail="AI build import is not available right now. Check that the assistant is up to date.")
    imported = _process_build_import(request.url, settings)
    if request.persist:
        catalog.save_imported_build(imported)
    return imported


@app.post("/v1/builds/import", response_model=ImportedBuild)
def hosted_import_build(
    request: LoadoutImportRequest,
    response: Response,
    authorization: str | None = Header(default=None, alias="Authorization"),
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
) -> ImportedBuild:
    if not get_settings().openrouter_api_key:
        raise HTTPException(status_code=503, detail="Hosted AI processing is not configured.")
    subject_id = _authenticate_hosted(authorization, "build-import")
    key = _validate_idempotency_key(idempotency_key)
    request_hash = hashlib.sha256(request.url.strip().encode()).hexdigest()
    usage = get_usage_store()
    try:
        reservation = usage.reserve(subject_id, key, request_hash)
    except QuotaExhaustedError as exc:
        raise HTTPException(
            status_code=403,
            detail=str(exc),
            headers=_quota_headers(usage.quota(subject_id)),
        ) from exc
    except IdempotencyConflictError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except ImportAlreadyProcessingError as exc:
        raise HTTPException(status_code=409, detail=str(exc), headers={"Retry-After": "5"}) from exc

    if reservation.state == "succeeded" and reservation.response_json:
        _set_quota_headers(response, usage.quota(subject_id))
        response.headers["Idempotency-Replayed"] = "true"
        return ImportedBuild.model_validate_json(reservation.response_json)
    if reservation.state == "failed":
        raise HTTPException(
            status_code=reservation.error_status or 502,
            detail=reservation.error_detail or "The earlier build import failed.",
            headers=_quota_headers(usage.quota(subject_id)),
        )

    execution_id = reservation.execution_id
    if not execution_id:
        raise HTTPException(status_code=500, detail="The import reservation is invalid.")
    try:
        imported = _process_build_import(request.url, get_settings())
    except HTTPException as exc:
        usage.complete_failure(subject_id, key, execution_id, exc.status_code, str(exc.detail))
        raise HTTPException(
            status_code=exc.status_code,
            detail=exc.detail,
            headers=_quota_headers(usage.quota(subject_id)),
        ) from exc
    except Exception:
        usage.complete_failure(subject_id, key, execution_id, 500, "The build import failed.")
        raise HTTPException(
            status_code=500,
            detail="The build import failed.",
            headers=_quota_headers(usage.quota(subject_id)),
        )
    usage.complete_success(
        subject_id, key, execution_id, imported.model_dump_json(by_alias=True)
    )
    _set_quota_headers(response, usage.quota(subject_id))
    response.headers["Idempotency-Replayed"] = "false"
    return imported


@app.post("/api/chat", response_model=ChatResponse)
def chat(
    request: ChatRequest,
    control_token: str | None = Header(default=None, alias="X-BG3-Companion-Control"),
) -> ChatResponse:
    settings = get_settings()
    if settings.upstream_backend_url:
        _require_companion_control(control_token, settings)
        access_token = companion_session.access_token()
        if access_token:
            try:
                return upstream.chat(settings.upstream_backend_url, request, access_token)
            except upstream.UpstreamBackendError as exc:
                if exc.status_code == 401:
                    companion_session.clear()
        settings = settings.model_copy(update={"openrouter_api_key": ""})
    return _answer_chat(request, settings)


@app.post("/v1/chat", response_model=ChatResponse)
def hosted_chat(
    request: ChatRequest,
    authorization: str | None = Header(default=None, alias="Authorization"),
) -> ChatResponse:
    _authenticate_hosted(authorization, "chat")
    return _answer_chat(request, get_settings())


def _answer_chat(request: ChatRequest, settings: Settings) -> ChatResponse:
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
    return llm_chat.answer(checkpoint, request, walkthrough_step, settings)


def _process_build_import(url: str, settings: Settings) -> ImportedBuild:
    try:
        return loadout_import.import_build(url, settings)
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


def _authenticate_hosted(authorization: str | None, scope: str) -> str:
    try:
        return get_hosted_auth_service().authenticate(authorization, scope)
    except HostedAuthenticationError as exc:
        raise HTTPException(
            status_code=401,
            detail=str(exc),
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc


def _validate_idempotency_key(value: str | None) -> str:
    try:
        return str(uuid.UUID(value or ""))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="A UUID Idempotency-Key header is required.") from exc


def _set_quota_headers(response: Response, quota) -> None:
    for name, value in _quota_headers(quota).items():
        response.headers[name] = value


def _quota_headers(quota) -> dict[str, str]:
    return {
        "X-Quota-Limit": str(quota.limit),
        "X-Quota-Used": str(quota.used),
        "X-Quota-Remaining": str(quota.remaining),
    }


def _require_companion_control(control_token: str | None, settings: Settings) -> None:
    if (
        not settings.companion_control_token
        or not isinstance(control_token, str)
        or not secrets.compare_digest(settings.companion_control_token, control_token)
    ):
        raise HTTPException(status_code=404, detail="Not found.")


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
